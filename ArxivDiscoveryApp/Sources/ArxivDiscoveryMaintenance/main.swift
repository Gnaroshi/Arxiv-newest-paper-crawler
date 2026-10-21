import AppKit
import ArxivDiscoveryCore
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"
let applying = arguments.contains("--apply")
let repository = PaperRepository()
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
encoder.dateEncodingStrategy = .iso8601

func emit<T: Encodable>(_ value: T) throws {
    FileHandle.standardOutput.write(try encoder.encode(value))
    FileHandle.standardOutput.write(Data("\n".utf8))
}

do {
    if applying && !NSRunningApplication.runningApplications(withBundleIdentifier: "dev.gnaroshi.ArxivDiscovery").isEmpty {
        throw NSError(domain: "ArxivDiscoveryMaintenance", code: 1, userInfo: [NSLocalizedDescriptionKey: "Quit Arxiv Discovery normally before changing its local library."])
    }
    switch command {
    case "probe-search":
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        guard let first = value("--from"), let last = value("--to"),
              let start = DiscoveryDate.date(from: first), let end = DiscoveryDate.date(from: last),
              start <= end, end.timeIntervalSince(start) <= 30 * 86400 else {
            throw ArxivClientError.invalidRequest
        }
        var days: [String] = []
        var date = start
        while date <= end { days.append(DiscoveryDate.key(for: date)); date = date.addingTimeInterval(86400) }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var policy = DiscoveryPolicy()
        policy.maximumPages = 5
        policy.totalTimeout = 15
        let search = DiscoverySearch(repository: PaperRepository(rootURL: temporary))
        let query = DiscoveryQuery(interval: DiscoveryDate.interval(for: first)!, researchTopics: ResearchTopic.defaults)
        let report = try await search.search(days: days, template: query, policy: policy) { _ in }
        try emit(report)
    case "migrate-trash":
        guard applying else { throw NSError(domain: "ArxivDiscoveryMaintenance", code: 2, userInfo: [NSLocalizedDescriptionKey: "Migration requires --apply."]) }
        try emit(["movedToTrash": repository.compactExcludedPapers()])
    case "cleanup":
        if applying {
            try emit(repository.applyTopicCleanup(topics: SmartTopic.allCases, applicationVersion: "0.4.0"))
        } else {
            try emit(repository.previewTopicCleanup(topics: SmartTopic.allCases))
        }
    case "restore":
        guard applying else {
            throw NSError(domain: "ArxivDiscoveryMaintenance", code: 2, userInfo: [NSLocalizedDescriptionKey: "Restore requires --apply."])
        }
        try emit(["restoredCount": repository.restoreLastTopicCleanup()])
    default:
        print("Usage: ArxivDiscoveryMaintenance cleanup [--apply] | restore --apply | migrate-trash --apply | probe-search --from YYYY-MM-DD --to YYYY-MM-DD")
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
