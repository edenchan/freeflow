import Foundation

/// A first-class API provider preset.
///
/// FreeFlow keeps one active preset at a time. Each preset owns its default
/// models and URLs, plus an isolated storage namespace for the user's API key
/// and any overrides, so adding another preset cannot clobber Groq settings.
protocol ProviderPreset: Sendable {
    var id: String { get }
    var displayName: String { get }
    var keyPlaceholder: String { get }
    /// Account name in `AppSettingsStorage` for this preset's primary API key.
    var apiKeyAccount: String { get }
    var iconResourceName: String? { get }
    var defaults: ProviderConfiguration { get }

    var onboardingHeading: String { get }
    var onboardingSteps: [String] { get }

    /// Whether `baseURL` is this preset's hosted API (used only for migration).
    func matches(baseURL: String) -> Bool

    func transcriptionURL(from baseURL: URL) -> URL

    func transcriptionFormFields(
        model: String,
        responseFormat: String,
        language: String?,
        includeFillerWords: Bool,
        keyTerms: [String]
    ) -> [(name: String, value: String)]

    func makeRealtimeSession(
        config: RealtimeTranscriptionService.Configuration
    ) -> any LiveTranscriptionSession
}

extension ProviderPreset {
    var iconResourceName: String? { nil }

    var transcriptionAPIURLAccount: String { "provider.\(id).transcription_api_url" }
    var transcriptionAPIKeyAccount: String { "provider.\(id).transcription_api_key" }
    var apiBaseURLAccount: String { "provider.\(id).api_base_url" }

    func userDefaultsKey(_ name: String) -> String {
        "provider.\(id).\(name)"
    }

    func transcriptionURL(from baseURL: URL) -> URL {
        let normalizedPath = baseURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        if normalizedPath.hasSuffix("audio/transcriptions") {
            return baseURL
        }
        return baseURL
            .appendingPathComponent("audio")
            .appendingPathComponent("transcriptions")
    }

    func transcriptionFormFields(
        model: String,
        responseFormat: String,
        language: String?,
        includeFillerWords: Bool,
        keyTerms: [String]
    ) -> [(name: String, value: String)] {
        var fields = [
            ("model", model),
            ("response_format", responseFormat)
        ]
        if let language, !language.isEmpty {
            fields.append(("language", language))
        }
        return fields
    }

    func makeRealtimeSession(
        config: RealtimeTranscriptionService.Configuration
    ) -> any LiveTranscriptionSession {
        RealtimeTranscriptionService(config: config)
    }
}
