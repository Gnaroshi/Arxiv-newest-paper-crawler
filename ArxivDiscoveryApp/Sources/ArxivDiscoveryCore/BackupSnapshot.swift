import Foundation

public struct ArxivBackupSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var applicationID: String
    public var applicationVersion: String
    public var createdAt: Date
    public var papers: [Paper]
    public var library: LibraryState
    public var discoveryHistory: DiscoveryHistory
    public var translationUsage: TranslationUsageLedger

    public init(
        schemaVersion: Int = 1,
        applicationID: String = "arxiv-discovery",
        applicationVersion: String,
        createdAt: Date = Date(),
        papers: [Paper],
        library: LibraryState,
        discoveryHistory: DiscoveryHistory,
        translationUsage: TranslationUsageLedger
    ) {
        self.schemaVersion = schemaVersion
        self.applicationID = applicationID
        self.applicationVersion = applicationVersion
        self.createdAt = createdAt
        self.papers = papers
        self.library = library
        self.discoveryHistory = discoveryHistory
        self.translationUsage = translationUsage
    }
}

public enum PDFNameStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case title
    case arxivID

    public var id: String { rawValue }
}
