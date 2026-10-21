import ArxivDiscoveryCore
import Foundation

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var handler: ((URLRequest, FixtureProtocol) -> Void)?
    static var requests: [URLRequest] = []
    static var stopped = 0
    private var work: DispatchWorkItem?
    private var chunks: [DispatchWorkItem] = []

    static func configure(_ handler: @escaping (URLRequest, FixtureProtocol) -> Void) {
        lock.withLock { self.handler = handler; requests = []; stopped = 0 }
    }
    static var count: Int { lock.withLock { requests.count } }
    static var offsets: [Int] {
        lock.withLock { requests.compactMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "start" }?.value.flatMap(Int.init) } }
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let callback = Self.lock.withLock { Self.requests.append(request); return Self.handler }
        callback?(request, self)
    }
    override func stopLoading() {
        work?.cancel()
        chunks.forEach { $0.cancel() }
        Self.lock.withLock { Self.stopped += 1 }
    }
    func respond(_ text: String, status: Int = 200, headers: [String: String] = [:], delay: TimeInterval = 0) {
        let action = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        work = action
        if delay > 0 { DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: action) }
        else { action.perform() }
    }

    func trickle() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for index in 0..<10 {
            let chunk = DispatchWorkItem { [weak self] in
                guard let self else { return }
                client?.urlProtocol(self, didLoad: Data("x".utf8))
            }
            chunks.append(chunk)
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(index) * 0.03, execute: chunk)
        }
    }
}

private func configuration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureProtocol.self]
    return configuration
}

private func fixtureClient() -> ArxivClient {
    ArxivClient(session: URLSession(configuration: configuration()), endpoint: URL(string: "https://fixture.invalid/query")!)
}

private func feed(_ entries: [(String, String)], total: Int? = nil) -> String {
    let rows = entries.map { id, day in
        "<entry><id>https://arxiv.org/abs/\(id)</id><published>\(day)T12:00:00Z</published><title>World Models \(id)</title><summary>A world model for robotics.</summary><author><name>Alice</name></author></entry>"
    }.joined()
    return "<feed xmlns='http://www.w3.org/2005/Atom' xmlns:opensearch='http://a9.com/-/spec/opensearch/1.1/'>\(total.map { "<opensearch:totalResults>\($0)</opensearch:totalResults>" } ?? "")\(rows)</feed>"
}

private func query() -> DiscoveryQuery {
    DiscoveryQuery(interval: DiscoveryDate.interval(for: "2026-10-01")!, researchTopics: ResearchTopic.defaults)
}

private func fastPolicy() -> DiscoveryPolicy {
    var policy = DiscoveryPolicy()
    policy.requestTimeout = 0.3
    policy.totalTimeout = 2
    policy.requestSpacing = 0
    return policy
}

