import ArxivDiscoveryCore
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

do {
    let endpoint = try ArxivAPIClient().endpoint(for: DiscoveryQuery(categories: ["cs.AI", "cs.CL"], days: 2, maxResults: 40))
    let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
    require(components?.scheme == "https", "discovery endpoint must use HTTPS")
    require(components?.host == "export.arxiv.org", "discovery endpoint must be arXiv")
    require(components?.queryItems?.first(where: { $0.name == "search_query" })?.value == "cat:cs.AI OR cat:cs.CL", "category query mismatch")
    require(components?.queryItems?.first(where: { $0.name == "max_results" })?.value == "40", "result limit mismatch")
    do {
        _ = try ArxivAPIClient().endpoint(for: DiscoveryQuery(categories: ["cs.AI;open /tmp/x"], days: 2, maxResults: 40))
        require(false, "unsafe category was accepted")
    } catch DiscoveryError.invalidCategories {
        // Expected.
    }

    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom"><entry>
      <id>https://arxiv.org/abs/2401.00001v2</id>
      <updated>2026-07-20T00:00:00Z</updated><published>2026-07-19T00:00:00Z</published>
      <title> A useful paper </title><summary> A bounded abstract. </summary>
      <author><name>Ada Example</name></author><category term="cs.AI" />
      <link href="https://arxiv.org/pdf/2401.00001v2" type="application/pdf" />
    </entry></feed>
    """
    guard let candidate = try ArxivFeedParser.parse(Data(xml.utf8)).first else {
        require(false, "fixture candidate was not parsed")
        exit(1)
    }
    require(candidate.candidateId == "arxiv:2401.00001", "stable candidate ID mismatch")
    require(candidate.title == "A useful paper", "title normalization mismatch")
    require(candidate.authors == ["Ada Example"], "author parsing mismatch")
    require(candidate.categories == ["cs.AI"], "category parsing mismatch")
    require(candidate.paperUrl.absoluteString == "https://arxiv.org/abs/2401.00001v2", "paper URL mismatch")
    print("PASS: native Arxiv Discovery core contract")
} catch {
    FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
    exit(1)
}
