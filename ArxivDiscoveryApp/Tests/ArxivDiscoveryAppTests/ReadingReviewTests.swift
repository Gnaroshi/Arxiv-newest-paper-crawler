import ArxivDiscoveryCore
import XCTest

@testable import ArxivDiscoveryApp

final class ReadingReviewTests: XCTestCase {
    private let now = DiscoveryDate.date(from: "2026-10-21")!.addingTimeInterval(12 * 3600)

    private func paper(
        _ id: String, title: String = "World Models for Robotics",
        abstract: String = "A world model for robot planning."
    ) -> Paper {
        Paper(
            entryID: "https://arxiv.org/abs/\(id)", shortID: id, title: title, authors: ["Author"], subjects: ["cs.RO"],
            abstract: abstract, pdfURL: "https://arxiv.org/pdf/\(id)", publishedAt: now)
    }

    private func plan(
        _ papers: [Paper], state: ReadingReviewState = ReadingReviewState(), library: LibraryState = LibraryState(),
        now: Date? = nil
    ) throws -> DailyReadingPlan {
        try DailyReadingPlan.build(
            papers: papers, library: library, topics: ResearchTopic.defaults,
            index: PaperSearchIndex(papers: papers, topics: ResearchTopic.defaults), state: state,
            now: now ?? self.now, calendar: DiscoveryDate.calendar)
    }

    func testShortlistIsBoundedAndEveryUnreadPaperHasExactlyOneBucket() throws {
        let papers = (0..<20).map { paper("test-\($0)") }
        let value = try plan(papers)
        XCTAssertEqual(value.items.filter { $0.bucket == .readFirst }.count, 5)
        XCTAssertEqual(Set(value.items.map(\.paperID)).count, 20)
        XCTAssertEqual(value.items.count, 20)
        XCTAssertEqual(try plan(papers), value)
    }

    func testUnrelatedPaperIsNotNowButMissingEvidenceNeedsContext() throws {
        let papers = [
            paper("unrelated", title: "Graph Colouring", abstract: "A combinatorial proof."),
            paper("empty", abstract: ""),
        ]
        let value = try plan(papers)
        XCTAssertEqual(value.items.first { $0.paperID == "unrelated" }?.bucket, .notNow)
        XCTAssertEqual(value.items.first { $0.paperID == "empty" }?.bucket, .needsContext)
    }

    func testSavedAndNotesAreReadingIntentNotAutomaticDiscard() throws {
        let papers = [
            paper("saved", title: "A Mathematical Method", abstract: "A proof."),
            paper("note", title: "Another Method", abstract: "A proof."),
        ]
        var library = LibraryState()
        library.setSaved(true, paperID: "saved", at: now)
        library.setNote("Relevant to my work", paperID: "note", at: now)
        let before = library
        let value = try plan(papers, library: library)
        XCTAssertTrue(value.items.allSatisfy { $0.bucket != .notNow })
        XCTAssertEqual(library, before)
    }

    func testManualPinOverridesTopicsAndNotNowSurvivesNextDay() throws {
        let papers = [paper("pin", title: "A Proof", abstract: "A proof."), paper("skip")]
        var state = ReadingReviewState()
        state.choose(.readFirst, for: "pin", now: now)
        state.choose(.notNow, for: "skip", now: now)
        let value = try plan(papers, state: state, now: now.addingTimeInterval(86400))
        XCTAssertEqual(value.items.first { $0.paperID == "pin" }?.bucket, .readFirst)
        XCTAssertEqual(value.items.first { $0.paperID == "skip" }?.bucket, .notNow)
    }