@MainActor private final class UIHeartbeat {
    var ticks = 0
    func pulse() async {
        while !Task.isCancelled {
            ticks += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

func checkDiscoveryNetworking() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let transport = BoundedHTTPClient(configuration: configuration())
    let request = URLRequest(url: URL(string: "https://fixture.invalid/stall")!)
    FixtureProtocol.configure { _, _ in /* Never responds, even though connected. */ }
    let start = Date()
    do {
        _ = try await transport.data(for: request, timeout: 0.08)
        throw CheckFailure.failed("A silent server must time out.")
    } catch HTTPTransferError.timedOut {}
    catch let error as URLError where error.code == .timedOut {}
    try require(Date().timeIntervalSince(start) < 1, "A wall-clock timeout must not wait for the resource timeout default.")

    FixtureProtocol.configure { _, instance in instance.trickle() }
    let trickleStart = Date()
    do { _ = try await transport.data(for: request, timeout: 0.08); throw CheckFailure.failed("A trickling response must still hit the wall-clock deadline.") }
    catch HTTPTransferError.timedOut {}
    catch let error as URLError where error.code == .timedOut {}
    try require(Date().timeIntervalSince(trickleStart) < 0.25, "Partial bytes must not extend the overall request deadline.")

    FixtureProtocol.configure { _, _ in }
    let operation = Task { try await transport.data(for: request, timeout: 10) }
    try await Task.sleep(for: .milliseconds(20))
    let cancelledAt = Date()
    operation.cancel()
    do { _ = try await operation.value; throw CheckFailure.failed("Cancelled network work must throw.") }
    catch is CancellationError {}
    try require(Date().timeIntervalSince(cancelledAt) < 0.5, "Cancel must promptly release the network wait.")

    FixtureProtocol.configure { _, protocolInstance in protocolInstance.respond(String(repeating: "x", count: 4096)) }
    do { _ = try await transport.data(for: request, maximumBytes: 128); throw CheckFailure.failed("An oversized stream must fail.") }
    catch HTTPTransferError.tooLarge {}

    let days = (1...16).map { String(format: "2026-10-%02d", $0) }
    let acronymRule = ResearchTopic(id: "vla", name: "VLA", anyTerms: ["vla"])
    try require(acronymRule.searchExpression.contains(" AND ") && acronymRule.searchExpression.contains("robotics"), "Ambiguous VLA acronyms must require robotics context in the remote query as well as local filtering.")
    FixtureProtocol.configure { _, instance in instance.respond(feed([("2610.00001", days[0]), ("2610.00002", days[15])], total: 2)) }
    let repository = PaperRepository(rootURL: root.appendingPathComponent("grouped"))
    let search = DiscoverySearch(repository: repository, client: fixtureClient())
    let report = try await search.search(days: days, template: query(), policy: fastPolicy()) { _ in }
    try require(report.requestCount == 1 && report.completedDays.count == 16, "Sixteen adjacent dates must use one complete range query, not sixteen requests.")
    try require(report.pendingDays.isEmpty && report.receivedPapers == 2, "Grouped results must be assigned to the selected dates.")
    let cached = try await search.search(days: days, template: query(), policy: fastPolicy()) { _ in }
    try require(cached.requestCount == 0 && cached.cachedDays.count == 16 && FixtureProtocol.count == 1, "Repeated complete searches must use local coverage, including zero-result days.")
    try require(try repository.loadPapers().count == 2, "Repeated search must not duplicate papers.")
    let forced = try await search.search(days: days, template: query(), forceRefresh: true, policy: fastPolicy()) { _ in }
    try require(forced.requestCount == 1 && FixtureProtocol.count == 2, "Explicit refresh must bypass local coverage and the page cache.")

    let holesRepository = PaperRepository(rootURL: root.appendingPathComponent("cached-holes"))
    var holesHistory = DiscoveryHistory()
    for day in [days[1], days[4], days[8]] {
        holesHistory.record(.init(day: day, lastSearchedAt: Date(), paperCount: 0, categories: [], isComplete: true, mode: .topics, researchTopics: ResearchTopic.defaults))
    }
    try holesRepository.saveDiscoveryHistory(holesHistory)
    FixtureProtocol.configure { _, instance in instance.respond(feed([], total: 0)) }
    let holes = DiscoverySearch(repository: holesRepository, client: fixtureClient())
    let holesReport = try await holes.search(days: days, template: query(), policy: fastPolicy()) { _ in }
    try require(holesReport.requestCount == 1 && holesReport.cachedDays.count == 3, "Already-complete dates inside a selected range must not fragment it into many remote calls.")

    FixtureProtocol.configure { _, instance in instance.respond(feed([], total: 0)) }
    let sparse = DiscoverySearch(repository: PaperRepository(rootURL: root.appendingPathComponent("sparse")), client: fixtureClient())
    let sparseReport = try await sparse.search(days: [days[0], days[2]], template: query(), policy: fastPolicy()) { _ in }
    try require(sparseReport.requestCount == 2, "Nonadjacent dates must not pull in unselected days.")

    FixtureProtocol.configure { _, instance in instance.respond("Rate limited", status: 429, headers: ["Retry-After": "60"]) }
    let limited = DiscoverySearch(repository: PaperRepository(rootURL: root.appendingPathComponent("limited")), client: fixtureClient())
    let limitedReport = try await limited.search(days: [days[0], days[2]], template: query(), policy: fastPolicy()) { _ in }
    try require(limitedReport.requestCount == 1 && limitedReport.failures.first?.reason == "rate_limited", "429 must stop the batch, not retry every date.")
    let cooldown = try await limited.search(days: days, template: query(), policy: fastPolicy()) { _ in }
    try require(cooldown.requestCount == 0 && FixtureProtocol.count == 1, "Cooldown must also prevent repeated button clicks from making requests.")

    FixtureProtocol.configure { _, instance in instance.respond("Maintenance", status: 503) }
    let unavailable = DiscoverySearch(repository: PaperRepository(rootURL: root.appendingPathComponent("unavailable")), client: fixtureClient())
    let unavailableReport = try await unavailable.search(days: [days[0], days[2]], template: query(), policy: fastPolicy()) { _ in }
    try require(unavailableReport.requestCount == 1 && unavailableReport.pendingDays.count == 2, "503 must fail fast and preserve unfinished dates.")

    let partialRepository = PaperRepository(rootURL: root.appendingPathComponent("partial"))
    var library = LibraryState()
    library.setNote("My reading work", paperID: "2610.00001")
    try partialRepository.saveLibraryState(library)
    var pagedPolicy = fastPolicy()
    pagedPolicy.pageSize = 2
    FixtureProtocol.configure { request, instance in
        let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "start" }?.value
        if offset == "0" { instance.respond(feed([("2610.00001", days[0]), ("2610.00002", days[0])], total: 3)) }
        else { instance.respond("Unavailable", status: 503) }
    }
    let partial = DiscoverySearch(repository: partialRepository, client: fixtureClient())
    let partialReport = try await partial.search(days: [days[0]], template: query(), policy: pagedPolicy) { _ in }
    try require(partialReport.pendingDays == [days[0]], "Truncated results must not mark a date complete.")
    try require(try partialRepository.loadPapers().count == 2, "The first page must be saved before a later page fails.")
    try require(try partialRepository.loadDiscoveryHistory().days[days[0]]?.isComplete == false, "Coverage must remain incomplete after paging failure.")
    FixtureProtocol.configure { _, instance in instance.respond(feed([("2610.00003", days[0])], total: 3)) }
    let resumed = try await partial.search(days: [days[0]], template: query(), policy: pagedPolicy) { _ in }
    try require(resumed.requestCount == 1 && FixtureProtocol.offsets == [2], "Retry must replay cached pages and fetch only the unfinished offset.")
    try require(try partialRepository.loadPapers().count == 3, "Paged continuation must merge without duplicates.")
    try require(try partialRepository.loadLibraryState().progress(for: "2610.00001").note == "My reading work", "Search must never overwrite reading state.")

    let budgeted = DiscoverySearch(repository: PaperRepository(rootURL: root.appendingPathComponent("page-budget")), client: fixtureClient())
    var onePagePolicy = pagedPolicy
    onePagePolicy.maximumPages = 1
    FixtureProtocol.configure { request, instance in
        let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "start" }?.value
        instance.respond(offset == "0" ? feed([("2610.00001", days[0]), ("2610.00002", days[0])], total: 3) : feed([("2610.00003", days[0])], total: 3))
    }
    let budgetFirst = try await budgeted.search(days: [days[0]], template: query(), policy: onePagePolicy) { _ in }
    let budgetNext = try await budgeted.search(days: [days[0]], template: query(), policy: onePagePolicy) { _ in }
    try require(budgetFirst.pendingDays.count == 1 && budgetNext.pendingDays.isEmpty && FixtureProtocol.offsets == [0, 2], "Cached pages must not use up the next run's page budget or prevent continuation.")

