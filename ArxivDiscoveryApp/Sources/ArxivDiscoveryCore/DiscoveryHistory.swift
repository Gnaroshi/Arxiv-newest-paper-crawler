import Foundation

public struct DiscoveryDayRecord: Codable, Equatable, Identifiable, Sendable {
    public var day: String
    public var lastSearchedAt: Date
    public var paperCount: Int
    public var categories: [String]
    public var isComplete: Bool
    public var mode: DiscoveryMode?
    public var topics: [SmartTopic]?
    public var topicSignatures: [String]?

    public var id: String { day }

    public init(day: String, lastSearchedAt: Date, paperCount: Int, categories: [String], isComplete: Bool, mode: DiscoveryMode = .categories, topics: [SmartTopic] = [], researchTopics: [ResearchTopic]? = nil) {
        self.day = day
        self.lastSearchedAt = lastSearchedAt
        self.paperCount = paperCount
        self.categories = categories.sorted()
        self.isComplete = isComplete
        self.mode = mode
        self.topics = topics.sorted { $0.rawValue < $1.rawValue }
        self.topicSignatures = researchTopics?.map(\.signature).sorted()
    }

    public func covers(categories expected: Set<String>) -> Bool {
        isComplete && (mode ?? .categories) == .categories && Set(categories) == expected
    }

    public func covers(mode expectedMode: DiscoveryMode, categories expectedCategories: Set<String>, topics expectedTopics: Set<SmartTopic>) -> Bool {
        guard isComplete, (mode ?? .categories) == expectedMode else { return false }
        return expectedMode == .topics ? Set(topics ?? []) == expectedTopics : Set(categories) == expectedCategories
    }

    public func covers(mode: DiscoveryMode, categories: Set<String>, researchTopics: [ResearchTopic]) -> Bool {
        isComplete && matchesScope(mode: mode, categories: categories, researchTopics: researchTopics)
    }

    public func matchesScope(mode: DiscoveryMode, categories: Set<String>, researchTopics: [ResearchTopic]) -> Bool {
        guard (self.mode ?? .categories) == mode else { return false }
        if mode == .categories { return Set(self.categories) == categories }
        return topicSignatures == researchTopics.map(\.signature).sorted()
    }
}

public struct DiscoveryHistory: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var days: [String: DiscoveryDayRecord]

    public init(schemaVersion: Int = 1, days: [String: DiscoveryDayRecord] = [:]) {
        self.schemaVersion = schemaVersion
        self.days = days
    }

    public mutating func record(_ value: DiscoveryDayRecord) {
        days[value.day] = value
    }

    public mutating func prune(keepingDays count: Int = 400, now: Date = Date()) {
        let calendar = DiscoveryDate.calendar
        guard let cutoff = calendar.date(byAdding: .day, value: -max(count, 30), to: now) else { return }
        days = days.filter { key, _ in
            guard let date = DiscoveryDate.date(from: key) else { return false }
            return date >= cutoff
        }
    }
}

public enum DiscoveryDate {
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    public static func key(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    public static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])), Self.key(for: date) == key else { return nil }
        return date
    }

    public static func interval(for key: String) -> DateInterval? {
        guard let start = date(from: key), let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    public static func recentKeys(count: Int, endingAt date: Date = Date()) -> Set<String> {
        Set((0..<max(count, 1)).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: date).map(key(for:))
        })
    }
}
