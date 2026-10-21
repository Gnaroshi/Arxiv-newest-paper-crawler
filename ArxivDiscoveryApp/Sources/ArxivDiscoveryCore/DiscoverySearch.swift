import CryptoKit
import Foundation

public struct DiscoveryPolicy: Sendable {
    public var requestTimeout: TimeInterval = 12
    public var totalTimeout: TimeInterval = 45
    public var requestSpacing: TimeInterval = 3
    public var cacheTTL: TimeInterval = 6 * 3600
    public var pageSize = 200
    public var maximumPages = 10
    public var retentionDays = 60
    public init() {}
}

public struct DiscoveryFailure: Codable, Equatable, Sendable {
    public var days: [String]
    public var reason: String
    public var message: String
}

public struct DiscoveryProgress: Sendable {
    public var message: String
    public var completedDays: Int
    public var totalDays: Int
    public var receivedPapers: Int
    public var requests: Int
}

public struct DiscoveryRunReport: Codable, Sendable {
    public var startedAt = Date()
    public var elapsedSeconds: TimeInterval = 0
    public var selectedDays: [String] = []
    public var completedDays: [String] = []
    public var cachedDays: [String] = []
    public var pendingDays: [String] = []
    public var failures: [DiscoveryFailure] = []
    public var requestCount = 0
    public var receivedPapers = 0
    public var cancelled = false
    public var timedOut = false
    public var retryAfterSeconds: TimeInterval?
    public var storageFailed = false
}

public struct DiscoverySnapshot: Sendable {
    public var papers: [Paper]
    public var history: DiscoveryHistory
}

private struct CachedDiscoveryPage: Codable {
    var fetchedAt: Date
    var batch: ArxivSearchBatch
}

