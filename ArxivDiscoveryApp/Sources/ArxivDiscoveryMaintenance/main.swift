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
        print("Usage: ArxivDiscoveryMaintenance cleanup [--apply] | restore --apply | migrate-trash --apply")
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
