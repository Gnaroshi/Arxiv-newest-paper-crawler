import Foundation

public enum DiscoveryMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case topics
    case categories

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .topics: "연구 주제"
        case .categories: "arXiv 분야 태그"
        }
    }
}

public extension SmartTopic {
    var searchTerms: [String] {
        switch self {
        case .vla:
            ["vision-language-action", "vision language action", "VLA", "VLAs", "OpenVLA", "SmolVLA"]
        case .worldModels:
            ["world model", "world models", "world modelling", "world modeling", "world-model", "world action model"]
        }
    }

    func evidence(in paper: Paper) -> String? {
        let text = "\(paper.title) \(paper.abstract)".lowercased()
            .replacingOccurrences(of: "[‐‑–—-]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        switch self {
        case .vla:
            if text.contains("vision language action") { return "vision-language-action" }
            if text.contains("openvla") || text.contains("smolvla") { return "VLA policy model" }
            let acronym = text.range(of: #"\bvlas?\b"#, options: .regularExpression) != nil
            let robotics = ["robot", "manipulation", "embodied", "action chunk", "visuomotor"].contains { text.contains($0) }
            return acronym && robotics ? "VLA with robotics context" : nil
        case .worldModels:
            for phrase in ["world model", "world modelling", "world modeling", "world action model"] {
                if text.contains(phrase) { return phrase }
            }
            return nil
        }
    }
}

public extension DiscoveryQuery {
    var searchExpression: String? {
        let scope: String
        switch mode {
        case .topics:
            guard !topics.isEmpty else { return nil }
            let terms = Set(topics.flatMap(\.searchTerms)).sorted()
            scope = terms.map { "(ti:\"\($0)\" OR abs:\"\($0)\")" }.joined(separator: " OR ")
        case .categories:
            guard !categories.isEmpty else { return nil }
            scope = categories.sorted().map { "cat:\($0)" }.joined(separator: " OR ")
        }
        let formatter = DateFormatter()
        formatter.calendar = DiscoveryDate.calendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmm"
        let start = formatter.string(from: interval.start)
        let end = formatter.string(from: interval.end.addingTimeInterval(-60))
        return "(\(scope)) AND submittedDate:[\(start) TO \(end)]"
    }

    func accepts(_ paper: Paper) -> Bool {
        switch mode {
        case .topics: topics.contains { $0.matches(paper) }
        case .categories: !Set(paper.subjects).isDisjoint(with: categories)
        }
    }
}
