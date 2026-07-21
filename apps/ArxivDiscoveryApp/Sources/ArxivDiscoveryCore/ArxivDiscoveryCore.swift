import Foundation

public struct ArxivCandidate: Codable, Hashable, Identifiable, Sendable {
    public let candidateId: String
    public let arxivId: String
    public let title: String
    public let authors: [String]
    public let abstract: String
    public let categories: [String]
    public let submittedAt: String
    public let updatedAt: String?
    public let paperUrl: URL
    public let pdfUrl: URL

    public var id: String { candidateId }

    public init(
        candidateId: String,
        arxivId: String,
        title: String,
        authors: [String],
        abstract: String,
        categories: [String],
        submittedAt: String,
        updatedAt: String?,
        paperUrl: URL,
        pdfUrl: URL
    ) {
        self.candidateId = candidateId
        self.arxivId = arxivId
        self.title = title
        self.authors = authors
        self.abstract = abstract
        self.categories = categories
        self.submittedAt = submittedAt
        self.updatedAt = updatedAt
        self.paperUrl = paperUrl
        self.pdfUrl = pdfUrl
    }
}

public struct DiscoveryQuery: Equatable, Sendable {
    public var categories: [String]
    public var days: Int
    public var maxResults: Int

    public init(categories: [String], days: Int, maxResults: Int) {
        self.categories = categories
        self.days = days
        self.maxResults = maxResults
    }

    public func validated() throws -> DiscoveryQuery {
        let normalized = categories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty,
              normalized.allSatisfy({ $0.range(of: #"^[a-zA-Z-]+(\.[a-zA-Z-]+)?$"#, options: .regularExpression) != nil })
        else { throw DiscoveryError.invalidCategories }
        guard (1...31).contains(days) else { throw DiscoveryError.invalidDays }
        guard (1...200).contains(maxResults) else { throw DiscoveryError.invalidMaxResults }
        return DiscoveryQuery(categories: normalized, days: days, maxResults: maxResults)
    }
}

public enum DiscoveryError: LocalizedError, Equatable {
    case invalidCategories
    case invalidDays
    case invalidMaxResults
    case invalidResponse
    case serverStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidCategories: "Enter one or more arXiv categories such as cs.AI or cs.CL."
        case .invalidDays: "Choose a discovery window from 1 to 31 days."
        case .invalidMaxResults: "Choose a result limit from 1 to 200."
        case .invalidResponse: "arXiv returned data that could not be read."
        case .serverStatus(let code): "arXiv returned HTTP status \(code)."
        }
    }
}

public struct ArxivAPIClient: Sendable {
    public init() {}

    public func endpoint(for query: DiscoveryQuery) throws -> URL {
        let query = try query.validated()
        let categoryExpression = query.categories.map { "cat:\($0)" }.joined(separator: " OR ")
        var components = URLComponents(string: "https://export.arxiv.org/api/query")
        components?.queryItems = [
            URLQueryItem(name: "search_query", value: categoryExpression),
            URLQueryItem(name: "sortBy", value: "submittedDate"),
            URLQueryItem(name: "sortOrder", value: "descending"),
            URLQueryItem(name: "start", value: "0"),
            URLQueryItem(name: "max_results", value: String(query.maxResults)),
        ]
        guard let url = components?.url else { throw DiscoveryError.invalidResponse }
        return url
    }

    public func discover(_ query: DiscoveryQuery, session: URLSession = .shared) async throws -> [ArxivCandidate] {
        let validated = try query.validated()
        var request = URLRequest(url: try endpoint(for: validated))
        request.timeoutInterval = 30
        request.setValue("Gnaroshi-Arxiv-Discovery/0.4.0 (contact: github.com/Gnaroshi)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw DiscoveryError.invalidResponse }
        guard response.statusCode == 200 else { throw DiscoveryError.serverStatus(response.statusCode) }
        let candidates = try ArxivFeedParser.parse(data)
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -validated.days, to: Date()) ?? .distantPast
        let formatter = ISO8601DateFormatter()
        return candidates.filter { candidate in
            guard let date = formatter.date(from: candidate.submittedAt) else { return true }
            return date >= cutoff
        }
    }
}

public enum ArxivFeedParser {
    public static func parse(_ data: Data) throws -> [ArxivCandidate] {
        let delegate = FeedDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.parseError == nil else { throw DiscoveryError.invalidResponse }
        return delegate.candidates
    }
}

private final class FeedDelegate: NSObject, XMLParserDelegate {
    struct Entry {
        var title = ""
        var identifier = ""
        var abstract = ""
        var submittedAt = ""
        var updatedAt = ""
        var authors: [String] = []
        var categories: [String] = []
        var pdfURL: String?
    }

    var candidates: [ArxivCandidate] = []
    var parseError: Error?
    private var entry: Entry?
    private var element = ""
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        element = elementName
        text = ""
        if elementName == "entry" { entry = Entry() }
        guard entry != nil else { return }
        if elementName == "category", let term = attributeDict["term"], !term.isEmpty { entry?.categories.append(term) }
        if elementName == "link", attributeDict["type"] == "application/pdf", let href = attributeDict["href"] { entry?.pdfURL = href }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard var current = entry else { return }
        let value = normalize(text)
        switch elementName {
        case "title": current.title = value
        case "id": current.identifier = value
        case "summary": current.abstract = value
        case "published": current.submittedAt = value
        case "updated": current.updatedAt = value
        case "name" where element == "name" && !value.isEmpty: current.authors.append(value)
        case "entry":
            if let candidate = makeCandidate(current) { candidates.append(candidate) }
            entry = nil
            text = ""
            return
        default: break
        }
        entry = current
        text = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) { self.parseError = parseError }

    private func normalize(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private func makeCandidate(_ entry: Entry) -> ArxivCandidate? {
        guard let paperURL = URL(string: entry.identifier), paperURL.scheme == "https" else { return nil }
        let identifier = paperURL.lastPathComponent
        guard identifier.range(of: #"^(\d{4}\.\d{4,5}|[a-zA-Z-]+(\.[A-Z]{2})?/\d{7})(v\d+)?$"#, options: .regularExpression) != nil else { return nil }
        let baseIdentifier = identifier.replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
        guard let pdfURL = URL(string: entry.pdfURL ?? "https://arxiv.org/pdf/\(identifier)"), pdfURL.scheme == "https" else { return nil }
        return ArxivCandidate(
            candidateId: "arxiv:\(baseIdentifier.lowercased())",
            arxivId: identifier,
            title: entry.title,
            authors: entry.authors,
            abstract: entry.abstract,
            categories: entry.categories,
            submittedAt: entry.submittedAt,
            updatedAt: entry.updatedAt.isEmpty ? nil : entry.updatedAt,
            paperUrl: paperURL,
            pdfUrl: pdfURL
        )
    }
}
