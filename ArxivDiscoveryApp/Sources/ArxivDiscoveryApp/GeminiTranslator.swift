import ArxivDiscoveryCore
import Foundation

enum GeminiTranslationError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case httpStatus(Int, String?)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "The Gemini request could not be created."
        case .invalidResponse: "Gemini returned an unreadable response."
        case let .httpStatus(code, message): message ?? "Gemini returned HTTP status \(code)."
        case .emptyResponse: "Gemini returned no translated text."
        }
    }
}

struct GeminiModel: Codable, Hashable, Identifiable {
    let name: String
    let displayName: String
    let inputTokenLimit: Int?
    let outputTokenLimit: Int?
    let supportedGenerationMethods: [String]

    var id: String { modelID }
    var modelID: String { name.replacingOccurrences(of: "models/", with: "") }
}

struct GeminiTranslationResult {
    let text: String
    let usage: TranslationTokenUsage
}

struct GeminiClient {
    var session: URLSession = .shared

    func listModels(apiKey: String) async throws -> [GeminiModel] {
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models") else {
            throw GeminiTranslationError.invalidRequest
        }
        components.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
        guard let url = components.url else { throw GeminiTranslationError.invalidRequest }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let result = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return result.models
            .filter { $0.supportedGenerationMethods.contains("generateContent") }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func translate(_ paper: Paper, model: String, apiKey: String) async throws -> GeminiTranslationResult {
        guard let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent")
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
        try validate(response: response, data: data)
        let result = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        let text = result.candidates
            .flatMap(\.content.parts)
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GeminiTranslationError.emptyResponse }
        let metadata = result.usageMetadata
        return GeminiTranslationResult(
            text: text,
            usage: TranslationTokenUsage(
                promptTokens: metadata?.promptTokenCount ?? 0,
                responseTokens: metadata?.candidatesTokenCount ?? 0,
                thinkingTokens: metadata?.thoughtsTokenCount ?? 0,
                totalTokens: metadata?.totalTokenCount ?? 0
            )
        )
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiTranslationError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data))?.error.message
            throw GeminiTranslationError.httpStatus(httpResponse.statusCode, message)
        }
    }
}

private struct ModelListResponse: Decodable {
    let models: [GeminiModel]
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
    struct UsageMetadata: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
        let thoughtsTokenCount: Int?
        let totalTokenCount: Int?
    }
    let candidates: [Candidate]
    let usageMetadata: UsageMetadata?
}

private struct GeminiErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}
