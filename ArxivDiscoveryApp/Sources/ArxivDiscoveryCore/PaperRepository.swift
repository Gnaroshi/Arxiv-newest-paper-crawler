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
    public var statusURL: URL { rootURL.appendingPathComponent("status.json") }
    public var pdfsURL: URL { rootURL.appendingPathComponent("PDFs", isDirectory: true) }

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

    public func merge(existing: [Paper], discovered: [Paper]) -> [Paper] {
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.shortID, $0) })
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
            try saveFavorites(try loadFavorites().union(importedFavorites))
        }
        return LegacyImportResult(
            importedPaperCount: max(merged.count - existing.count, 0),
            importedFavoriteCount: importedFavoriteCount
        )
    }

    public func pdfURL(for paper: Paper) -> URL {
        let safeID = paper.shortID.replacingOccurrences(of: "/", with: "_")
        return pdfsURL.appendingPathComponent("\(safeID).pdf")
    }

    public func storeDownloadedPDF(from temporaryURL: URL, for paper: Paper) throws -> URL {
        try FileManager.default.createDirectory(at: pdfsURL, withIntermediateDirectories: true)
        let destination = pdfURL(for: paper)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
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

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
