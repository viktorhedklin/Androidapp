import Foundation

enum BrainFactory {
    static func create(settings: Settings, apiKey: String) -> Brain {
        switch settings.provider {
        case .gemini:
            return GeminiBrain(baseUrl: settings.resolvedBaseUrl, apiKey: apiKey, model: settings.resolvedModel)
        case .openai, .nvidia:
            return OpenAICompatibleBrain(baseUrl: settings.resolvedBaseUrl, apiKey: apiKey, model: settings.resolvedModel)
        }
    }
}
