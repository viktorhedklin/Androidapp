import Foundation

/// OpenAI-compatible `/chat/completions` brain -- used for both the OpenAI
/// and NVIDIA NIM providers (NIM speaks the same request/response shape).
/// Mirrors OpenAiCompatibleBrain.kt with URLSession instead of OkHttp and
/// JSONSerialization instead of org.json.
final class OpenAICompatibleBrain: Brain {
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
        guard let url = URL(string: "\(trimmedBase)/chat/completions") else {
            throw BrainError("Invalid base URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
        let systemMsg: [String: Any] = ["role": "system", "content": PromptBuilder.systemPrompt(ctx)]
        let userMsg: [String: Any] = [
            "role": "user",
            "content": [
                ["type": "text", "text": PromptBuilder.userText(ctx)],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(ctx.screenshotBase64Jpeg)"]]
            ]
        ]
        return [
            "model": model,
            "temperature": 0.2,
            "max_tokens": 800,
            "response_format": ["type": "json_object"],
            "messages": [systemMsg, userMsg]
        ]
    }

    private func parseDecision(_ data: Data) throws -> BrainDecision {
        guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BrainError("Malformed response body")
        }
        guard let choices = outer["choices"] as? [[String: Any]], !choices.isEmpty else {
            throw BrainError("No choices in response")
        }
        guard let message = choices[0]["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw BrainError("No content in first choice")
        }
        return try BrainResponseParser.parse(content)
    }
}
