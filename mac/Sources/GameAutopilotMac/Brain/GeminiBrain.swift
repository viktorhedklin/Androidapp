import Foundation

/// Brain backed by Google's Gemini REST API (`generateContent`). Same
/// strict-JSON schema as OpenAICompatibleBrain (PromptBuilder /
/// BrainResponseParser) -- only the request/response envelope differs:
/// Gemini takes a `system_instruction` + `contents[].parts[]` body with
/// inline base64 image data, and returns
/// `candidates[].content.parts[].text`. Mirrors GeminiBrain.kt.
final class GeminiBrain: Brain {
    private let baseUrl: String
    private let apiKey: String
    private let model: String
    private let session: URLSession

    init(baseUrl: String, apiKey: String, model: String, session: URLSession = .shared) {
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func decide(_ ctx: BrainContext) async throws -> BrainDecision {
        guard !apiKey.isEmpty else { throw BrainError("API key not set") }

        let trimmedBase = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        guard let url = URL(string: "\(trimmedBase)/models/\(model):generateContent") else {
            throw BrainError("Invalid base URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: buildRequestBody(ctx))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BrainError("Network error: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw BrainError("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw BrainError("HTTP \(http.statusCode): \(text.prefix(400))")
        }

        return try parseDecision(data)
    }

    private func buildRequestBody(_ ctx: BrainContext) -> [String: Any] {
        [
            "system_instruction": [
                "parts": [["text": PromptBuilder.systemPrompt(ctx)]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": PromptBuilder.userText(ctx)],
                        ["inline_data": ["mime_type": "image/jpeg", "data": ctx.screenshotBase64Jpeg]]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 800,
                "responseMimeType": "application/json"
            ]
        ]
    }

    private func parseDecision(_ data: Data) throws -> BrainDecision {
        guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BrainError("Malformed response body")
        }
        guard let candidates = outer["candidates"] as? [[String: Any]], !candidates.isEmpty else {
            let blockReason = (outer["promptFeedback"] as? [String: Any])?["blockReason"] as? String
            throw BrainError("No candidates in response" + (blockReason.map { " (blocked: \($0))" } ?? ""))
        }
        guard let content = candidates[0]["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else {
            throw BrainError("No content parts in first candidate")
        }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else {
            throw BrainError("Empty text from Gemini response")
        }
        return try BrainResponseParser.parse(text)
    }
}