/// One serial owner for discovery, paging, pacing, cache and checkpoints. No
/// parsing, merging or JSON I/O in this actor runs on the main/UI actor.
public actor DiscoverySearch {
    private let repository: PaperRepository
    private let client: any ArxivSearching
    private var running = false
    private var lastRequestAt: Date?
    private var cooldownUntil: Date?

    public init(repository: PaperRepository, client: any ArxivSearching = ArxivClient()) {
        self.repository = repository
        self.client = client
    }

    public func snapshot() throws -> DiscoverySnapshot {
        DiscoverySnapshot(papers: try repository.loadPapers(), history: try repository.loadDiscoveryHistory())
    }

    public static func groupedDays(_ days: [String]) -> [[String]] {
        var groups: [[String]] = []
        for day in Set(days).sorted() {
            guard let date = DiscoveryDate.date(from: day) else { continue }
            if let previous = groups.last?.last,
               DiscoveryDate.interval(for: previous)?.end == date,
               groups[groups.count - 1].count < 31 {
                groups[groups.count - 1].append(day)
            } else { groups.append([day]) }
        }
        return groups
    }

    public func search(days: [String], template: DiscoveryQuery, forceRefresh: Bool = false, policy: DiscoveryPolicy = DiscoveryPolicy(), progress: @escaping @Sendable (DiscoveryProgress) async -> Void) async throws -> DiscoveryRunReport {
        guard !running else { throw ArxivClientError.invalidRequest }
        running = true
        defer { running = false }
        var report = DiscoveryRunReport()
        try FileManager.default.createDirectory(at: repository.rootURL, withIntermediateDirectories: true)
        report.selectedDays = Array(Set(days.filter { DiscoveryDate.date(from: $0).map { $0 <= Date() } == true })).sorted()
        let start = Date()
        let deadline = start.addingTimeInterval(policy.totalTimeout)
        var history = try repository.loadDiscoveryHistory()
        let rules = template.researchTopics ?? ResearchTopic.defaults.filter { template.topics.map(\.rawValue).contains($0.id) }
        report.cachedDays = forceRefresh ? [] : report.selectedDays.filter { day in
            guard let record = history.days[day] else { return false }
            return record.covers(mode: template.mode, categories: Set(template.categories), researchTopics: rules)
                && Date().timeIntervalSince(record.lastSearchedAt) < policy.cacheTTL
        }
        var completed = Set(report.cachedDays)
        let pending = report.selectedDays.filter { !completed.contains($0) }
        var consecutiveFailures = 0
        var stop = false
        var received = Set<String>()
        await progress(.init(message: pending.isEmpty ? "Using saved results." : "Preparing grouped date search…", completedDays: completed.count, totalDays: report.selectedDays.count, receivedPapers: 0, requests: 0))

        if let cooldownUntil, cooldownUntil > Date(), !pending.isEmpty {
            report.retryAfterSeconds = cooldownUntil.timeIntervalSinceNow
            report.failures = [.init(days: pending, reason: "rate_limited", message: "arXiv asked us to pause. Try unfinished dates later.")]
            stop = true
        }

        for group in Self.groupedDays(report.selectedDays) {
            if stop { break }
            if group.allSatisfy({ completed.contains($0) }) { continue }
            guard let first = group.first, let last = group.last,
                  let firstInterval = DiscoveryDate.interval(for: first), let lastInterval = DiscoveryDate.interval(for: last) else { continue }
            var query = template
            query.interval = DateInterval(start: firstInterval.start, end: lastInterval.end)
            query.maxResults = min(max(policy.pageSize, 1), 500)
            query.start = 0
            var groupPapers: [String: Paper] = [:]
            var oldestFetch = Date()
            while true {
                if Task.isCancelled { report.cancelled = true; stop = true; break }
                if Date() >= deadline { report.timedOut = true; stop = true; break }
                do {
                    let cached = forceRefresh ? nil : loadCachedPage(query, ttl: policy.cacheTTL)
                    let page: CachedDiscoveryPage
                    if let cached { page = cached }
                    else {
                        // Cached pages do not consume the network budget. A
                        // retry can therefore advance beyond previous pages.
                        if report.requestCount >= policy.maximumPages { stop = true; break }
                        if let lastRequestAt {
                            let wait = max(0, policy.requestSpacing - Date().timeIntervalSince(lastRequestAt))
                            if wait >= deadline.timeIntervalSinceNow { report.timedOut = true; stop = true; break }
                            if wait > 0 {
                                await progress(.init(message: "Waiting briefly between requests to arXiv…", completedDays: completed.count, totalDays: report.selectedDays.count, receivedPapers: received.count, requests: report.requestCount))
                                try await Task.sleep(for: .seconds(wait))
                            }
                        }
                        try Task.checkCancellation()
                        query.timeoutSeconds = min(policy.requestTimeout, deadline.timeIntervalSinceNow)
                        guard query.timeoutSeconds > 0 else { report.timedOut = true; stop = true; break }
                        await progress(.init(message: "Fetching \(first)–\(last) · page \(query.start / query.maxResults + 1) · at most \(Int(ceil(query.timeoutSeconds)))s for this request", completedDays: completed.count, totalDays: report.selectedDays.count, receivedPapers: received.count, requests: report.requestCount + 1))
                        lastRequestAt = Date()
                        report.requestCount += 1
                        page = CachedDiscoveryPage(fetchedAt: Date(), batch: try await client.discoverBatch(query: query, now: Date()))
                        try? saveCachedPage(page, query: query)
                    }
                    let batch = page.batch
                    guard batch.isComplete || batch.rawCount > 0 else { throw ArxivClientError.malformedFeed }
                    oldestFetch = min(oldestFetch, page.fetchedAt)
                    let excluded = try repository.loadCleanupState().excluded
                    for paper in batch.papers where excluded[paper.shortID] == nil && group.contains(DiscoveryDate.key(for: paper.publishedAt)) {
                        groupPapers[paper.shortID] = paper
                        received.insert(paper.shortID)
                    }
                    let records = group.map { day in
                        DiscoveryDayRecord(day: day, lastSearchedAt: oldestFetch, paperCount: groupPapers.values.filter { DiscoveryDate.key(for: $0.publishedAt) == day }.count, categories: template.categories, isComplete: batch.isComplete, mode: template.mode, topics: template.topics, researchTopics: rules)
                    }
                    // Metadata first, coverage second: never claim a successful
                    // search for papers that have not reached disk yet.
                    do {
                        let current = try repository.loadPapers()
                        let merged = repository.merge(existing: current, discovered: Array(groupPapers.values)).filter { excluded[$0.shortID] == nil }
                        let kept = repository.prunedPapers(merged, library: try repository.loadLibraryState(), retentionDays: policy.retentionDays)
                        try repository.savePapers(kept)
                        for record in records where batch.isComplete || !completed.contains(record.day) { history.record(record) }
                        history.prune()
                        try repository.saveDiscoveryHistory(history)
                    } catch {
                        report.storageFailed = true
                        report.failures.append(.init(days: group, reason: "storage", message: "Results could not be fully saved. Existing papers are kept; check local storage."))
                        stop = true
                        break
                    }
                    consecutiveFailures = 0
                    await progress(.init(message: "Saved \(received.count) matching papers so far.", completedDays: batch.isComplete ? completed.union(group).count : completed.count, totalDays: report.selectedDays.count, receivedPapers: received.count, requests: report.requestCount))
                    if batch.isComplete { completed.formUnion(group); break }
                    query.start += batch.rawCount
                } catch {
                    if Task.isCancelled || error is CancellationError { report.cancelled = true; stop = true; break }
                    let failure = Self.failure(error, days: group.filter { !completed.contains($0) })
                    report.failures.append(failure)
                    if Date() >= deadline { report.timedOut = true; stop = true }
                    consecutiveFailures += 1
                    if case let ArxivClientError.rateLimited(delay) = error {
                        let delay = max(3, delay ?? 60)
                        cooldownUntil = Date().addingTimeInterval(delay)
                        report.retryAfterSeconds = delay
                        stop = true
                    }
                    if ["unavailable", "invalid_feed", "http_error"].contains(failure.reason) || consecutiveFailures >= 2 { stop = true }
                    break
                }
            }
        }
        report.completedDays = completed.sorted()
        report.pendingDays = report.selectedDays.filter { !completed.contains($0) }
        report.receivedPapers = received.count
        report.cancelled = report.cancelled || Task.isCancelled
        report.elapsedSeconds = Date().timeIntervalSince(start)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(report).write(to: repository.rootURL.appendingPathComponent("last-discovery.json"), options: .atomic)
        } catch {
            report.storageFailed = true
            report.failures.append(.init(days: [], reason: "storage", message: "Papers were checkpointed, but the search report could not be saved."))
        }
        return report
    }

    private static func failure(_ error: Error, days: [String]) -> DiscoveryFailure {
        let code = (error as? URLError)?.code
        if error as? HTTPTransferError == .timedOut || code == .timedOut {
            return .init(days: days, reason: "timeout", message: "arXiv did not respond before the request time limit. Try unfinished dates later.")
        }
        if case ArxivClientError.rateLimited = error {
            return .init(days: days, reason: "rate_limited", message: "arXiv is limiting requests. Try unfinished dates later.")
        }
        if error as? ArxivClientError == .serviceUnavailable {
            return .init(days: days, reason: "unavailable", message: "arXiv is temporarily unavailable. Try unfinished dates later.")
        }
        if error as? ArxivClientError == .malformedFeed {
            return .init(days: days, reason: "invalid_feed", message: "arXiv returned an invalid feed, not a valid empty search result.")
        }
        if case let ArxivClientError.httpStatus(status) = error {
            return .init(days: days, reason: "http_error", message: "arXiv rejected the search (HTTP \(status)). Check the topic phrases before retrying.")
        }
        if error as? HTTPTransferError == .tooLarge {
            return .init(days: days, reason: "invalid_feed", message: "The response was too large. Narrow the selected dates or topic phrases.")
        }
        return .init(days: days, reason: "network", message: "The search could not reach arXiv. Check the connection and retry unfinished dates.")
    }

    private var cacheURL: URL { repository.rootURL.appendingPathComponent("Cache/Discovery", isDirectory: true) }
    private func pageURL(_ query: DiscoveryQuery) -> URL {
        let rules = query.researchTopics?.map(\.signature).sorted().joined(separator: "|") ?? query.topics.map(\.rawValue).sorted().joined(separator: "|")
        let key = "v1|\(query.searchExpression ?? "")|\(rules)|\(query.start)|\(query.maxResults)"
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheURL.appendingPathComponent(digest + ".json")
    }
    private func loadCachedPage(_ query: DiscoveryQuery, ttl: TimeInterval) -> CachedDiscoveryPage? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: pageURL(query)),
              let page = try? decoder.decode(CachedDiscoveryPage.self, from: data),
              Date().timeIntervalSince(page.fetchedAt) < ttl else { return nil }
        return page
    }
    private func saveCachedPage(_ page: CachedDiscoveryPage, query: DiscoveryQuery) throws {
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(page).write(to: pageURL(query), options: .atomic)
        let files = try FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        var bytes = 0
        for (index, file) in files.enumerated() where file.pathExtension == "json" {
            bytes += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if index >= 128 || bytes > 64 * 1024 * 1024 { try? FileManager.default.removeItem(at: file) }
        }
    }
}
