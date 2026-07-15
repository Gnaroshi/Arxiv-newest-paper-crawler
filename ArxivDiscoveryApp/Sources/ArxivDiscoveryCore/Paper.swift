import Foundation

public struct Paper: Codable, Hashable, Identifiable, Sendable {
    public var entryID: String
    public var shortID: String
    public var title: String
    public var authors: [String]
    public var subjects: [String]
    public var abstract: String
    public var abstractKO: String?
    public var pdfURL: String
    public var publishedAt: Date
    public var crawledAt: Date?

    public var id: String { shortID }

    public init(
        entryID: String,
        shortID: String,
        title: String,
        authors: [String],
        subjects: [String],
        abstract: String,
        abstractKO: String? = nil,
        pdfURL: String,
        publishedAt: Date,
        crawledAt: Date? = nil
    ) {
        self.entryID = entryID
        self.shortID = shortID
        self.title = title
        self.authors = authors
        self.subjects = subjects
        self.abstract = abstract
        self.abstractKO = abstractKO
        self.pdfURL = pdfURL
        self.publishedAt = publishedAt
        self.crawledAt = crawledAt
    }

    public var entryURL: URL? { URL(string: entryID) }
    public var downloadablePDFURL: URL? { URL(string: pdfURL) }

    public func merging(preserving existing: Paper) -> Paper {
        var merged = self
        if merged.abstractKO?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            merged.abstractKO = existing.abstractKO
        }
        return merged
    }

    private enum CodingKeys: String, CodingKey {
        case entryID = "entry_id"
        case shortID = "short_id"
        case title
        case authors
        case subjects
        case abstract
        case abstractKO = "abstract_ko"
        case pdfURL = "pdf_url"
        case publishedAt = "published_time_utc"
        case crawledAt = "crawled_at"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        entryID = try values.decode(String.self, forKey: .entryID)
        shortID = try values.decode(String.self, forKey: .shortID)
        title = try values.decode(String.self, forKey: .title)
        authors = try values.decodeIfPresent([String].self, forKey: .authors) ?? []
        subjects = try values.decodeIfPresent([String].self, forKey: .subjects) ?? []
        abstract = try values.decode(String.self, forKey: .abstract)
        abstractKO = try values.decodeIfPresent(String.self, forKey: .abstractKO)
        pdfURL = try values.decode(String.self, forKey: .pdfURL)
        publishedAt = try values.decodeFlexibleDate(forKey: .publishedAt)
        crawledAt = try values.decodeFlexibleDateIfPresent(forKey: .crawledAt)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(entryID, forKey: .entryID)
        try values.encode(shortID, forKey: .shortID)
        try values.encode(title, forKey: .title)
        try values.encode(authors, forKey: .authors)
        try values.encode(subjects, forKey: .subjects)
        try values.encode(abstract, forKey: .abstract)
        try values.encodeIfPresent(abstractKO, forKey: .abstractKO)
        try values.encode(pdfURL, forKey: .pdfURL)
        try values.encode(ISO8601DateFormatter.arxiv.string(from: publishedAt), forKey: .publishedAt)
        if let crawledAt {
            try values.encode(ISO8601DateFormatter.arxiv.string(from: crawledAt), forKey: .crawledAt)
        }
    }
}

extension ISO8601DateFormatter {
    static let arxiv: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let arxivWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func arxivDate(from value: String) -> Date? {
        arxiv.date(from: value) ?? arxivWithoutFractionalSeconds.date(from: value)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDate(forKey key: Key) throws -> Date {
        let value = try decode(String.self, forKey: key)
        guard let date = ISO8601DateFormatter.arxivDate(from: value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Expected an ISO-8601 date."
            )
        }
        return date
    }

    func decodeFlexibleDateIfPresent(forKey key: Key) throws -> Date? {
        guard let value = try decodeIfPresent(String.self, forKey: key) else { return nil }
        return ISO8601DateFormatter.arxivDate(from: value)
    }
}

public struct DiscoveryQuery: Equatable, Sendable {
    public var days: Int
    public var maxResults: Int
    public var categories: [String]

    public init(
        days: Int = 1,
        maxResults: Int = 200,
        categories: [String] = ["cs.AI", "cs.LG", "cs.CV", "cs.CL", "cs.NE", "stat.ML"]
    ) {
        self.days = min(max(days, 1), 30)
        self.maxResults = min(max(maxResults, 1), 500)
        self.categories = categories.isEmpty ? ["cs.AI"] : categories
    }
}
