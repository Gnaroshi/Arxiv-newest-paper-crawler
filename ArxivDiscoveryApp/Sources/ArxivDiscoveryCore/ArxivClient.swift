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
        }
    }
}

public protocol ArxivSearching {
    func discover(query: DiscoveryQuery, now: Date) async throws -> [Paper]
}

public struct ArxivClient: ArxivSearching {
    private let session: URLSession
    private let endpoint: URL
    private let maximumResponseBytes = 10 * 1024 * 1024

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://export.arxiv.org/api/query")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    public func discover(query: DiscoveryQuery, now: Date = Date()) async throws -> [Paper] {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw ArxivClientError.invalidRequest
        }
        let categoryQuery = query.categories.map { "cat:\($0)" }.joined(separator: " OR ")
        components.queryItems = [
            URLQueryItem(name: "search_query", value: categoryQuery),
            URLQueryItem(name: "start", value: "0"),
            URLQueryItem(name: "max_results", value: String(query.maxResults)),
            URLQueryItem(name: "sortBy", value: "submittedDate"),
            URLQueryItem(name: "sortOrder", value: "descending")
        ]
        guard let url = components.url else { throw ArxivClientError.invalidRequest }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("ArxivDiscovery/0.2.0 (https://github.com/Gnaroshi/Arxiv-newest-paper-crawler)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ArxivClientError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ArxivClientError.httpStatus(httpResponse.statusCode)
        }
        guard data.count <= maximumResponseBytes else {
            throw ArxivClientError.responseTooLarge
        }

        let papers = try ArxivFeedParser.parse(data: data, crawledAt: now)
        let cutoff = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: -query.days,
            to: now
        ) ?? now.addingTimeInterval(TimeInterval(-query.days * 86_400))
        return papers
            .filter { $0.publishedAt >= cutoff && $0.publishedAt <= now }
            .sorted { $0.publishedAt > $1.publishedAt }
    }
}

public enum ArxivFeedParser {
    public static func parse(data: Data, crawledAt: Date = Date()) throws -> [Paper] {
        let delegate = FeedDelegate(crawledAt: crawledAt)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse(), delegate.error == nil else {
            throw delegate.error ?? ArxivClientError.malformedFeed
        }
        return delegate.papers
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

    private var entry: Entry?
    private var currentElement = ""
    private var text = ""
    private var insideAuthor = false

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
        if elementName == "entry" {
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
        let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        switch elementName {
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
        let raw = URL(string: entryID)?.lastPathComponent ?? entryID
        return raw.replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
    }
}
