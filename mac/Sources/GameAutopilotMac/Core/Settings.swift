import Foundation

/// Mirrors data/Settings.kt's BrainProvider. The API key is deliberately
/// NOT part of this struct -- it lives in Keychain (Util/Keychain.swift)
/// and callers merge it in separately, so it never round-trips through
/// UserDefaults/Codable.
enum BrainProvider: String, CaseIterable, Codable {
    case openai
    case nvidia
    case gemini

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .nvidia: return "NVIDIA NIM"
        case .gemini: return "Google Gemini"
        }
    }
}

struct Settings: Codable, Equatable {
    var provider: BrainProvider = .openai
    var baseUrl: String = ""
    var model: String = ""
    var maxActionsPerMinute: Int = 30
    var onlyActOnTarget: Bool = true
    var useSetOfMarks: Bool = true
    var tickIntervalMs: Int = 1500

    static let defaultOpenAIUrl = "https://api.openai.com/v1"
    static let defaultOpenAIModel = "gpt-4o-mini"
    static let defaultNvidiaUrl = "https://integrate.api.nvidia.com/v1"
    static let defaultNvidiaModel = "meta/llama-3.2-90b-vision-instruct"
    static let defaultGeminiUrl = "https://generativelanguage.googleapis.com/v1beta"
    // gemini-3.5-flash is GA and vision/Computer-Use capable as of mid-2026 --
    // gemini-3.5-pro does not exist yet at time of writing. Paste a different
    // model id into Settings > Model once a stronger one ships; no code change needed.
    static let defaultGeminiModel = "gemini-3.5-flash"

    static func defaultUrl(for provider: BrainProvider) -> String {
        switch provider {
        case .openai: return defaultOpenAIUrl
        case .nvidia: return defaultNvidiaUrl
        case .gemini: return defaultGeminiUrl
        }
    }

    static func defaultModel(for provider: BrainProvider) -> String {
        switch provider {
        case .openai: return defaultOpenAIModel
        case .nvidia: return defaultNvidiaModel
        case .gemini: return defaultGeminiModel
        }
    }

    /// Resolved base URL/model, falling back to the provider's default
    /// when the user hasn't overridden it. Use these, not the raw stored
    /// fields, when actually constructing a Brain.
    var resolvedBaseUrl: String { baseUrl.isEmpty ? Self.defaultUrl(for: provider) : baseUrl }
    var resolvedModel: String { model.isEmpty ? Self.defaultModel(for: provider) : model }
}

/// UserDefaults-backed settings store. Everything except the API key lives
/// here as plain Codable JSON -- fine, since none of it is a secret.
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: Settings

    private let defaults: UserDefaults
    private static let key = "com.gameautopilot.mac.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = Settings()
        }
    }

    func save(_ s: Settings) {
        settings = s
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
