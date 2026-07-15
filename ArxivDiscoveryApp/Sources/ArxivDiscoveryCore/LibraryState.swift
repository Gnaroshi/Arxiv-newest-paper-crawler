import Foundation

public enum PaperDisposition: String, Codable, CaseIterable, Sendable {
    case inbox
    case reviewed
    case saved
}

public struct PaperProgress: Codable, Equatable, Sendable {
    public var disposition: PaperDisposition
    public var firstViewedAt: Date?
    public var reviewedAt: Date?
    public var savedAt: Date?
    public var collectionIDs: [String]
    public var note: String
    public var updatedAt: Date

    public init(
        disposition: PaperDisposition = .inbox,
        firstViewedAt: Date? = nil,
        reviewedAt: Date? = nil,
        savedAt: Date? = nil,
        collectionIDs: [String] = [],
        note: String = "",
        updatedAt: Date = Date()
    ) {
        self.disposition = disposition
        self.firstViewedAt = firstViewedAt
        self.reviewedAt = reviewedAt
        self.savedAt = savedAt
        self.collectionIDs = Array(Set(collectionIDs)).sorted()
        self.note = note
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case disposition, firstViewedAt, reviewedAt, savedAt, collectionIDs, note, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        disposition = try values.decodeIfPresent(PaperDisposition.self, forKey: .disposition) ?? .inbox
        firstViewedAt = try values.decodeIfPresent(Date.self, forKey: .firstViewedAt)
        reviewedAt = try values.decodeIfPresent(Date.self, forKey: .reviewedAt)
        savedAt = try values.decodeIfPresent(Date.self, forKey: .savedAt)
        collectionIDs = Array(Set(try values.decodeIfPresent([String].self, forKey: .collectionIDs) ?? [])).sorted()
        note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
    }
}

public struct PaperCollection: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, name: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct LibraryState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var papers: [String: PaperProgress]
    public var collections: [PaperCollection]

    public init(schemaVersion: Int = 1, papers: [String: PaperProgress] = [:], collections: [PaperCollection] = []) {
        self.schemaVersion = schemaVersion
        self.papers = papers
        self.collections = collections
    }

    public func progress(for paperID: String) -> PaperProgress {
        papers[paperID] ?? PaperProgress(updatedAt: Date(timeIntervalSince1970: 0))
    }

    public var savedPaperIDs: Set<String> {
        Set(papers.compactMap { $0.value.disposition == .saved ? $0.key : nil })
    }

    public mutating func markViewed(_ paperID: String, at date: Date = Date()) {
        var progress = progress(for: paperID)
        guard progress.firstViewedAt == nil else { return }
        progress.firstViewedAt = date
        progress.updatedAt = date
        papers[paperID] = progress
    }

    public mutating func markReviewed(_ paperID: String, at date: Date = Date()) {
        var progress = progress(for: paperID)
        progress.disposition = .reviewed
        progress.reviewedAt = date
        progress.savedAt = nil
        progress.collectionIDs = []
        progress.updatedAt = date
        papers[paperID] = progress
    }

    public mutating func moveToInbox(_ paperID: String, at date: Date = Date()) {
        var progress = progress(for: paperID)
        progress.disposition = .inbox
        progress.reviewedAt = nil
        progress.savedAt = nil
        progress.collectionIDs = []
        progress.updatedAt = date
        papers[paperID] = progress
    }

    public mutating func setSaved(_ saved: Bool, paperID: String, at date: Date = Date()) {
        var progress = progress(for: paperID)
        if saved {
            progress.disposition = .saved
            progress.savedAt = date
            progress.reviewedAt = nil
        } else {
            progress.disposition = .inbox
            progress.savedAt = nil
            progress.collectionIDs = []
        }
        progress.updatedAt = date
        papers[paperID] = progress
    }

    @discardableResult
    public mutating func createCollection(named rawName: String, at date: Date = Date()) -> PaperCollection? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              collections.contains(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) == false
        else { return nil }
        let collection = PaperCollection(name: name, createdAt: date, updatedAt: date)
        collections.append(collection)
        collections.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return collection
    }

    public mutating func setCollection(_ collectionID: String, contains paperID: String, enabled: Bool, at date: Date = Date()) {
        guard collections.contains(where: { $0.id == collectionID }) else { return }
        var progress = progress(for: paperID)
        var membership = Set(progress.collectionIDs)
        if enabled {
            membership.insert(collectionID)
            progress.disposition = .saved
            progress.savedAt = progress.savedAt ?? date
            progress.reviewedAt = nil
        } else {
            membership.remove(collectionID)
        }
        progress.collectionIDs = membership.sorted()
        progress.updatedAt = date
        papers[paperID] = progress
    }

    public mutating func setNote(_ note: String, paperID: String, at date: Date = Date()) {
        var progress = progress(for: paperID)
        progress.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        progress.updatedAt = date
        papers[paperID] = progress
    }
}

public enum SmartTopic: String, CaseIterable, Identifiable, Sendable {
    case vla
    case worldModels

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .vla: "VLA"
        case .worldModels: "World Models"
        }
    }

    public func matches(_ paper: Paper) -> Bool {
        let text = "\(paper.title) \(paper.abstract)".lowercased()
        switch self {
        case .vla:
            return text.contains("vision-language-action")
                || text.contains("vision language action")
                || text.range(of: #"\bvla(s)?\b"#, options: .regularExpression) != nil
        case .worldModels:
            return text.contains("world model")
                || text.contains("world-model")
                || text.contains("world action model")
                || text.contains("video world model")
        }
    }
}
