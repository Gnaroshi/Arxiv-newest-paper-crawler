import ArxivDiscoveryCore
import Foundation

private struct StatusEnvelope: Encodable {
    struct Provider: Encodable {
        let id: String
        let version: String
    }

    struct Freshness: Encodable {
        let observedAt: Date?
        let generatedAt: Date
        let thresholdSeconds: Int
        let isStale: Bool
    }

    struct DataSummary: Encodable {
        let paperCount: Int
        let favoriteCount: Int
        let lastRefresh: Date?
        let nextAction: String
    }

    struct Issue: Encodable {
        let code: String
        let message: String
    }

    let contractVersion: Int
    let capability: String
    let provider: Provider
    let freshness: Freshness
    let status: String
    let data: DataSummary
    let warnings: [Issue]
    let errors: [Issue]
}

private func envelope(status snapshot: IntegrationSnapshot?, now: Date) -> StatusEnvelope {
    let threshold = 36 * 60 * 60
    guard let snapshot else {
        return StatusEnvelope(
            contractVersion: 1,
            capability: "status",
            provider: .init(id: "arxiv-discovery", version: "0.2.0"),
            freshness: .init(observedAt: nil, generatedAt: now, thresholdSeconds: threshold, isStale: true),
            status: "unavailable",
            data: .init(paperCount: 0, favoriteCount: 0, lastRefresh: nil, nextAction: "Launch Arxiv Discovery to initialize local status."),
            warnings: [],
            errors: [.init(code: "status_missing", message: "No application status has been recorded yet.")]
        )
    }

    let stale = now.timeIntervalSince(snapshot.observedAt) > TimeInterval(threshold)
    var warnings: [StatusEnvelope.Issue] = []
    if stale {
        warnings.append(.init(code: "status_stale", message: "The last application observation is older than the freshness window."))
    }
    if let code = snapshot.lastErrorCode {
        warnings.append(.init(code: code, message: "The last discovery attempt did not complete."))
    }
    let state = stale ? "stale" : snapshot.availability == "ready" ? "ok" : snapshot.availability
    return StatusEnvelope(
        contractVersion: 1,
        capability: "status",
        provider: .init(id: snapshot.providerID, version: snapshot.providerVersion),
        freshness: .init(observedAt: snapshot.observedAt, generatedAt: now, thresholdSeconds: threshold, isStale: stale),
        status: state,
        data: .init(
            paperCount: snapshot.paperCount,
            favoriteCount: snapshot.favoriteCount,
            lastRefresh: snapshot.lastRefresh,
            nextAction: snapshot.paperCount == 0 ? "Launch the app and find recent papers." : "Open Arxiv Discovery to review local candidates."
        ),
        warnings: warnings,
        errors: []
    )
}

private func emit(_ value: StatusEnvelope) -> Never {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    do {
        FileHandle.standardOutput.write(try encoder.encode(value))
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(EXIT_SUCCESS)
    } catch {
        exit(EXIT_FAILURE)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments == ["status", "--json"] else {
    emit(
        StatusEnvelope(
            contractVersion: 1,
            capability: "status",
            provider: .init(id: "arxiv-discovery", version: "0.2.0"),
            freshness: .init(observedAt: nil, generatedAt: Date(), thresholdSeconds: 129_600, isStale: true),
            status: "incompatible",
            data: .init(paperCount: 0, favoriteCount: 0, lastRefresh: nil, nextAction: "Use the fixed status --json command."),
            warnings: [],
            errors: [.init(code: "unsupported_command", message: "Only status --json is supported.")]
        )
    )
}

let snapshot = try? PaperRepository().loadStatus()
emit(envelope(status: snapshot ?? nil, now: Date()))
