import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum ArxivClientError: LocalizedError, Equatable {
    case invalidRequest
    case invalidResponse
    case httpStatus(Int)
    case responseTooLarge
    case malformedFeed
    case rateLimited(TimeInterval?)
    case serviceUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "The discovery request could not be created."
        case .invalidResponse:
            "arXiv returned an unreadable response."
        case let .httpStatus(code):
            "arXiv returned HTTP status \(code)."
        case .responseTooLarge:
            "The arXiv response exceeded the safe size limit."
        case .malformedFeed:
            "The arXiv feed could not be parsed."
        case .rateLimited:
            "arXiv is limiting requests. Saved results are kept; try unfinished dates later."
        case .serviceUnavailable:
            "arXiv is temporarily unavailable. Saved results are kept; try unfinished dates later."
        }
    }
}

public protocol ArxivSearching: Sendable {
    func discover(query: DiscoveryQuery, now: Date) async throws -> [Paper]
    func discoverBatch(query: DiscoveryQuery, now: Date) async throws -> ArxivSearchBatch
}

public struct ArxivSearchBatch: Codable, Sendable {
    public var papers: [Paper]
    public var isComplete: Bool
    public var rawCount: Int
    public var totalResults: Int?

    public init(papers: [Paper], isComplete: Bool, rawCount: Int? = nil, totalResults: Int? = nil) {
        self.papers = papers
        self.isComplete = isComplete
        self.rawCount = rawCount ?? papers.count
        self.totalResults = totalResults
    }
}

public extension ArxivSearching {
    func discoverBatch(query: DiscoveryQuery, now: Date) async throws -> ArxivSearchBatch {
        let papers = try await discover(query: query, now: now)
        return ArxivSearchBatch(papers: papers, isComplete: papers.count < query.maxResults)
    }
}

public struct ArxivClient: ArxivSearching {
    private let transport: BoundedHTTPClient
    private let endpoint: URL
    private let maximumResponseBytes = 10 * 1024 * 1024

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://export.arxiv.org/api/query")!
    ) {
        self.transport = BoundedHTTPClient(configuration: session.configuration)
        self.endpoint = endpoint
    }

    public func discover(query: DiscoveryQuery, now: Date = Date()) async throws -> [Paper] {
        try await discoverBatch(query: query, now: now).papers
    }

    public func discoverBatch(query: DiscoveryQuery, now: Date = Date()) async throws -> ArxivSearchBatch {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw ArxivClientError.invalidRequest
        }
        guard let searchQuery = query.searchExpression else { throw ArxivClientError.invalidRequest }
        components.queryItems = [
            URLQueryItem(name: "search_query", value: searchQuery),
            URLQueryItem(name: "start", value: String(query.start)),
            URLQueryItem(name: "max_results", value: String(query.maxResults)),
            URLQueryItem(name: "sortBy", value: "submittedDate"),
            URLQueryItem(name: "sortOrder", value: "descending")
        ]
        guard let url = components.url else { throw ArxivClientError.invalidRequest }

        var request = URLRequest(url: url)
        request.timeoutInterval = query.timeoutSeconds
        request.setValue("ArxivDiscovery/0.4.0 (https://github.com/Gnaroshi/Arxiv-newest-paper-crawler)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")

        let (data, httpResponse) = try await transport.data(for: request, timeout: query.timeoutSeconds, maximumBytes: maximumResponseBytes)
        if httpResponse.statusCode == 429 {
            throw ArxivClientError.rateLimited(httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
        }
        if (500...599).contains(httpResponse.statusCode) { throw ArxivClientError.serviceUnavailable }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ArxivClientError.httpStatus(httpResponse.statusCode)
        }
        guard data.count <= maximumResponseBytes else {
            throw ArxivClientError.responseTooLarge
        }

        let feed = try ArxivFeedParser.parsePage(data: data, crawledAt: now)
        let papers = feed.papers
        let accepted = papers
            .filter { $0.publishedAt >= query.interval.start && $0.publishedAt < query.interval.end }
            .filter { query.accepts($0) }
            .sorted { $0.publishedAt > $1.publishedAt }
        let complete = feed.totalResults.map { query.start + feed.rawCount >= $0 } ?? (feed.rawCount < query.maxResults)
        return ArxivSearchBatch(papers: accepted, isComplete: complete, rawCount: feed.rawCount, totalResults: feed.totalResults)
    }

}

