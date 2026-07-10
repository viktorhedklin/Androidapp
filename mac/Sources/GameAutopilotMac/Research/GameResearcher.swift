import Foundation

struct ResearchResult {
    let summary: String
    let questions: [String]
    let suggestedGoalMode: GoalMode
    let usedLiveSearch: Bool
}

/// One-shot pre-game research: given a name + optional user-typed info,
/// asks an LLM to summarize what it knows and suggest clarifying
/// questions, before the target is ever started.
///
/// Default path uses whichever provider is already configured for
/// gameplay (Settings + the main API key) -- zero new keys, works
/// universally, and for any reasonably known target the model's training
/// knowledge plus a well-built prompt is enough. If a separate Gemini
/// research key is present (Settings, optional, stored under its own
/// Keychain account), uses Gemini's `google_search` grounding tool
/// instead for live web results.
///
/// Deliberately does NOT request strict JSON response mode: Gemini's
/// search-grounding tool and `responseMimeType: json` don't reliably
/// coexist, so this asks for JSON in the prompt text and extracts it
/// leniently (reuses BrainResponseParser.stripCodeFences without sharing
/// its strict-mode assumption) -- keeps one parsing shape across both
/// the default and optional-grounding paths rather than two.
enum GameResearcher {
    static func research(
        name: String,
        userInfo: String,
        settings: Settings,
        gameplayApiKey: String,
        researchApiKey: String?
    ) async throws -> ResearchResult {
        let prompt = buildPrompt(name: name, userInfo: userInfo)

        if let researchApiKey, !researchApiKey.isEmpty {
            let text = try await callGeminiWithSearch(prompt: prompt, apiKey: researchApiKey)
            return try parse(text, usedLiveSearch: true)
        }

        let text: String
        switch settings.provider {
        case .gemini:
            text = try await callGemini(
                prompt: prompt, baseUrl: settings.resolvedBaseUrl, apiKey: gameplayApiKey,
                model: settings.resolvedModel, withSearch: false
            )
        case .openai, .nvidia:
            text = try await callOpenAICompatible(
                prompt: prompt, baseUrl: settings.resolvedBaseUrl, apiKey: gameplayApiKey, model: settings.resolvedModel
            )
        }
        return try parse(text, usedLiveSearch: false)
    }

    private static func buildPrompt(name: String, userInfo: String) -> String {
        """
        You're helping set up an autonomous play assistant for a macOS app/game called "\(name)".
        \(userInfo.isEmpty ? "" : "The user also said: \(userInfo)\n")
        Describe what you know about this app/game in 3-6 sentences: what it is, the
        core loop/objective, and anything a vision-based assistant should know before
        playing it (common UI patterns, things to avoid, how progress/currency works).
        If you're not confident you know this specific app/game, say so plainly rather
        than inventing details.

        Then list 0-3 short clarifying questions ONLY if something genuinely important
        is unresolvable from the name/description alone (e.g. "which mode should it
        play?"). Most of the time zero questions is correct -- don't manufacture
        questions just to seem thorough.

        Also judge whether this sounds like a target with a natural finish line
        ("completeGoal") or an open-ended/idle/grinding target with no end
        ("keepRunning").

        Respond with ONLY this JSON, no other text, no markdown fences:
        {"summary":"...","questions":["...", ...],"suggestedGoalMode":"completeGoal"|"keepRunning"}
        """
    }

    private static func parse(_ text: String, usedLiveSearch: Bool) throws -> ResearchResult {
        let cleaned = BrainResponseParser.stripCodeFences(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw BrainError("Research response wasn't valid JSON: \(cleaned.prefix(200))")
        }
        let summary = (obj["summary"] as? String) ?? ""
        let questions = (obj["questions"] as? [String])?.filter { !$0.isEmpty } ?? []
        let modeRaw = ((obj["suggestedGoalMode"] as? String) ?? "keepRunning").lowercased()
        let mode: GoalMode = modeRaw.contains("complete") ? .playUntilComplete : .keepRunning
        return ResearchResult(summary: summary, questions: questions, suggestedGoalMode: mode, usedLiveSearch: usedLiveSearch)
    }

    // MARK: - HTTP
    //
    // Mirrors OpenAICompatibleBrain/GeminiBrain's request shape, but
    // text-only (no screenshot, no strict JSON response mode) -- kept
    // separate rather than forced through the Brain protocol, since the
    // per-tick gameplay contract (screenshot required, strict action
    // schema) isn't a good fit for a one-shot text research call.

    private static func callOpenAICompatible(prompt: String, baseUrl: String, apiKey: String, model: String) async throws -> String {
        guard !apiKey.isEmpty else { throw BrainError("API key not set") }
        let trimmedBase = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        guard let url = URL(string: "\(trimmedBase)/chat/completions") else { throw BrainError("Invalid base URL") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0.3,
            "max_tokens": 600,
            "messages": [["role": "user", "content": prompt]]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw BrainError("Research request failed: \(text.prefix(300))")
        }
        guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = outer["choices"] as? [[String: Any]], !choices.isEmpty,
              let message = choices[0]["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw BrainError("No content in research response") }
        return content
    }

    private static func callGeminiWithSearch(prompt: String, apiKey: String) async throws -> String {
        try await callGemini(
            prompt: prompt, baseUrl: Settings.defaultGeminiUrl, apiKey: apiKey,
            model: Settings.defaultGeminiModel, withSearch: true
        )
    }

    private static func callGemini(prompt: String, baseUrl: String, apiKey: String, model: String, withSearch: Bool) async throws -> String {
        guard !apiKey.isEmpty else { throw BrainError("API key not set") }
        let trimmedBase = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        guard let url = URL(string: "\(trimmedBase)/models/\(model):generateContent") else { throw BrainError("Invalid base URL") }

        var body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.3, "maxOutputTokens": 600]
        ]
        if withSearch {
            body["tools"] = [["google_search": [String: Any]()]]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw BrainError("Research request failed: \(text.prefix(300))")
        }
        guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = outer["candidates"] as? [[String: Any]], !candidates.isEmpty,
              let content = candidates[0]["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else { throw BrainError("No content in research response") }
        return parts.compactMap { $0["text"] as? String }.joined()
    }
}
