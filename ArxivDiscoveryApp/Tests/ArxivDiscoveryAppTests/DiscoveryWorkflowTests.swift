import ArxivDiscoveryCore
import XCTest

@testable import ArxivDiscoveryApp

private actor InterruptedClient: ArxivSearching {
    private(set) var offsets: [Int] = []
    private var shouldWait = true

    func discover(query: DiscoveryQuery, now: Date) async throws -> [Paper] {
        try await discoverBatch(query: query, now: now).papers
    }

    func discoverBatch(query: DiscoveryQuery, now: Date) async throws -> ArxivSearchBatch {
        offsets.append(query.start)
        if query.start != 0, shouldWait {
            shouldWait = false
            try await Task.sleep(for: .seconds(60))
        }
        let id = query.start == 0 ? "2610.00001" : "2610.00002"
        let paper = Paper(
            entryID: "https://arxiv.org/abs/\(id)", shortID: id, title: "World Models",
            authors: ["Author"], subjects: ["cs.RO"], abstract: "A world model.", pdfURL: "https://arxiv.org/pdf/\(id)",
            publishedAt: DiscoveryDate.date(from: "2026-10-01")!.addingTimeInterval(12 * 3600), crawledAt: now)
        return ArxivSearchBatch(papers: [paper], isComplete: query.start != 0, rawCount: 1, totalResults: 2)
    }
}

@MainActor final class DiscoveryWorkflowTests: XCTestCase {
    private func fixture() throws -> (AppViewModel, InterruptedClient, URL, String) {
        let root = VerificationLibrary.baseURL.appendingPathComponent("test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        struct Marker: Encodable {
            let schemaVersion = 1
            let offline = true
        }
        try JSONEncoder().encode(Marker()).write(to: root.appendingPathComponent("verification.json"))
        let suite = "dev.gnaroshi.ArxivDiscovery.test." + UUID().uuidString
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.selectedTopicIDs = [SmartTopic.worldModels.rawValue]
        let client = InterruptedClient()
        var policy = DiscoveryPolicy()
        policy.requestSpacing = 0
        policy.totalTimeout = 5
        let model = AppViewModel(
            settings: settings, repository: PaperRepository(rootURL: root), client: client,
            isVerification: true, allowPublicVerificationDiscovery: true, discoveryPolicy: policy)
        model.selectedDiscoveryDays = ["2026-10-01", "2026-10-02"]
        return (model, client, root, suite)
    }

