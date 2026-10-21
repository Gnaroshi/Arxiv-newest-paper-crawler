import Foundation

/// The same title/abstract rule is used for remote discovery and local filtering.
public struct ResearchTopic: Codable, Hashable, Identifiable, Sendable {
    private static let vlaContext = ["robot", "robotic", "robotics", "manipulation", "embodied", "visuomotor", "action chunk"]
    public var id: String
    public var name: String
    public var anyTerms: [String]
    public var requiredTerms: [String]
    public var excludedTerms: [String]

    public init(id: String = UUID().uuidString, name: String, anyTerms: [String], requiredTerms: [String] = [], excludedTerms: [String] = []) {
        self.id = id
        self.name = name
        self.anyTerms = Self.clean(anyTerms)
        self.requiredTerms = Self.clean(requiredTerms)
        self.excludedTerms = Self.clean(excludedTerms)
    }

    public var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !anyTerms.isEmpty }
    public var signature: String { ([id] + anyTerms.sorted() + ["AND"] + requiredTerms.sorted() + ["NOT"] + excludedTerms.sorted()).joined(separator: "|") }

    public func matches(_ paper: Paper) -> Bool { matches(normalizedText: Self.text(for: paper)) }

    public func matches(normalizedText text: String) -> Bool {
        guard isValid else { return false }
        let contains: (String) -> Bool = { text.contains(" " + Self.normalize($0) + " ") }
        guard !excludedTerms.contains(where: contains), requiredTerms.allSatisfy(contains) else { return false }
        return anyTerms.contains { term in
            if id == SmartTopic.vla.rawValue && ["vla", "vlas"].contains(Self.normalize(term)) {
                return contains(term) && Self.vlaContext.contains(where: contains)
            }
            return contains(term)
        }
    }

    public var searchExpression: String {
        func clause(_ term: String) -> String {
            let safe = Self.normalize(term)
            return "(ti:\"\(safe)\" OR abs:\"\(safe)\")"
        }
        let any = anyTerms.map { term in
            let expression = clause(term)
            guard id == SmartTopic.vla.rawValue, ["vla", "vlas"].contains(Self.normalize(term)) else { return expression }
            // VLA also means Very Large Array in astronomy. Apply the same
            // robotics condition remotely so those pages are never requested.
            return "(\(expression) AND (\(Self.vlaContext.map(clause).joined(separator: " OR "))))"
        }.joined(separator: " OR ")
        let required = requiredTerms.map { " AND " + clause($0) }.joined()
        let excluded = excludedTerms.map { " ANDNOT " + clause($0) }.joined()
        return "(\(any))\(required)\(excluded)"
    }

    public static func normalize(_ value: String) -> String {
        value.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func text(for paper: Paper) -> String { " " + normalize(paper.title + " " + paper.abstract) + " " }
    public static var defaults: [ResearchTopic] {
        SmartTopic.allCases.map { ResearchTopic(id: $0.rawValue, name: $0.label, anyTerms: $0.searchTerms) }
    }

    private static func clean(_ terms: [String]) -> [String] {
        Array(Set(terms.map(normalize).filter { !$0.isEmpty })).sorted()
    }
}

/// Rebuilt when papers or topic rules change, never while a row is rendering.
public struct PaperSearchIndex: Sendable {
    public var textByID: [String: String] = [:]
    public var topicIDsByPaper: [String: Set<String>] = [:]
    public var topicCounts: [String: Int] = [:]

    public init(papers: [Paper], topics: [ResearchTopic]) {
        for paper in papers {
            let topicText = ResearchTopic.text(for: paper)
            textByID[paper.shortID] = ResearchTopic.normalize(paper.title + " " + paper.abstract + " " + paper.authors.joined(separator: " ") + " " + paper.subjects.joined(separator: " "))
            let matches = Set(topics.filter { $0.matches(normalizedText: topicText) }.map(\.id))
            topicIDsByPaper[paper.shortID] = matches
            for id in matches { topicCounts[id, default: 0] += 1 }
        }
    }
}