    let brokenRepository = PaperRepository(rootURL: root.appendingPathComponent("disk-failure"))
    try brokenRepository.saveLibraryState(library)
    try FileManager.default.createDirectory(at: brokenRepository.papersURL, withIntermediateDirectories: true)
    FixtureProtocol.configure { _, instance in instance.respond(feed([("2610.00001", days[0])], total: 1)) }
    let broken = DiscoverySearch(repository: brokenRepository, client: fixtureClient())
    let brokenReport = try await broken.search(days: days, template: query(), policy: fastPolicy()) { _ in }
    try require(brokenReport.storageFailed && brokenReport.completedDays.isEmpty, "A checkpoint failure must never become complete coverage.")
    try require(try brokenRepository.loadLibraryState().progress(for: "2610.00001").note == "My reading work", "A disk failure must leave reading work untouched.")

    FixtureProtocol.configure { _, _ in }
    let bounded = DiscoverySearch(repository: PaperRepository(rootURL: root.appendingPathComponent("deadline")), client: fixtureClient())
    var deadlinePolicy = fastPolicy()
    deadlinePolicy.requestTimeout = 5
    deadlinePolicy.totalTimeout = 0.09
    let heartbeat = await UIHeartbeat()
    let ticking = Task { await heartbeat.pulse() }
    let deadlineStart = Date()
    let deadlineReport = try await bounded.search(days: days, template: query(), policy: deadlinePolicy) { _ in }
    ticking.cancel()
    await ticking.value
    let ticks = await heartbeat.ticks
    try require(ticks >= 2, "The main/UI actor must continue ticking while a server is silent.")
    try require(Date().timeIntervalSince(deadlineStart) < 1 && deadlineReport.timedOut, "Overall deadline must constrain the active request, not just gaps between dates.")

    FixtureProtocol.configure { _, _ in }
    let cancellable = DiscoverySearch(repository: PaperRepository(rootURL: root.appendingPathComponent("cancelled")), client: fixtureClient())
    let active = Task { try await cancellable.search(days: days, template: query(), policy: fastPolicy()) { _ in } }
    try await Task.sleep(for: .milliseconds(20))
    do {
        _ = try await cancellable.search(days: days, template: query(), policy: fastPolicy()) { _ in }
        throw CheckFailure.failed("Discovery must reject overlapping search tasks.")
    } catch ArxivClientError.invalidRequest {}
    active.cancel()
    let cancelled = try await active.value
    try require(cancelled.cancelled && cancelled.pendingDays.count == 16, "Cancellation must return a terminal report, preserving unfinished dates.")