    func testTomorrowExpiresAtLocalMidnightRatherThanUTC() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let beforeMidnight = now.addingTimeInterval(2 * 3600)
        var state = ReadingReviewState()
        state.choose(.tomorrow, for: "later", now: beforeMidnight, calendar: calendar)
        let midnight = try XCTUnwrap(state.decisions["later"]?.reconsiderAt)
        XCTAssertEqual(calendar.component(.hour, from: midnight), 0)
        XCTAssertEqual(state.activeChoice(for: "later", now: midnight.addingTimeInterval(-1)), .tomorrow)
        XCTAssertEqual(state.activeChoice(for: "later", now: midnight), .automatic)
        let papers = [paper("later")]
        let index = PaperSearchIndex(papers: papers, topics: ResearchTopic.defaults)
        let before = try DailyReadingPlan.build(
            papers: papers, library: LibraryState(), topics: ResearchTopic.defaults, index: index, state: state,
            now: beforeMidnight, calendar: calendar)
        let after = try DailyReadingPlan.build(
            papers: papers, library: LibraryState(), topics: ResearchTopic.defaults, index: index, state: state,
            now: midnight, calendar: calendar)
        XCTAssertEqual(before.items.first?.bucket, .notNow)
        XCTAssertEqual(after.items.first?.bucket, .readFirst)
        XCTAssertNotEqual(before.localDay, after.localDay)
    }

    func testReviewedPapersLeaveDailyQueueAndManualRereadCanRestore() throws {
        let papers = [paper("read")]
        var library = LibraryState()
        library.markReviewed("read", at: now)
        XCTAssertTrue(try plan(papers, library: library).items.isEmpty)
        var state = ReadingReviewState()
        state.choose(.readFirst, for: "read", now: now)
        XCTAssertEqual(try plan(papers, state: state, library: library).items.first?.bucket, .readFirst)
    }

    func testRefreshWritesOnlyOwnedRecommendationFileAndNeverLibraryData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PaperRepository(rootURL: root)
        let papers = [paper("one")]
        try repository.savePapers(papers)
        try repository.saveLibraryState(LibraryState())
        let before = try Data(contentsOf: repository.libraryURL)
        let service = ReadingReviewService(repository: repository)
        let value = try await service.refresh(
            papers: papers, library: LibraryState(), topics: ResearchTopic.defaults,
            index: PaperSearchIndex(papers: papers, topics: ResearchTopic.defaults), state: ReadingReviewState(),
            now: now)
        XCTAssertEqual(value.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.dailyReadingURL.path))
        XCTAssertEqual(try Data(contentsOf: repository.libraryURL), before)
        XCTAssertEqual(try repository.loadPapers(), papers)
    }

    func testPinnedPaperIsProtectedFromTopicCleanupAndIncludedInBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PaperRepository(rootURL: root)
        let papers = [paper("pin", title: "Graph Colouring", abstract: "A proof.")]
        try repository.savePapers(papers)
        var state = ReadingReviewState()
        state.choose(.readFirst, for: "pin", now: now)
        try repository.saveReadingReview(state)
        XCTAssertTrue(try repository.previewTopicCleanup(topics: [.vla]).candidates.isEmpty)
        XCTAssertEqual(try repository.makeBackupSnapshot(applicationVersion: "test").readingReview, state)
    }

    func test7000PaperPriorityBuildUsesBoundedLocalWork() throws {
        let papers = (0..<7000).map { paper("test-\($0)") }
        let index = PaperSearchIndex(papers: papers, topics: ResearchTopic.defaults)
        let start = Date()
        let value = try DailyReadingPlan.build(
            papers: papers, library: LibraryState(), topics: ResearchTopic.defaults,
            index: index, state: ReadingReviewState(), now: now)
        let elapsed = Date().timeIntervalSince(start)
        print("7,000-paper local reading priority calculation: \(elapsed)s (model work, not rendering FPS)")
        XCTAssertEqual(value.items.count, 7000)
        XCTAssertEqual(value.items.filter { $0.bucket == .readFirst }.count, 5)
        XCTAssertLessThan(elapsed, 1.5)
    }

    func testExplicitTitleFocusOutranksBroadTopicAndCanRecommendOutsideCurrentTopics() throws {
        let papers = [paper("broad"), paper("focus", title: "Neural ODE Methods", abstract: "Differential equation solvers.")]
        var state = ReadingReviewState()
        state.focusTerms = ["neural ode"]
        state.dailyLimit = 1
        let value = try plan(papers, state: state)
        XCTAssertEqual(value.items.first?.paperID, "focus")
        XCTAssertEqual(value.items.first?.bucket, .readFirst)
        XCTAssertEqual(value.items.first { $0.paperID == "broad" }?.bucket, .skim)
        XCTAssertTrue(value.items.first?.reasons.contains { $0.contains("neural ode") } == true)
    }
}
