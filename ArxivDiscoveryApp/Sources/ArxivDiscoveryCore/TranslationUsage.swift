import Foundation

public struct TranslationTokenUsage: Codable, Equatable, Sendable {
    public var promptTokens: Int
    public var responseTokens: Int
    public var thinkingTokens: Int
    public var totalTokens: Int

    public init(promptTokens: Int = 0, responseTokens: Int = 0, thinkingTokens: Int = 0, totalTokens: Int = 0) {
        self.promptTokens = max(promptTokens, 0)
        self.responseTokens = max(responseTokens, 0)
        self.thinkingTokens = max(thinkingTokens, 0)
        self.totalTokens = max(totalTokens, 0)
    }
}

public struct TranslationUsageRecord: Codable, Equatable, Identifiable, Sendable {
    public var day: String
    public var model: String
    public var requests: Int
    public var promptTokens: Int
    public var responseTokens: Int
    public var thinkingTokens: Int
    public var totalTokens: Int
    public var lastUsedAt: Date

    public var id: String { "\(day):\(model)" }
}

public struct TranslationUsageLedger: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var records: [TranslationUsageRecord]

    public init(schemaVersion: Int = 1, records: [TranslationUsageRecord] = []) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    public mutating func record(model: String, usage: TranslationTokenUsage, at date: Date = Date()) {
        let day = DiscoveryDate.key(for: date)
        if let index = records.firstIndex(where: { $0.day == day && $0.model == model }) {
            records[index].requests += 1
            records[index].promptTokens += usage.promptTokens
            records[index].responseTokens += usage.responseTokens
            records[index].thinkingTokens += usage.thinkingTokens
            records[index].totalTokens += usage.totalTokens
            records[index].lastUsedAt = date
        } else {
            records.append(.init(
                day: day,
                model: model,
                requests: 1,
                promptTokens: usage.promptTokens,
                responseTokens: usage.responseTokens,
                thinkingTokens: usage.thinkingTokens,
                totalTokens: usage.totalTokens,
                lastUsedAt: date
            ))
        }
        records = records.filter {
            guard let recordDate = DiscoveryDate.date(from: $0.day),
                  let cutoff = DiscoveryDate.calendar.date(byAdding: .day, value: -365, to: date)
            else { return true }
            return recordDate >= cutoff
        }
    }

    public func summary(for day: String) -> TranslationUsageRecord {
        records.filter { $0.day == day }.reduce(
            TranslationUsageRecord(day: day, model: "", requests: 0, promptTokens: 0, responseTokens: 0, thinkingTokens: 0, totalTokens: 0, lastUsedAt: Date(timeIntervalSince1970: 0))
        ) { result, value in
            var merged = result
            merged.requests += value.requests
            merged.promptTokens += value.promptTokens
            merged.responseTokens += value.responseTokens
            merged.thinkingTokens += value.thinkingTokens
            merged.totalTokens += value.totalTokens
            merged.lastUsedAt = max(merged.lastUsedAt, value.lastUsedAt)
            return merged
        }
    }
}
