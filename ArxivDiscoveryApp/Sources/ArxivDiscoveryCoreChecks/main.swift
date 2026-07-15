import ArxivDiscoveryCore
import Foundation

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw CheckFailure.failed(message) }
}

func paper(abstract: String, translation: String?) -> Paper {
    Paper(
        entryID: "https://arxiv.org/abs/2607.12345",
        shortID: "2607.12345",
        title: "Example",
        authors: ["Alice"],
        subjects: ["cs.AI"],
        abstract: abstract,
        abstractKO: translation,
        pdfURL: "https://arxiv.org/pdf/2607.12345.pdf",
        publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
        crawledAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func checkFeedParser() throws {
    let feed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <entry>
        <id>https://arxiv.org/abs/2607.12345v2</id>
        <published>2026-07-15T01:02:03Z</published>
        <title>  Example   Paper  </title>
        <summary>First line.\nSecond line.</summary>
        <author><name>Alice Example</name></author>
        <category term="cs.AI" />
        <link title="pdf" href="https://arxiv.org/pdf/2607.12345v2" type="application/pdf" />
      </entry>
    </feed>
    """
    let papers = try ArxivFeedParser.parse(data: Data(feed.utf8))
    try require(papers.count == 1, "Atom parser should return one paper.")
    try require(papers[0].shortID == "2607.12345", "Stable ID should omit the arXiv version suffix.")
    try require(papers[0].title == "Example Paper", "Title whitespace should be normalized.")
    try require(papers[0].abstract == "First line. Second line.", "Abstract whitespace should be normalized.")
    try require(papers[0].authors == ["Alice Example"], "Authors should be parsed.")
    try require(papers[0].subjects == ["cs.AI"], "Subjects should be parsed.")
}

func checkMerge() throws {
    let repository = PaperRepository(rootURL: try temporaryDirectory())
    let merged = repository.merge(
        existing: [paper(abstract: "Old", translation: "기존 번역")],
        discovered: [paper(abstract: "Updated", translation: nil)]
    )
    try require(merged.count == 1, "Merge should de-duplicate by stable arXiv ID.")
    try require(merged[0].abstract == "Updated", "Merge should keep current public metadata.")
    try require(merged[0].abstractKO == "기존 번역", "Merge should preserve an existing translation.")
}

func checkLegacyImport() throws {
    let root = try temporaryDirectory()
    let legacy = try temporaryDirectory()
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: legacy)
    }
    let repository = PaperRepository(rootURL: root)
    let source = legacy.appendingPathComponent("papers.json")
    let favorites = legacy.appendingPathComponent("favorites.json")
    try JSONEncoder.compatible.encode([paper(abstract: "Legacy", translation: nil)]).write(to: source)
    try JSONEncoder.compatible.encode(["2607.12345"]).write(to: favorites)
    let original = try Data(contentsOf: source)

    let result = try repository.importLegacy(papers: source)
    try require(result.importedPaperCount == 1, "Legacy import should report the new paper.")
    try require(result.importedFavoriteCount == 1, "Legacy import should report sibling favorites.")
    try require(try repository.loadPapers().count == 1, "Imported papers should persist.")
    try require(try repository.loadFavorites() == ["2607.12345"], "Imported favorites should persist.")
    try require(try Data(contentsOf: source) == original, "Legacy source should not be modified.")
}

func checkLibraryWorkflow() throws {
    var state = LibraryState()
    state.markViewed("paper-a", at: Date(timeIntervalSince1970: 100))
    try require(state.progress(for: "paper-a").firstViewedAt != nil, "Opening an abstract should record first view.")
    state.markReviewed("paper-a", at: Date(timeIntervalSince1970: 200))
    try require(state.progress(for: "paper-a").disposition == .reviewed, "Reviewed papers should leave Inbox.")
    state.setSaved(true, paperID: "paper-a", at: Date(timeIntervalSince1970: 300))
    let collection = try requireValue(state.createCollection(named: "World Models"), "Collection should be created.")
    state.setCollection(collection.id, contains: "paper-a", enabled: true)
    state.setNote("Compare the ablation.", paperID: "paper-a")
    try require(state.savedPaperIDs == ["paper-a"], "Saved IDs should be derived from library state.")
    try require(state.progress(for: "paper-a").collectionIDs == [collection.id], "A paper should belong to a collection.")
    try require(state.progress(for: "paper-a").note == "Compare the ablation.", "Notes should persist in progress state.")
}

func checkDiscoveryHistory() throws {
    var history = DiscoveryHistory()
    history.record(.init(
        day: "2026-07-15",
        lastSearchedAt: Date(timeIntervalSince1970: 100),
        paperCount: 174,
        categories: ["cs.AI", "cs.RO"],
        isComplete: true
    ))
    try require(history.days["2026-07-15"]?.covers(categories: ["cs.AI", "cs.RO"]) == true, "History should track the exact searched subject set.")
    try require(history.days["2026-07-15"]?.covers(categories: ["cs.AI"]) == false, "Changed subjects should require a new search.")
    try require(DiscoveryDate.interval(for: "2026-07-15")?.duration == 86_400, "A discovery day should be a bounded UTC interval.")
}

func checkFilenameAndCache() throws {
    let safe = PaperRepository.safeFilenameStem("  Vision/Language: Action.  ", fallback: "paper")
    try require(safe == "Vision Language Action", "PDF titles should be safe macOS filename stems.")
    let long = String(repeating: "가", count: 200)
    try require(PaperRepository.safeFilenameStem(long, fallback: "paper").lengthOfBytes(using: .utf8) <= 220, "PDF filename stems should stay within the byte budget.")

    let now = Date()
    let oldPaper = Paper(
        entryID: "https://arxiv.org/abs/old.1",
        shortID: "old.1",
        title: "Old",
        authors: [],
        subjects: ["cs.AI"],
        abstract: "Old abstract",
        pdfURL: "https://arxiv.org/pdf/old.1.pdf",
        publishedAt: now.addingTimeInterval(-400 * 86_400),
        crawledAt: now.addingTimeInterval(-30 * 86_400)
    )
    var library = LibraryState()
    library.setNote("Keep", paperID: oldPaper.shortID)
    let repository = PaperRepository(rootURL: try temporaryDirectory())
    try require(repository.prunedPapers([oldPaper], library: library, retentionDays: 60, now: now).count == 1, "Notes should protect a paper from cache pruning.")
    try require(repository.prunedPapers([oldPaper], library: LibraryState(), retentionDays: 60, now: now).isEmpty, "Unowned expired papers should be pruned.")
}

func checkBackupSnapshot() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = PaperRepository(rootURL: root)
    try repository.savePapers([paper(abstract: "Backup", translation: "백업")])
    var library = LibraryState()
    library.setSaved(true, paperID: "2607.12345")
    library.setNote("Private note", paperID: "2607.12345")
    try repository.saveLibraryState(library)
    let snapshot = try repository.makeBackupSnapshot(applicationVersion: "0.4.0")
    try require(snapshot.schemaVersion == 1, "Backup snapshots should be versioned.")
    try require(snapshot.library.progress(for: "2607.12345").note == "Private note", "Backup should preserve the private library state.")
    let encoded = try repository.encodedBackupSnapshot(applicationVersion: "0.4.0")
    let text = String(decoding: encoded, as: UTF8.self)
    try require(!text.contains("gemini-api-key") && !text.contains("/PDFs/"), "Backup should omit credentials and PDF paths.")
}

func requireValue<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw CheckFailure.failed(message) }
    return value
}

private extension JSONEncoder {
    static var compatible: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

do {
    try checkFeedParser()
    try checkMerge()
    try checkLegacyImport()
    try checkLibraryWorkflow()
    try checkDiscoveryHistory()
    try checkFilenameAndCache()
    try checkBackupSnapshot()
    print("ArxivDiscoveryCoreChecks passed (7 checks).")
} catch {
    FileHandle.standardError.write(Data("ArxivDiscoveryCoreChecks failed: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
