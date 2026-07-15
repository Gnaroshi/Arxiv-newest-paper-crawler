import ArxivDiscoveryCore
import Foundation

enum GeminiTranslationError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case httpStatus(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "The translation request could not be created."
        case .invalidResponse: "Gemini returned an unreadable response."
        case let .httpStatus(code): "Gemini returned HTTP status \(code)."
        case .emptyResponse: "Gemini returned no translated text."
        }
    }
}

struct GeminiTranslator {
    let model: String
    var session: URLSession = .shared

    func translate(_ paper: Paper, apiKey: String) async throws -> String {
        guard let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1/models/\(encodedModel):generateContent")
        else { throw GeminiTranslationError.invalidRequest }

        let prompt = """
        Translate the following public arXiv abstract from English into natural Korean.
        Preserve technical terms, model names, equations, and citations.
        Return only the Korean translation.

        Title: \(paper.title)
        Abstract: \(paper.abstract)
        """
        let payload = GenerateContentRequest(
            contents: [.init(role: "user", parts: [.init(text: prompt)])],
            generationConfig: .init(temperature: 0.1)
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiTranslationError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw GeminiTranslationError.httpStatus(httpResponse.statusCode)
        }
        let result = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        let text = result.candidates
            .flatMap(\.content.parts)
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GeminiTranslationError.emptyResponse }
        return text
    }
}

private struct GenerateContentRequest: Encodable {
    struct Content: Encodable {
        struct Part: Encodable { let text: String }
        let role: String
        let parts: [Part]
    }
    struct Configuration: Encodable { let temperature: Double }
    let contents: [Content]
    let generationConfig: Configuration
}

private struct GenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]
        }
        let content: Content
    }
    let candidates: [Candidate]
}