    FixtureProtocol.configure { _, instance in instance.respond("<html><body>Gateway failure</body></html>") }
    let invalidRepository = PaperRepository(rootURL: root.appendingPathComponent("invalid"))
    let invalid = DiscoverySearch(repository: invalidRepository, client: fixtureClient())
    let invalidReport = try await invalid.search(days: days, template: query(), policy: fastPolicy()) { _ in }
    try require(invalidReport.failures.first?.reason == "invalid_feed", "HTML or an error feed must not become a successful zero-paper search.")
    try require(try invalidRepository.loadDiscoveryHistory().days.isEmpty, "Invalid responses must never record successful coverage.")
    do {
        _ = try ArxivFeedParser.parse(data: Data("<feed><entry><id>http://arxiv.org/api/errors#bad_query</id><title>Error</title><summary>Bad query</summary><published>2026-10-01T00:00:00Z</published></entry></feed>".utf8))
        throw CheckFailure.failed("An arXiv API error entry must fail even when HTTP is 200.")
    } catch ArxivClientError.malformedFeed {}
    let oldArchive = try ArxivFeedParser.parse(data: Data(feed([("cs/0701001v2", days[0])], total: 1).utf8))
    try require(oldArchive.first?.shortID == "cs/0701001", "Old archive identifiers must preserve their archive prefix.")

    let downloadBytes = "%PDF-1.7\nfixture"
    FixtureProtocol.configure { _, instance in instance.respond(downloadBytes) }
    let (downloaded, _) = try await transport.download(for: request)
    defer { try? FileManager.default.removeItem(at: downloaded) }
    try require(try Data(contentsOf: downloaded) == Data(downloadBytes.utf8), "PDF transfer must stream to a local temporary file.")

    let pdfRepository = PaperRepository(rootURL: root.appendingPathComponent("pdfs"))
    let first = paper(abstract: "first", translation: nil)
    var second = first
    second.shortID = "different-paper"
    let firstFile = root.appendingPathComponent("first.pdf")
    let secondFile = root.appendingPathComponent("second.pdf")
    try Data("first reading copy".utf8).write(to: firstFile)
    try Data("second reading copy".utf8).write(to: secondFile)
    let firstDestination = try pdfRepository.storeDownloadedPDF(from: firstFile, for: first, style: .title)
    try require(pdfRepository.existingPDFURL(for: second, preferredStyle: .title) == nil, "A title collision must not open another paper's owned PDF.")
    let secondDestination = try pdfRepository.storeDownloadedPDF(from: secondFile, for: second, style: .title)
    try require(firstDestination != secondDestination, "Same-title PDFs must not overwrite each other.")
    try require(try Data(contentsOf: firstDestination) == Data("first reading copy".utf8), "Original PDF contents must be preserved.")
    try require(pdfRepository.existingPDFURL(for: second, preferredStyle: .title) == secondDestination, "The PDF ownership index must resolve the right paper after a collision.")
    let repeatedFile = root.appendingPathComponent("repeated.pdf")
    try Data("replacement without my annotations".utf8).write(to: repeatedFile)
    try require(try pdfRepository.storeDownloadedPDF(from: repeatedFile, for: first, style: .title) == firstDestination, "Redownload must return the existing reading copy.")
    try require(try Data(contentsOf: firstDestination) == Data("first reading copy".utf8), "Redownload must not overwrite a user's PDF annotations.")

    try require(DiscoveryDate.date(from: "2026-02-31") == nil, "Invalid dates must not roll over silently.")
    var incomplete = DiscoveryDayRecord(day: days[0], lastSearchedAt: Date(), paperCount: 500, categories: [], isComplete: false, mode: .topics, researchTopics: ResearchTopic.defaults)
    try require(!incomplete.covers(mode: .topics, categories: [], researchTopics: ResearchTopic.defaults), "Incomplete coverage must remain selectable for retry.")
    incomplete.isComplete = true
    try require(incomplete.covers(mode: .topics, categories: [], researchTopics: ResearchTopic.defaults), "Complete coverage must be reusable.")
    print("Discovery networking checks passed: hard timeout, cancellation, bounded streaming, 16-day batching, cache, sparse dates, 429/cooldown, 503, paging/resume, partial save, reading-work preservation, deadline, invalid feed and local PDF transfer.")
}
