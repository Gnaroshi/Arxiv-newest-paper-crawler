import ArxivDiscoveryCore
import Combine
import XCTest
@testable import ArxivDiscoveryApp

@MainActor final class BrowserWorkflowTests: XCTestCase {
    private func fixture(_ count: Int = 80) throws -> (AppViewModel, URL, String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let name = "dev.gnaroshi.ArxivDiscovery.test." + UUID().uuidString
        let settings = AppSettings(defaults: UserDefaults(suiteName: name)!)
        let repository = PaperRepository(rootURL: root)
        let values = (0..<count).map { index in
            Paper(entryID: "https://arxiv.org/abs/test-\(index)", shortID: "test-\(index)",
                  title: index.isMultiple(of: 2) ? "World Models \(index)" : "Vision-Language-Action \(index)",
                  authors: ["Author"], subjects: ["cs.RO"],
                  abstract: index.isMultiple(of: 2) ? "A world model for future prediction." : "A VLA for robot manipulation.",
                  pdfURL: "https://arxiv.org/pdf/test-\(index)", publishedAt: Date())
        }
        try repository.savePapers(values)
        return (AppViewModel(settings: settings, repository: repository, isVerification: true), root, name)
    }

    private func cleanup(_ root: URL, _ suite: String) {
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    private func waitUntilIdle(_ model: AppViewModel) async throws {
        let deadline = Date().addingTimeInterval(5)
        while model.isCleaning || model.isIndexingTopics {
            if Date() >= deadline { XCTFail("An owned operation did not finish"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testTopicSwitchesAreExclusiveAndFastFor7000Papers() throws {
        let (model, root, suite) = try fixture(7000)
        defer { cleanup(root, suite) }
        var worst: TimeInterval = 0
        for _ in 0..<12 {
            let started = Date()
            model.scope = .topic("vla")
            XCTAssertEqual(model.filteredPapers.count, 3500)
            XCTAssertTrue(model.filteredPapers.allSatisfy { $0.title.contains("Vision-Language-Action") })
            model.scope = .topic(SmartTopic.worldModels.rawValue)
            XCTAssertEqual(model.filteredPapers.count, 3500)
            worst = max(worst, Date().timeIntervalSince(started))
        }
        print("Worst pair of 7,000-paper topic switches: \(worst)s")
        XCTAssertLessThan(worst, 0.25)
    }

    func testRepeatedSelectionDoesNotRewriteReadingState() throws {
        let (model, root, suite) = try fixture()
        defer { cleanup(root, suite) }
        model.selectedPaperID = "test-0"
        model.recordSelection()
        let before = try Data(contentsOf: model.repository.libraryURL)
        for _ in 0..<50 { model.recordSelection() }
        XCTAssertEqual(try Data(contentsOf: model.repository.libraryURL), before)
    }

    func testDraftSurvivesTopicSelectionAndSaveThenRevert() throws {
        let (model, root, suite) = try fixture()
        defer { cleanup(root, suite) }
        let paper = try XCTUnwrap(model.papers.first)
        model.noteDrafts.values.update("Unsaved draft", for: paper.shortID, saved: "")
        model.scope = .topic("vla")
        model.selectedPaperID = "test-1"
        model.scope = .all
        model.selectedPaperID = paper.shortID
        XCTAssertEqual(model.noteDrafts.values.text(for: paper.shortID, saved: ""), "Unsaved draft")
        model.saveNote("Unsaved draft", for: paper)
        XCTAssertTrue(model.noteDrafts.values.isEmpty)
        XCTAssertEqual(try model.repository.loadLibraryState().progress(for: paper.shortID).note, "Unsaved draft")
        model.noteDrafts.values.update("Do not save", for: paper.shortID, saved: "Unsaved draft")
        model.noteDrafts.values.discard(paper.shortID)
        XCTAssertEqual(model.noteDrafts.values.text(for: paper.shortID, saved: "Unsaved draft"), "Unsaved draft")
    }

    func testTypingDraftDoesNotInvalidateBrowserOrWriteFiles() throws {
        let (model, root, suite) = try fixture(7000)
        defer { cleanup(root, suite) }
        let before = try Data(contentsOf: model.repository.libraryURL)
        var updates = 0
        let observer = model.objectWillChange.sink { updates += 1 }
        for index in 0..<100 { model.noteDrafts.values.update("Draft \(index)", for: "test-0", saved: "") }
        XCTAssertEqual(updates, 0)
        XCTAssertEqual(try Data(contentsOf: model.repository.libraryURL), before)
        withExtendedLifetime(observer) {}
    }

    func testFailedNoteSaveKeepsDraftAndSavedState() throws {
        let (model, root, suite) = try fixture()
        defer { cleanup(root, suite) }
        let paper = try XCTUnwrap(model.papers.first)
        model.noteDrafts.values.update("Keep this draft", for: paper.shortID, saved: "")
        try FileManager.default.removeItem(at: model.repository.libraryURL)
        try FileManager.default.createDirectory(at: model.repository.libraryURL, withIntermediateDirectories: true)
        model.saveNote("Keep this draft", for: paper)
        XCTAssertEqual(model.library.progress(for: paper.shortID).note, "")
        XCTAssertEqual(model.noteDrafts.values.text(for: paper.shortID, saved: ""), "Keep this draft")
        XCTAssertNotNil(model.noteDrafts.errors[paper.shortID])
    }

    func testCoreCleanupRejectsChangedCandidatesBeforeAnyWrite() throws {
        let (model, root, suite) = try fixture()
        defer { cleanup(root, suite) }
        let before = try Data(contentsOf: model.repository.papersURL)
        XCTAssertThrowsError(try model.repository.applyTopicCleanup(topics: [.vla], applicationVersion: "test", expectedCandidateIDs: ["wrong-item"]))
        XCTAssertEqual(try Data(contentsOf: model.repository.papersURL), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Backups").path))
    }

    func testNewestTopicRulesWinAfterRapidEdits() async throws {
        let (model, root, suite) = try fixture(7000)
        defer { cleanup(root, suite) }
        model.settings.researchTopics = [ResearchTopic(id: "last", name: "First", anyTerms: ["world model"])]
        try await Task.sleep(for: .milliseconds(100))
        model.settings.researchTopics = [ResearchTopic(id: "last", name: "Final", anyTerms: ["vision language action"])]
        try await Task.sleep(for: .milliseconds(100))
        try await waitUntilIdle(model)
        model.scope = .topic("last")
        XCTAssertEqual(model.filteredPapers.count, 3500)
        XCTAssertTrue(model.filteredPapers.allSatisfy { $0.title.contains("Vision-Language-Action") })
    }

    func testCleanupRequiresFreshPreviewAndRestoresOnlyLatestBatch() async throws {
        let (model, root, suite) = try fixture()
        defer { cleanup(root, suite) }
        model.settings.selectedTopicIDs = ["vla"]
        model.scope = .cleanup
        model.previewCleanup()
        try await waitUntilIdle(model)
        XCTAssertEqual(model.cleanupPreview?.candidates.count, 40)
        let before = try model.repository.loadPapers()
        model.settings.selectedTopicIDs = [SmartTopic.worldModels.rawValue]
        model.applyCleanup()
        XCTAssertNotNil(model.cleanupError)
        XCTAssertEqual(try model.repository.loadPapers(), before)
        model.previewCleanup()
        try await waitUntilIdle(model)
        model.applyCleanup()
        try await waitUntilIdle(model)
        XCTAssertEqual(model.activePapers.count, 40)
        XCTAssertEqual(model.excludedCount, 40)
        XCTAssertEqual(model.lastRemovalCount, 40)
        model.restoreLastCleanup()
        try await waitUntilIdle(model)
        XCTAssertEqual(model.activePapers.count, 80)
        XCTAssertEqual(model.excludedCount, 0)
    }

    func testOfflineVerificationNeverDiscoversOrChangesCanonicalLibrary() throws {
        let (model, root, suite) = try fixture()
        defer { cleanup(root, suite) }
        let before = try Data(contentsOf: model.repository.papersURL)
        model.searchSelectedDates()
        XCTAssertFalse(model.isDiscovering)
        XCTAssertFalse(model.geminiConfigured)
        XCTAssertEqual(try Data(contentsOf: model.repository.papersURL), before)
        XCTAssertNotEqual(root, PaperRepository.defaultRootURL())
    }

    func testWorkspaceWidthsCannotClipDetailPane() {
        for width in stride(from: 601.0, through: 2000, by: 1) {
            let metrics = PaperWorkspaceMetrics(width: width)
            XCTAssertLessThanOrEqual(metrics.maximumListWidth + 301, width)
            XCTAssertTrue(metrics.sideBySide)
        }
        XCTAssertFalse(PaperWorkspaceMetrics(width: 600).sideBySide)
        XCTAssertFalse(VerificationLibrary.isValid(PaperRepository.defaultRootURL()))
    }
}
