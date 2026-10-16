import Foundation

public struct ExcludedPaper: Codable, Equatable, Sendable {
    public var excludedAt: Date
    public var batchID: String
    public var reason: String
}

public struct TopicCleanupState: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var excluded: [String: ExcludedPaper] = [:]
    public init() {}

    public var latestBatchID: String? {
        excluded.values.max { $0.excludedAt < $1.excludedAt }?.batchID
    }
}

public struct TopicCleanupCandidate: Codable, Equatable, Identifiable, Sendable {
    public var paperID: String
    public var title: String
    public var reason: String
    public var id: String { paperID }
}

public struct TopicCleanupPreview: Codable, Equatable, Sendable {
    public var topics: [SmartTopic]
    public var totalCount: Int
    public var relatedCount: Int
    public var protectedCount: Int
    public var alreadyExcludedCount: Int
    public var candidates: [TopicCleanupCandidate]
}

public struct TopicCleanupResult: Codable, Equatable, Sendable {
    public var batchID: String
    public var excludedCount: Int
    public var backupPath: String
    public var preview: TopicCleanupPreview
}

public enum TopicCleanupError: LocalizedError {
    case emptyTopics
    public var errorDescription: String? { "유지할 연구 주제를 하나 이상 선택하세요." }
}

public extension PaperRepository {
    var cleanupStateURL: URL { rootURL.appendingPathComponent("cleanup-state.json") }

    func loadCleanupState() throws -> TopicCleanupState {
        guard FileManager.default.fileExists(atPath: cleanupStateURL.path) else { return TopicCleanupState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TopicCleanupState.self, from: Data(contentsOf: cleanupStateURL))
    }

    func previewTopicCleanup(
        topics: [SmartTopic],
        papers: [Paper],
        library: LibraryState,
        state: TopicCleanupState
    ) throws -> TopicCleanupPreview {
        guard !topics.isEmpty else { throw TopicCleanupError.emptyTopics }
        var preview = TopicCleanupPreview(topics: topics, totalCount: papers.count, relatedCount: 0, protectedCount: 0, alreadyExcludedCount: 0, candidates: [])
        for paper in papers {
            if state.excluded[paper.shortID] != nil {
                preview.alreadyExcludedCount += 1
            } else if topics.contains(where: { $0.matches(paper) }) {
                preview.relatedCount += 1
            } else {
                let progress = library.progress(for: paper.shortID)
                let userWork = progress.disposition != .inbox
                    || progress.firstViewedAt != nil
                    || !progress.collectionIDs.isEmpty
                    || !progress.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || paper.abstractKO?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    || existingPDFURL(for: paper, preferredStyle: .title) != nil
                if userWork {
                    preview.protectedCount += 1
                } else {
                    preview.candidates.append(.init(
                        paperID: paper.shortID,
                        title: paper.title,
                        reason: "제목·초록에 선택한 연구 주제의 근거가 없는 미열람 Inbox 논문"
                    ))
                }
            }
        }
        return preview
    }

    func previewTopicCleanup(topics: [SmartTopic]) throws -> TopicCleanupPreview {
        try previewTopicCleanup(topics: topics, papers: loadPapers(), library: loadLibraryState(), state: loadCleanupState())
    }

    func applyTopicCleanup(topics: [SmartTopic], applicationVersion: String, now: Date = Date()) throws -> TopicCleanupResult {
        let preview = try previewTopicCleanup(topics: topics)
        let batchID = UUID().uuidString
        let backupURL = try writeCleanupBackup(batchID: batchID)
        let encoder = Self.cleanupEncoder
        try encoder.encode(preview).write(to: backupURL.appendingPathComponent("preview.json"), options: .atomic)
        var state = try loadCleanupState()
        for candidate in preview.candidates {
            state.excluded[candidate.paperID] = ExcludedPaper(excludedAt: now, batchID: batchID, reason: candidate.reason)
        }
        let result = TopicCleanupResult(batchID: batchID, excludedCount: preview.candidates.count, backupPath: backupURL.path, preview: preview)
        try encoder.encode(result).write(to: backupURL.appendingPathComponent("result.json"), options: .atomic)
        try encoder.encode(state).write(to: cleanupStateURL, options: .atomic)
        return result
    }

    @discardableResult
    func restoreLastTopicCleanup() throws -> Int {
        var state = try loadCleanupState()
        guard let batchID = state.latestBatchID else { return 0 }
        _ = try writeCleanupBackup(batchID: "restore-" + UUID().uuidString)
        let before = state.excluded.count
        state.excluded = state.excluded.filter { $0.value.batchID != batchID }
        try Self.cleanupEncoder.encode(state).write(to: cleanupStateURL, options: .atomic)
        return before - state.excluded.count
    }

    func restoreExcludedPaper(_ paperID: String) throws {
        var state = try loadCleanupState()
        state.excluded.removeValue(forKey: paperID)
        try Self.cleanupEncoder.encode(state).write(to: cleanupStateURL, options: .atomic)
    }

    private func writeCleanupBackup(batchID: String) throws -> URL {
        let url = rootURL.appendingPathComponent("Backups", isDirectory: true).appendingPathComponent("cleanup-" + batchID, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for source in [papersURL, libraryURL, favoritesURL, discoveryHistoryURL, translationUsageURL, cleanupStateURL, statusURL] {
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: url.appendingPathComponent(source.lastPathComponent))
            }
        }
        return url
    }

    private static var cleanupEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
