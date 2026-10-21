import Foundation

public enum ReadingBucket: String, Codable, CaseIterable, Identifiable, Sendable {
    case readFirst, skim, notNow, needsContext
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .readFirst: "Read first"
        case .skim: "Skim"
        case .notNow: "Not now"
        case .needsContext: "Needs context"
        }
    }
}

public enum ReadingChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, readFirst, tomorrow, notNow
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .automatic: "Automatic"
        case .readFirst: "Read first"
        case .tomorrow: "Reconsider tomorrow"
        case .notNow: "Not now"
        }
    }
}

public struct ReadingDecision: Codable, Equatable, Sendable {
    public var choice: ReadingChoice
    public var updatedAt: Date
    public var reconsiderAt: Date?
}

public struct ReadingReviewState: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var dailyLimit = 5
    public var focusTerms: [String] = []
    public var decisions: [String: ReadingDecision] = [:]
    public init() {}

    public mutating func choose(
        _ choice: ReadingChoice, for id: String, now: Date = Date(), calendar: Calendar = .current
    ) {
        if choice == .automatic {
            decisions.removeValue(forKey: id)
            return
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        decisions[id] = ReadingDecision(
            choice: choice, updatedAt: now, reconsiderAt: choice == .tomorrow ? tomorrow : nil)
    }

    public var protectedIDs: Set<String> {
        Set(decisions.filter { $0.value.choice == .readFirst || $0.value.choice == .tomorrow }.map(\.key))
    }

    public func activeChoice(for id: String, now: Date = Date()) -> ReadingChoice {
        guard let decision = decisions[id] else { return .automatic }
        if decision.choice == .tomorrow, (decision.reconsiderAt ?? .distantPast) <= now { return .automatic }
        return decision.choice
    }
}

public struct ReadingRecommendation: Codable, Equatable, Identifiable, Sendable {
    public var paperID: String
    public var bucket: ReadingBucket
    public var score: Int
    public var reasons: [String]
    public var id: String { paperID }
}

public struct DailyReadingPlan: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var generatedAt: Date
    public var localDay: String
    public var timeZone: String
    public var topicSignatures: [String]
    public var items: [ReadingRecommendation]

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Local relevance triage, not a scientific-quality or citation-impact score.
    /// Recommendations never mark a paper read, move it, or change its notes.
    public static func build(
        papers: [Paper], library: LibraryState, topics: [ResearchTopic],
        index: PaperSearchIndex, state: ReadingReviewState,
        now: Date = Date(), calendar: Calendar = .current
    ) throws -> DailyReadingPlan {
        var ranked: [(Paper, ReadingRecommendation, Bool)] = []
        let topicIDs = Set(topics.map(\.id))
        let focus = state.focusTerms.map(ResearchTopic.normalize).filter { !$0.isEmpty }
        for (offset, paper) in papers.enumerated() {
            if offset.isMultiple(of: 256) { try Task.checkCancellation() }
            let progress = library.progress(for: paper.shortID)
            let decision = state.decisions[paper.shortID]
            let pin = decision?.choice == .readFirst
            if !pin && (progress.reviewedAt != nil || progress.disposition == .reviewed) { continue }
            var item = ReadingRecommendation(paperID: paper.shortID, bucket: .skim, score: 0, reasons: [])
            if decision?.choice == .notNow {
                item.bucket = .notNow
                item.reasons = ["You chose not to read this now."]
            } else if decision?.choice == .tomorrow, let until = decision?.reconsiderAt, until > now {
                item.bucket = .notNow
                item.reasons = ["Deferred by you until tomorrow."]
            } else if pin {
                item.bucket = .readFirst
                item.score = 1000
                item.reasons = ["Pinned by you."]
            } else if paper.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || paper.abstract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                item.bucket = .needsContext
                item.reasons = ["Title or abstract is missing; relevance cannot be judged safely."]
            } else {
                let title = " " + ResearchTopic.normalize(paper.title) + " "
                let text = index.textByID[paper.shortID] ?? ResearchTopic.normalize(paper.title + " " + paper.abstract)
                let matches = topics.filter { index.topicIDsByPaper[paper.shortID]?.contains($0.id) == true }
                let titleMatch = matches.contains { topic in topic.anyTerms.contains { title.contains(" " + $0 + " ") }
                }
                if !matches.isEmpty {
                    item.score += titleMatch ? 60 : 35
                    item.reasons.append(
                        "\(titleMatch ? "Title and abstract match" : "Abstract matches") \(matches.map(\.name).joined(separator: ", "))."
                    )
                }
                let focusMatches = focus.filter { (" " + text + " ").contains(" " + $0 + " ") }
                if !focusMatches.isEmpty {
                    item.score += 30
                    item.reasons.append("Matches your reading focus: \(focusMatches.joined(separator: ", ")).")
                }
                if progress.savedAt != nil || progress.disposition == .saved {
                    item.score += 60
                    item.reasons.append("Saved by you.")
                }
                if !progress.note.isEmpty {
                    item.score += 60
                    item.reasons.append("You have a reading note.")
                }
                if !progress.collectionIDs.isEmpty {
                    item.score += 40
                    item.reasons.append("In one of your collections.")
                }
                if item.score == 0 {
                    item.bucket = topicIDs.isEmpty && focus.isEmpty ? .needsContext : .notNow
                    item.reasons = [
                        topicIDs.isEmpty && focus.isEmpty
                            ? "Choose research topics or reading-focus phrases first."
                            : "No selected-topic or reading-focus evidence in the title and abstract. This is not a quality judgment."
                    ]
                }
            }
            ranked.append((paper, item, pin))
        }
        ranked.sort {
            if $0.1.score != $1.1.score { return $0.1.score > $1.1.score }
            if $0.0.publishedAt != $1.0.publishedAt { return $0.0.publishedAt > $1.0.publishedAt }
            return $0.0.shortID < $1.0.shortID
        }
        var automaticCount = 0
        let limit = min(20, max(1, state.dailyLimit))
        let items = ranked.map { _, recommendation, pin in
            var value = recommendation
            if !pin, value.bucket == .skim, value.score >= 60, automaticCount < limit {
                value.bucket = .readFirst
                automaticCount += 1
            }
            return value
        }
        return DailyReadingPlan(
            generatedAt: now, localDay: dayKey(now, calendar: calendar),
            timeZone: calendar.timeZone.identifier, topicSignatures: topics.map(\.signature).sorted(), items: items)
    }
}

extension PaperRepository {
    public var readingReviewURL: URL { rootURL.appendingPathComponent("reading-review.json") }
    public var dailyReadingURL: URL { rootURL.appendingPathComponent("daily-reading.json") }

    public func loadReadingReview() throws -> ReadingReviewState {
        guard FileManager.default.fileExists(atPath: readingReviewURL.path) else { return ReadingReviewState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ReadingReviewState.self, from: Data(contentsOf: readingReviewURL))
    }

    public func saveReadingReview(_ state: ReadingReviewState) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: readingReviewURL, options: .atomic)
    }
}

public actor ReadingReviewService {
    private let repository: PaperRepository
    public init(repository: PaperRepository) { self.repository = repository }

    public func refresh(
        papers: [Paper], library: LibraryState, topics: [ResearchTopic], index: PaperSearchIndex,
        state: ReadingReviewState, now: Date = Date(), calendar: Calendar = .current
    ) throws -> DailyReadingPlan {
        let plan = try DailyReadingPlan.build(
            papers: papers, library: library, topics: topics, index: index, state: state, now: now, calendar: calendar)
        try Task.checkCancellation()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(plan).write(to: repository.dailyReadingURL, options: .atomic)
        return plan
    }
}
