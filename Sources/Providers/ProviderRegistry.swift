import Foundation

/// All built-in provider presets. Register additional presets here.
enum ProviderRegistry {
    static var all: [any ProviderPreset] {
        [GroqProvider.shared]
    }

    static var `default`: any ProviderPreset { GroqProvider.shared }

    static func provider(id: String) -> (any ProviderPreset)? {
        all.first { $0.id == id }
    }

    static func provider(matchingBaseURL baseURL: String) -> (any ProviderPreset)? {
        all.first { $0.matches(baseURL: baseURL) }
    }

    /// Resolve the active preset from a stored id, falling back to host matching
    /// and finally to Groq.
    static func resolve(id: String?, baseURL: String) -> any ProviderPreset {
        if let id, let provider = provider(id: id) {
            return provider
        }
        if let matched = provider(matchingBaseURL: baseURL) {
            return matched
        }
        return `default`
    }
}