    private func cleanup(_ root: URL, _ suite: String) {
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    private func waitForSecondPage(_ client: InterruptedClient) async throws {
        let deadline = Date().addingTimeInterval(3)
        while await client.offsets.count < 2 {
            guard Date() < deadline else { return XCTFail("Second page was not reached") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func waitForSearch(_ model: AppViewModel) async throws {
        let deadline = Date().addingTimeInterval(3)
        while model.isDiscovering {
            guard Date() < deadline else { return XCTFail("Search did not settle after cancellation/retry") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testCancelAndRetryKeepsEveryUniquePaperAndNeverOverwritesReadingWork() async throws {
        let (model, client, root, suite) = try fixture()
        defer { cleanup(root, suite) }
        model.searchSelectedDates()
        try await waitForSecondPage(client)
        model.cancelDiscovery()
        try await waitForSearch(model)
        XCTAssertTrue(model.discoveryReport?.cancelled == true)
        XCTAssertEqual(model.papers.count, 1)
        XCTAssertEqual(model.discoveryReport?.pendingDays.count, 2)
        XCTAssertTrue(model.canRetryDiscovery)
        let paper = try XCTUnwrap(model.papers.first)
        model.saveNote("Reading work survives retry", for: paper)
        model.retryUnfinishedDates()
        try await waitForSearch(model)
        XCTAssertEqual(Set(model.papers.map(\.shortID)), ["2610.00001", "2610.00002"])
        XCTAssertEqual(model.papers.count, 2)
        XCTAssertTrue(model.discoveryReport?.pendingDays.isEmpty == true)
        XCTAssertEqual(model.discoveryReport?.addedPapers, 1)
        XCTAssertEqual(model.discoveryReport?.existingPapers, 1)
        XCTAssertEqual(model.library.progress(for: paper.shortID).note, "Reading work survives retry")
        let offsets = await client.offsets
        XCTAssertEqual(offsets, [0, 1, 1])
        model.searchSelectedDates()
        try await waitForSearch(model)
        XCTAssertEqual(model.discoveryReport?.requestCount, 0)
        XCTAssertEqual(model.papers.count, 2)
    }

    func testEditingTopicAfterCancelBlocksMisleadingRetryAndInvalidatesCoverage() async throws {
        let (model, client, root, suite) = try fixture()
        defer { cleanup(root, suite) }
        model.searchSelectedDates()
        try await waitForSecondPage(client)
        model.cancelDiscovery()
        try await waitForSearch(model)
        model.settings.researchTopics = [
            ResearchTopic(id: SmartTopic.worldModels.rawValue, name: "Edited topic", anyTerms: ["latent dynamics"])
        ]
        XCTAssertFalse(model.canRetryDiscovery)
        model.retryUnfinishedDates()
        XCTAssertFalse(model.isDiscovering)
        XCTAssertTrue(model.discoveryError?.contains("Topics changed") == true)
        XCTAssertFalse(
            model.discoveryHistory.days["2026-10-01"]?.covers(
                mode: .topics, categories: [], researchTopics: model.settings.selectedTopics) == true)
    }

    func testCancelledSearchCanResumeAfterRelaunchWithItsOriginalScope() async throws {
        let (model, client, root, suite) = try fixture()
        defer { cleanup(root, suite) }
        model.searchSelectedDates()
        try await waitForSecondPage(client)
        model.cancelDiscovery()
        try await waitForSearch(model)
        var policy = DiscoveryPolicy()
        policy.requestSpacing = 0
        let reopened = AppViewModel(
            settings: model.settings, repository: model.repository, client: client, isVerification: true,
            allowPublicVerificationDiscovery: true, discoveryPolicy: policy)
        XCTAssertEqual(reopened.selectedDiscoveryDays, ["2026-10-01", "2026-10-02"])
        XCTAssertTrue(reopened.canRetryDiscovery)
        reopened.retryUnfinishedDates()
        try await waitForSearch(reopened)
        XCTAssertEqual(reopened.papers.count, 2)
        XCTAssertTrue(reopened.discoveryReport?.pendingDays.isEmpty == true)
    }

    func testPublicVerificationRequiresAnIsolatedMarkedRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "dev.gnaroshi.ArxivDiscovery.test." + UUID().uuidString
        defer { cleanup(root, suite) }
        let model = AppViewModel(
            settings: AppSettings(defaults: UserDefaults(suiteName: suite)!),
            repository: PaperRepository(rootURL: root),
            isVerification: true, allowPublicVerificationDiscovery: true)
        XCTAssertFalse(model.canDiscover)
        model.searchSelectedDates()
        XCTAssertFalse(model.isDiscovering)
    }

    func testSearchCannotStartFromKeyboardWhileTopicEditorsAreOpen() async throws {
        let (model, client, root, suite) = try fixture()
        defer { cleanup(root, suite) }
        model.settings.topicEditorOpened()
        model.settings.topicEditorOpened()
        model.settings.topicEditorClosed()
        model.searchSelectedDates()
        XCTAssertFalse(model.isDiscovering)
        XCTAssertTrue(model.discoveryError?.contains("Finish editing topics") == true)
        let offsets = await client.offsets
        XCTAssertTrue(offsets.isEmpty)
        model.settings.topicEditorClosed()
        XCTAssertFalse(model.settings.isManagingTopics)
    }
}