public enum ArxivFeedParser {
    public static func parse(data: Data, crawledAt: Date = Date()) throws -> [Paper] {
        try parsePage(data: data, crawledAt: crawledAt).papers
    }

    public static func parsePage(data: Data, crawledAt: Date = Date()) throws -> ArxivSearchBatch {
        guard data.range(of: Data("<!DOCTYPE".utf8)) == nil else { throw ArxivClientError.malformedFeed }
        let delegate = FeedDelegate(crawledAt: crawledAt)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), delegate.error == nil, delegate.sawFeed,
              delegate.rawCount > 0 || delegate.totalResults == 0,
              delegate.rawCount == delegate.papers.count else {
            throw ArxivClientError.malformedFeed
        }
        return ArxivSearchBatch(papers: delegate.papers, isComplete: true, rawCount: delegate.rawCount, totalResults: delegate.totalResults)
    }
}

private final class FeedDelegate: NSObject, XMLParserDelegate {
    private struct Entry {
        var entryID = ""
        var title = ""
        var authors: [String] = []
        var subjects: [String] = []
        var abstract = ""
        var pdfURL = ""
        var published = ""
    }

    let crawledAt: Date
    var papers: [Paper] = []
    var error: Error?
    var sawFeed = false
    var rawCount = 0
    var totalResults: Int?

    private var entry: Entry?
    private var currentElement = ""
    private var text = ""
    private var insideAuthor = false
    private var depth = 0

    init(crawledAt: Date) {
        self.crawledAt = crawledAt
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        text = ""
        if depth == 0 && elementName != "feed" {
            error = ArxivClientError.malformedFeed
            parser.abortParsing()
            return
        }
        depth += 1
        if elementName == "feed" { sawFeed = true }
        if elementName == "entry" {
            rawCount += 1
            entry = Entry()
        } else if elementName == "author" {
            insideAuthor = true
        } else if elementName == "category", let term = attributeDict["term"] {
            entry?.subjects.append(term)
        } else if elementName == "link" {
            let isPDF = attributeDict["title"] == "pdf" || attributeDict["type"] == "application/pdf"
            if isPDF, let href = attributeDict["href"] {
                entry?.pdfURL = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        depth -= 1
        let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        switch elementName {
        case "opensearch:totalResults": totalResults = Int(normalized)
        case "id": entry?.entryID = normalized
        case "title": entry?.title = normalized
        case "summary": entry?.abstract = normalized
        case "published": entry?.published = normalized
        case "name" where insideAuthor:
            if !normalized.isEmpty { entry?.authors.append(normalized) }
        case "author": insideAuthor = false
        case "entry": finishEntry()
        default: break
        }
        text = ""
        currentElement = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = parseError
    }

    private func finishEntry() {
        defer { entry = nil }
        guard let entry,
              !entry.entryID.contains("api/errors"),
              !entry.entryID.isEmpty,
              !entry.title.isEmpty,
              !entry.abstract.isEmpty,
              let publishedAt = ISO8601DateFormatter.arxivDate(from: entry.published)
        else { return }

        let shortID = Self.shortID(from: entry.entryID)
        let pdfURL = entry.pdfURL.isEmpty ? "https://arxiv.org/pdf/\(shortID).pdf" : entry.pdfURL
        papers.append(
            Paper(
                entryID: entry.entryID,
                shortID: shortID,
                title: entry.title,
                authors: entry.authors,
                subjects: entry.subjects,
                abstract: entry.abstract,
                pdfURL: pdfURL,
                publishedAt: publishedAt,
                crawledAt: crawledAt
            )
        )
    }

    private static func shortID(from entryID: String) -> String {
        let raw = entryID.components(separatedBy: "/abs/").last ?? entryID
        return raw.replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
    }
}
