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
    state.markReviewed("paper-a")
    try require(state.savedPaperIDs == ["paper-a"], "Reviewed must not remove a bookmark.")
    try require(state.progress(for: "paper-a").collectionIDs == [collection.id], "Reviewed must preserve collection membership.")
    state.setSaved(false, paperID: "paper-a")
    try require(state.progress(for: "paper-a").reviewedAt != nil, "Unbookmarking must preserve review history.")
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
    try require(repository.prunedPapers([oldPaper], library: LibraryState(), retentionDays: 60, now: now, excludedIDs: [oldPaper.shortID]).count == 1, "Excluded papers must remain recoverable after discovery cache pruning.")
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

func checkTopicDiscovery() throws {
    let interval = try requireValue(DiscoveryDate.interval(for: "2026-10-01"), "Valid interval")
    let query = DiscoveryQuery(interval: interval)
    let expression = try requireValue(query.searchExpression, "Topic query should exist")
    try require(expression.contains("ti:"), "Topics must filter the remote title/abstract query.")
    try require(!expression.contains("cat:"), "Topic discovery should not collect entire subject categories.")
    let broad = DiscoveryQuery(interval: interval, categories: ["cs.RO"], mode: .categories)
    try require(broad.searchExpression?.contains("cat:cs.RO") == true, "Subject collection must remain an explicit separate mode.")
    try require(DiscoveryQuery(interval: interval, topics: []).searchExpression == nil, "Empty topics must never fall back to broad discovery.")
    try require(query.accepts(paper(abstract: "We introduce a vision-language-action model for robotics.", translation: nil)), "VLA should match.")
    try require(query.accepts(paper(abstract: "Learning latent world modelling for simulation.", translation: nil)), "World modelling variants should match.")
    try require(!query.accepts(paper(abstract: "VLA radio observations of galaxies.", translation: nil)), "The Very Large Array acronym is not robotics VLA.")
    try require(!query.accepts(paper(abstract: "A new image classification loss.", translation: nil)), "Unrelated CV should not enter topic discovery.")
    let legacy = DiscoveryDayRecord(day: "2026-10-01", lastSearchedAt: Date(), paperCount: 500, categories: ["cs.RO"], isComplete: false)
    try require(!legacy.covers(mode: .topics, categories: ["cs.RO"], topics: Set(SmartTopic.allCases)), "Historical subject searches must not mark topics as already searched.")
}

func checkRecoverableCleanup() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = PaperRepository(rootURL: root)
    func fixture(_ id: String, _ abstract: String = "Unrelated graph theorem") -> Paper {
        var value = paper(abstract: abstract, translation: nil)
        value.shortID = id
        value.title = id
        return value
    }
    var translated = fixture("translated")
    translated.abstractKO = "보관할 번역"
    let values = [fixture("unrelated"), fixture("vla", "vision-language-action robot model"), fixture("saved"), fixture("viewed"), fixture("reviewed"), fixture("note"), fixture("pdf"), translated]
    var library = LibraryState()
    library.setSaved(true, paperID: "saved")
    library.markViewed("viewed")
    library.markReviewed("reviewed")
    library.setNote("Keep my work", paperID: "note")
    try repository.savePapers(values)
    try repository.saveLibraryState(library)
    try FileManager.default.createDirectory(at: repository.pdfsURL, withIntermediateDirectories: true)
    let downloaded = repository.pdfURL(for: values[6], style: .title)
    try Data("preserved PDF".utf8).write(to: downloaded)
    let papersBefore = try Data(contentsOf: repository.papersURL)
    let libraryBefore = try Data(contentsOf: repository.libraryURL)
    let preview = try repository.previewTopicCleanup(topics: SmartTopic.allCases)
    try require(preview.candidates.map(\.paperID) == ["unrelated"], "Only unrelated, unread, unowned Inbox papers should be excluded.")
    try require(preview.protectedCount == 6, "Saved/viewed/reviewed/notes/PDFs/translations should all be protected.")
    try require(!FileManager.default.fileExists(atPath: repository.cleanupStateURL.path), "Preview must not mutate state.")
    let result = try repository.applyTopicCleanup(topics: SmartTopic.allCases, applicationVersion: "test")
    try require(result.excludedCount == 1, "Cleanup should apply the preview.")
    try require(FileManager.default.fileExists(atPath: result.backupPath + "/papers.json"), "Backup must exist before exclusion state is committed.")
    try require(try repository.loadPapers().count == values.count - 1, "Trash metadata must leave the live paper array.")
    try require(try repository.loadTrashPapers().map(\.shortID) == ["unrelated"], "Trashed metadata must remain restorable.")
    try require(try Data(contentsOf: URL(fileURLWithPath: result.backupPath).appendingPathComponent("papers.json")) == papersBefore, "The pre-change backup must contain the exact original metadata.")
    try require(try Data(contentsOf: repository.libraryURL) == libraryBefore, "All reading state must remain byte-identical.")
    try require(try repository.previewTopicCleanup(topics: SmartTopic.allCases).candidates.isEmpty, "Repeated cleanup must be idempotent.")
    try require(try repository.restoreLastTopicCleanup() == 1, "Undo should restore the last batch.")
    try require(try repository.loadCleanupState().excluded.isEmpty, "Undo should remove the exclusions.")
    try require(try Set(repository.loadPapers().map(\.shortID)) == Set(values.map(\.shortID)), "Undo must restore the original paper set.")
    try repository.trashPaper(values[5])
    try require(try repository.loadLibraryState().progress(for: "note").note == "Keep my work", "Manual Trash must preserve notes.")
    try repository.restoreExcludedPaper("note")
    try require(try repository.loadPapers().contains { $0.shortID == "note" }, "Individual restore must work.")
    try repository.trashPaper(values[0])
    try repository.deleteTrashedMetadata("unrelated")
    try require(try repository.loadTrashPapers().isEmpty, "Explicit metadata deletion removes the Trash row.")
    try require(try repository.loadCleanupState().excluded["unrelated"] != nil, "Deleted papers must not be silently fetched again.")
    try require(try Data(contentsOf: downloaded) == Data("preserved PDF".utf8), "Cleanup and undo must preserve PDFs.")
}

