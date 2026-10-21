import Foundation

public struct IntegrationSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var providerID: String
    public var providerVersion: String
    public var observedAt: Date
    public var lastRefresh: Date?
    public var paperCount: Int
    public var favoriteCount: Int
    public var availability: String
    public var lastErrorCode: String?

    public init(
        schemaVersion: Int = 1,
        providerID: String = "arxiv-discovery",
        providerVersion: String,
        observedAt: Date = Date(),
        lastRefresh: Date?,
        paperCount: Int,
        favoriteCount: Int,
        availability: String,
        lastErrorCode: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.providerID = providerID
        self.providerVersion = providerVersion
        self.observedAt = observedAt
        self.lastRefresh = lastRefresh
        self.paperCount = paperCount
        self.favoriteCount = favoriteCount
        self.availability = availability
        self.lastErrorCode = lastErrorCode
    }
}

public struct LegacyImportResult: Equatable, Sendable {
    public var importedPaperCount: Int
    public var importedFavoriteCount: Int
}

public struct PaperRepository: Sendable {
    public let rootURL: URL

    public var papersURL: URL { rootURL.appendingPathComponent("papers.json") }
    public var favoritesURL: URL { rootURL.appendingPathComponent("favorites.json") }
    public var libraryURL: URL { rootURL.appendingPathComponent("library.json") }
    public var discoveryHistoryURL: URL { rootURL.appendingPathComponent("discovery-history.json") }
    public var translationUsageURL: URL { rootURL.appendingPathComponent("translation-usage.json") }
    public var statusURL: URL { rootURL.appendingPathComponent("status.json") }
    public var pdfsURL: URL { rootURL.appendingPathComponent("PDFs", isDirectory: true) }
    private var pdfIndexURL: URL { rootURL.appendingPathComponent("pdf-index.json") }

    public init(rootURL: URL = PaperRepository.defaultRootURL()) {
        self.rootURL = rootURL
    }

