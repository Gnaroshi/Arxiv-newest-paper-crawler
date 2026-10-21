import Foundation

public struct ExcludedPaper: Codable, Equatable, Sendable {
    public var excludedAt: Date
    public var batchID: String
    public var reason: String
    public var metadataDeleted: Bool? = nil
}

public struct TopicCleanupState: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var excluded: [String: ExcludedPaper] = [:]
    public init() {}

    public var latestBatchID: String? {
        excluded.values.filter { $0.metadataDeleted != true }.max { $0.excludedAt < $1.excludedAt }?.batchID
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
    public var researchTopics: [ResearchTopic]? = nil
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
    case metadataUnavailable
    public var errorDescription: String? {
        switch self {
        case .emptyTopics: "Select at least one research topic to keep."
        case .metadataUnavailable: "This metadata has been deleted. Use the pre-change backup to recover it."
        }
    }
}

public extension PaperRepository {
    var cleanupStateURL: URL { rootURL.appendingPathComponent("cleanup-state.json") }
    var trashURL: URL { rootURL.appendingPathComponent("trash.json") }

    func loadTrashPapers() throws -> [Paper] {
        let state = try loadCleanupState()
        return try loadTrashArchive().filter { state.excluded[$0.shortID] != nil && state.excluded[$0.shortID]?.metadataDeleted != true }
    }