func checkCustomTopics() throws {
    let topic = ResearchTopic(name: "Battery life", anyTerms: ["cycle life", "state of health"], requiredTerms: ["battery"], excludedTerms: ["survey"])
    try require(topic.matches(paper(abstract: "Predicting battery cycle-life.", translation: nil)), "User phrases must normalize punctuation.")
    try require(!topic.matches(paper(abstract: "Cycle life of stars.", translation: nil)), "Required terms must constrain a topic.")
    try require(!topic.matches(paper(abstract: "A survey of battery state of health.", translation: nil)), "Exclusions must win.")
    let interval = try requireValue(DiscoveryDate.interval(for: "2026-10-01"), "Interval")
    let query = DiscoveryQuery(interval: interval, researchTopics: [topic])
    try require(query.searchExpression?.contains("ANDNOT") == true, "Remote query must carry negative rules.")
    try require(query.accepts(paper(abstract: "battery cycle life", translation: nil)), "Local acceptance uses the same rule.")
    let history = DiscoveryDayRecord(day: "2026-10-01", lastSearchedAt: Date(), paperCount: 1, categories: [], isComplete: true, mode: .topics, researchTopics: [topic])
    var edited = topic
    edited.anyTerms = ["thermal runaway"]
    try require(!history.covers(mode: .topics, categories: [], researchTopics: [edited]), "Editing rules must invalidate old search coverage.")
    let rules = ResearchTopic.defaults
    try require(rules[1].matches(paper(abstract: "Composable World-Action Models for robotics", translation: nil)), "World-action plurals must not be lost by word boundaries.")
    try require(rules[1].matches(paper(abstract: "World-Action Modeling via prediction", translation: nil)), "World-action modeling must remain related.")
    try require(!rules[0].matches(paper(abstract: "VLA radio astronomy.", translation: nil)), "Custom-topic engine must disambiguate the VLA acronym.")
    let values = (0..<7000).map { index -> Paper in
        var value = paper(abstract: index % 2 == 0 ? "robot vision-language-action policy" : "unrelated image classification", translation: nil)
        value.shortID = "fixture-\(index)"
        return value
    }
    let started = Date()
    let index = PaperSearchIndex(papers: values, topics: rules)
    try require(index.topicCounts["vla"] == 3500, "Cached counts must match topic evidence.")
    try require(index.topicIDsByPaper["fixture-1"]?.isEmpty == true, "Unrelated papers must not match.")
    print("Indexed 7,000 fixture papers in \(String(format: "%.3f", Date().timeIntervalSince(started)))s; topic counts are cached.")
}

func checkTrashMigration() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = PaperRepository(rootURL: root)
    let value = paper(abstract: "A world model", translation: nil)
    try repository.savePapers([value])
    try repository.trashPaper(value)
    // Simulate an interrupted old write or a pre-v2 excluded paper still in papers.json.
    try repository.savePapers([value])
    try require(try repository.compactExcludedPapers() == 1, "Old exclusions must migrate out of the live array.")
    try require(try repository.compactExcludedPapers() == 0, "Migration must be idempotent.")
    try require(try repository.loadTrashPapers().count == 1, "Migration must not duplicate archive entries.")
    try require(try repository.makeBackupSnapshot(applicationVersion: "test").trashedPapers?.count == 1, "Private backups must include Trash metadata.")
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
    if let index = CommandLine.arguments.firstIndex(of: "--export-ui-fixture"), CommandLine.arguments.indices.contains(index + 1) {
        try exportUIFixture(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
        exit(EXIT_SUCCESS)
    }
    try checkFeedParser()
    try checkMerge()
    try checkLegacyImport()
    try checkLibraryWorkflow()
    try checkDiscoveryHistory()
    try checkFilenameAndCache()
    try checkBackupSnapshot()
    try checkTopicDiscovery()
    try checkRecoverableCleanup()
    try checkCustomTopics()
    try checkTrashMigration()
    try await checkDiscoveryNetworking()
    print("ArxivDiscoveryCoreChecks passed (11 core groups + discovery network regression suite).")
} catch {
    FileHandle.standardError.write(Data("ArxivDiscoveryCoreChecks failed: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
