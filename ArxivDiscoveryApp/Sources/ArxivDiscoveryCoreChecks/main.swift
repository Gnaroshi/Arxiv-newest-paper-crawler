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
    print("ArxivDiscoveryCoreChecks passed (3 checks).")
} catch {
    FileHandle.standardError.write(Data("ArxivDiscoveryCoreChecks failed: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