    private func loadTrashArchive() throws -> [Paper] {
        guard FileManager.default.fileExists(atPath: trashURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Paper].self, from: Data(contentsOf: trashURL))
    }

    /// Archive first, then tombstones, then compact the live array. A failed write
    /// never loses the last metadata copy; tombstones also suppress rediscovery.
    @discardableResult
    func compactExcludedPapers() throws -> Int {
        let state = try loadCleanupState()
        let papers = try loadPapers()
        let removed = papers.filter { state.excluded[$0.shortID] != nil }
        guard !removed.isEmpty else { return 0 }
        _ = try writeCleanupBackup(batchID: "trash-migration-" + UUID().uuidString)
        let archived = merge(existing: try loadTrashArchive(), discovered: removed)
        try Self.cleanupEncoder.encode(archived).write(to: trashURL, options: .atomic)
        try savePapers(papers.filter { state.excluded[$0.shortID] == nil })
        return removed.count
    }

    func trashPaper(_ paper: Paper, now: Date = Date()) throws {
        _ = try writeCleanupBackup(batchID: "manual-" + UUID().uuidString)
        let archived = merge(existing: try loadTrashArchive(), discovered: [paper])
        try Self.cleanupEncoder.encode(archived).write(to: trashURL, options: .atomic)
        var state = try loadCleanupState()
        state.excluded[paper.shortID] = .init(excludedAt: now, batchID: UUID().uuidString, reason: "Moved to Trash by you")
        try Self.cleanupEncoder.encode(state).write(to: cleanupStateURL, options: .atomic)
        try savePapers(loadPapers().filter { $0.shortID != paper.shortID })
    }

    func deleteTrashedMetadata(_ paperID: String) throws {
        // PDF files, reading notes and a rediscovery tombstone are deliberately kept.
        _ = try writeCleanupBackup(batchID: "delete-" + UUID().uuidString)
        var state = try loadCleanupState()
        guard state.excluded[paperID] != nil else { throw TopicCleanupError.metadataUnavailable }
        state.excluded[paperID]?.metadataDeleted = true
        try Self.cleanupEncoder.encode(state).write(to: cleanupStateURL, options: .atomic)
        let remaining = try loadTrashArchive().filter { $0.shortID != paperID }
        try Self.cleanupEncoder.encode(remaining).write(to: trashURL, options: .atomic)
        try savePapers(loadPapers().filter { $0.shortID != paperID })
    }

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
        state: TopicCleanupState,
        researchTopics: [ResearchTopic]? = nil
    ) throws -> TopicCleanupPreview {
        let rules = researchTopics ?? ResearchTopic.defaults.filter { topics.map(\.rawValue).contains($0.id) }
        guard !rules.isEmpty, rules.allSatisfy(\.isValid) else { throw TopicCleanupError.emptyTopics }
        var preview = TopicCleanupPreview(topics: topics, totalCount: papers.count, relatedCount: 0, protectedCount: 0, alreadyExcludedCount: 0, candidates: [])
        preview.researchTopics = rules
        let localPDFs = try existingPDFURLs(for: papers, preferredStyle: .title)
        for paper in papers {
            if state.excluded[paper.shortID] != nil {
                preview.alreadyExcludedCount += 1
            } else if rules.contains(where: { $0.matches(paper) }) {
                preview.relatedCount += 1
            } else {
                let progress = library.progress(for: paper.shortID)
                let userWork = progress.disposition != .inbox
                    || progress.savedAt != nil || progress.reviewedAt != nil
                    || progress.firstViewedAt != nil
                    || !progress.collectionIDs.isEmpty
                    || !progress.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || paper.abstractKO?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    || localPDFs[paper.shortID] != nil
                if userWork {
                    preview.protectedCount += 1
                } else {
                    preview.candidates.append(.init(
                        paperID: paper.shortID,
                        title: paper.title,
                        reason: "Unread Inbox paper with no selected topic evidence in its title or abstract"
                    ))
                }
            }
        }
        return preview
    }

    func previewTopicCleanup(topics: [SmartTopic], researchTopics: [ResearchTopic]? = nil) throws -> TopicCleanupPreview {
        try previewTopicCleanup(topics: topics, papers: loadPapers(), library: loadLibraryState(), state: loadCleanupState(), researchTopics: researchTopics)
    }

    func applyTopicCleanup(topics: [SmartTopic], applicationVersion: String, now: Date = Date(), researchTopics: [ResearchTopic]? = nil) throws -> TopicCleanupResult {
        let preview = try previewTopicCleanup(topics: topics, researchTopics: researchTopics)
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
        let candidates = Set(preview.candidates.map(\.paperID))
        let papers = try loadPapers()
        let archived = merge(existing: try loadTrashArchive(), discovered: papers.filter { candidates.contains($0.shortID) })
        try encoder.encode(archived).write(to: trashURL, options: .atomic)
        try encoder.encode(state).write(to: cleanupStateURL, options: .atomic)
        try savePapers(papers.filter { !candidates.contains($0.shortID) })
        return result
    }

    @discardableResult
    func restoreLastTopicCleanup() throws -> Int {
        var state = try loadCleanupState()
        guard let batchID = state.latestBatchID else { return 0 }
        _ = try writeCleanupBackup(batchID: "restore-" + UUID().uuidString)
        let before = state.excluded.count
        let restoreIDs = Set(state.excluded.filter { $0.value.batchID == batchID && $0.value.metadataDeleted != true }.keys)
        try savePapers(merge(existing: loadPapers(), discovered: loadTrashArchive().filter { restoreIDs.contains($0.shortID) }))
        state.excluded = state.excluded.filter { !restoreIDs.contains($0.key) }
        try Self.cleanupEncoder.encode(state).write(to: cleanupStateURL, options: .atomic)
        try Self.cleanupEncoder.encode(loadTrashArchive().filter { !restoreIDs.contains($0.shortID) }).write(to: trashURL, options: .atomic)
        return before - state.excluded.count
    }

    func restoreExcludedPaper(_ paperID: String) throws {
        var state = try loadCleanupState()
        guard state.excluded[paperID]?.metadataDeleted != true else { throw TopicCleanupError.metadataUnavailable }
        try savePapers(merge(existing: loadPapers(), discovered: loadTrashArchive().filter { $0.shortID == paperID }))
        state.excluded.removeValue(forKey: paperID)
        try Self.cleanupEncoder.encode(state).write(to: cleanupStateURL, options: .atomic)
        try Self.cleanupEncoder.encode(loadTrashArchive().filter { $0.shortID != paperID }).write(to: trashURL, options: .atomic)
    }

    private func writeCleanupBackup(batchID: String) throws -> URL {
        let url = rootURL.appendingPathComponent("Backups", isDirectory: true).appendingPathComponent("cleanup-" + batchID, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for source in [papersURL, libraryURL, favoritesURL, discoveryHistoryURL, translationUsageURL, cleanupStateURL, trashURL, statusURL] {
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