    public static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("dev.gnaroshi.ArxivDiscovery", isDirectory: true)
    }

    public func loadPapers() throws -> [Paper] {
        guard FileManager.default.fileExists(atPath: papersURL.path) else { return [] }
        return try Self.decoder.decode([Paper].self, from: Data(contentsOf: papersURL))
    }

    public func savePapers(_ papers: [Paper]) throws {
        try ensureRoot()
        try Self.encoder.encode(papers).write(to: papersURL, options: .atomic)
    }

    public func loadFavorites() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: favoritesURL.path) else { return [] }
        let values = try Self.decoder.decode([String].self, from: Data(contentsOf: favoritesURL))
        return Set(values)
    }

    public func saveFavorites(_ favorites: Set<String>) throws {
        try ensureRoot()
        try Self.encoder.encode(favorites.sorted()).write(to: favoritesURL, options: .atomic)
    }

    public func loadLibraryState() throws -> LibraryState {
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            return try Self.decoder.decode(LibraryState.self, from: Data(contentsOf: libraryURL))
        }
        var migrated = LibraryState()
        for paperID in try loadFavorites() {
            migrated.setSaved(true, paperID: paperID, at: Date(timeIntervalSince1970: 0))
        }
        return migrated
    }

    public func saveLibraryState(_ state: LibraryState) throws {
        try ensureRoot()
        try Self.encoder.encode(state).write(to: libraryURL, options: .atomic)
        try saveFavorites(state.savedPaperIDs)
    }

    public func loadDiscoveryHistory() throws -> DiscoveryHistory {
        guard FileManager.default.fileExists(atPath: discoveryHistoryURL.path) else { return DiscoveryHistory() }
        return try Self.decoder.decode(DiscoveryHistory.self, from: Data(contentsOf: discoveryHistoryURL))
    }

    public func saveDiscoveryHistory(_ history: DiscoveryHistory) throws {
        try ensureRoot()
        try Self.encoder.encode(history).write(to: discoveryHistoryURL, options: .atomic)
    }

    public func loadTranslationUsage() throws -> TranslationUsageLedger {
        guard FileManager.default.fileExists(atPath: translationUsageURL.path) else { return TranslationUsageLedger() }
        return try Self.decoder.decode(TranslationUsageLedger.self, from: Data(contentsOf: translationUsageURL))
    }

    public func saveTranslationUsage(_ usage: TranslationUsageLedger) throws {
        try ensureRoot()
        try Self.encoder.encode(usage).write(to: translationUsageURL, options: .atomic)
    }

    public func merge(existing: [Paper], discovered: [Paper]) -> [Paper] {
        var byID = Dictionary(existing.map { ($0.shortID, $0) }, uniquingKeysWith: { first, last in last.merging(preserving: first) })
        for paper in discovered {
            if let previous = byID[paper.shortID] {
                byID[paper.shortID] = paper.merging(preserving: previous)
            } else {
                byID[paper.shortID] = paper
            }
        }
        return byID.values.sorted { lhs, rhs in
            if lhs.publishedAt == rhs.publishedAt { return lhs.shortID < rhs.shortID }
            return lhs.publishedAt > rhs.publishedAt
        }
    }

    public func importLegacy(papers sourcePapersURL: URL) throws -> LegacyImportResult {
        let imported = try Self.decoder.decode([Paper].self, from: Data(contentsOf: sourcePapersURL))
        let existing = try loadPapers()
        let merged = merge(existing: existing, discovered: imported)
        try savePapers(merged)

        let siblingFavorites = sourcePapersURL.deletingLastPathComponent().appendingPathComponent("favorites.json")
        var importedFavoriteCount = 0
        if FileManager.default.fileExists(atPath: siblingFavorites.path) {
            let importedFavorites = try Self.decoder.decode([String].self, from: Data(contentsOf: siblingFavorites))
            importedFavoriteCount = importedFavorites.count
            var state = try loadLibraryState()
            for paperID in importedFavorites { state.setSaved(true, paperID: paperID) }
            try saveLibraryState(state)
        }
        return LegacyImportResult(
            importedPaperCount: max(merged.count - existing.count, 0),
            importedFavoriteCount: importedFavoriteCount
        )
    }

    public func pdfURL(for paper: Paper) -> URL {
        pdfURL(for: paper, style: .arxivID)
    }

    public func pdfURL(for paper: Paper, style: PDFNameStyle) -> URL {
        let stem: String
        switch style {
        case .title:
            stem = Self.safeFilenameStem(paper.title, fallback: paper.shortID)
        case .arxivID:
            stem = Self.safeFilenameStem(paper.shortID, fallback: "paper")
        }
        return pdfsURL.appendingPathComponent("\(stem).pdf")
    }

    public func existingPDFURL(for paper: Paper, preferredStyle: PDFNameStyle) -> URL? {
        try? existingPDFURLs(for: [paper], preferredStyle: preferredStyle)[paper.shortID]
    }

    public func existingPDFURLs(for papers: [Paper], preferredStyle: PDFNameStyle) throws -> [String: URL] {
        guard FileManager.default.fileExists(atPath: pdfsURL.path) else { return [:] }
        let index = try loadPDFIndex()
        let names = Set(index.values)
        var result: [String: URL] = [:]
        for paper in papers {
            if let url = existingPDFURL(for: paper, preferredStyle: preferredStyle, index: index, ownedNames: names) {
                result[paper.shortID] = url
            }
        }
        return result
    }

    private func loadPDFIndex() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: pdfIndexURL.path) else { return [:] }
        return try Self.decoder.decode([String: String].self, from: Data(contentsOf: pdfIndexURL))
    }

    private func existingPDFURL(for paper: Paper, preferredStyle: PDFNameStyle, index: [String: String], ownedNames: Set<String>) -> URL? {
        if let name = index[paper.shortID], name == URL(fileURLWithPath: name).lastPathComponent {
            let owned = pdfsURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: owned.path) { return owned }
        }
        let preferred = pdfURL(for: paper, style: preferredStyle)
        if !ownedNames.contains(preferred.lastPathComponent), FileManager.default.fileExists(atPath: preferred.path) { return preferred }
        let alternate: PDFNameStyle = preferredStyle == .title ? .arxivID : .title
        let fallback = pdfURL(for: paper, style: alternate)
        return !ownedNames.contains(fallback.lastPathComponent) && FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    public func storeDownloadedPDF(from temporaryURL: URL, for paper: Paper, style: PDFNameStyle = .title) throws -> URL {
        try FileManager.default.createDirectory(at: pdfsURL, withIntermediateDirectories: true)
        var index = try loadPDFIndex()
        if let existing = existingPDFURL(for: paper, preferredStyle: style, index: index, ownedNames: Set(index.values)) {
            // Keep the reading copy, including PDF annotations, unchanged.
            index[paper.shortID] = existing.lastPathComponent
            try Self.encoder.encode(index).write(to: pdfIndexURL, options: .atomic)
            return existing
        }
        var destination = pdfURL(for: paper, style: style)
        if FileManager.default.fileExists(atPath: destination.path) {
            // A same-title file may belong to another paper. Never replace it.
            let stem = destination.deletingPathExtension().lastPathComponent
            let collision = pdfsURL.appendingPathComponent("\(stem) [\(Self.safeFilenameStem(paper.shortID, fallback: UUID().uuidString))].pdf")
            guard !FileManager.default.fileExists(atPath: collision.path) else { throw CocoaError(.fileWriteFileExists) }
            destination = collision
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        index[paper.shortID] = destination.lastPathComponent
        try Self.encoder.encode(index).write(to: pdfIndexURL, options: .atomic)
        return destination
    }

    public func prunedPapers(
        _ papers: [Paper],
        library: LibraryState,
        retentionDays: Int,
        now: Date = Date(),
        excludedIDs: Set<String> = []
    ) -> [Paper] {
        let calendar = DiscoveryDate.calendar
        let publicationCutoff = calendar.date(byAdding: .day, value: -max(retentionDays, 30), to: now) ?? now
        let recentFetchCutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        return papers.filter { paper in
            let progress = library.progress(for: paper.shortID)
            let userOwned = progress.disposition == .saved
                || progress.disposition == .reviewed
                || progress.savedAt != nil
                || progress.reviewedAt != nil
                || !progress.collectionIDs.isEmpty
                || !progress.note.isEmpty
                || paper.abstractKO?.isEmpty == false
            let recentlyPublished = paper.publishedAt >= publicationCutoff
            let recentlyFetched = (paper.crawledAt ?? .distantPast) >= recentFetchCutoff
            return userOwned || excludedIDs.contains(paper.shortID) || recentlyPublished || recentlyFetched
        }
    }

    public func makeBackupSnapshot(applicationVersion: String, createdAt: Date = Date()) throws -> ArxivBackupSnapshot {
        try ArxivBackupSnapshot(
            applicationVersion: applicationVersion,
            createdAt: createdAt,
            papers: loadPapers(),
            library: loadLibraryState(),
            discoveryHistory: loadDiscoveryHistory(),
            translationUsage: loadTranslationUsage(),
            cleanupState: loadCleanupState(),
            trashedPapers: loadTrashPapers(),
            readingReview: loadReadingReview()
        )
    }

    public func encodedBackupSnapshot(applicationVersion: String, createdAt: Date = Date()) throws -> Data {
        try Self.encoder.encode(makeBackupSnapshot(applicationVersion: applicationVersion, createdAt: createdAt))
    }

    public func loadStatus() throws -> IntegrationSnapshot? {
        guard FileManager.default.fileExists(atPath: statusURL.path) else { return nil }
        return try Self.decoder.decode(IntegrationSnapshot.self, from: Data(contentsOf: statusURL))
    }

    public func saveStatus(_ status: IntegrationSnapshot) throws {
        try ensureRoot()
        try Self.encoder.encode(status).write(to: statusURL, options: .atomic)
    }

    private func ensureRoot() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    public static func safeFilenameStem(_ value: String, fallback: String) -> String {
        let normalized = value.precomposedStringWithCanonicalMapping
        let replaced = normalized.unicodeScalars.map { scalar -> String in
            if CharacterSet.controlCharacters.contains(scalar) || scalar == "/" || scalar == ":" { return " " }
            return String(scalar)
        }.joined()
        let collapsed = replaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let source = trimmed.isEmpty ? fallback : trimmed
        var result = ""
        for character in source {
            let candidate = result + String(character)
            if candidate.lengthOfBytes(using: .utf8) > 220 { break }
            result = candidate
        }
        let finalValue = result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return finalValue.isEmpty ? "paper" : finalValue
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
