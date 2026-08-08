import Foundation

/// xAI Grok — hosted STT (`/v1/stt` and `wss://api.x.ai/v1/stt`) plus Grok chat models.
struct GrokProvider: ProviderPreset {
    static let shared = GrokProvider()

    static let defaultBaseURL = "https://api.x.ai/v1"
    static let defaultSTTModel = "grok-stt"
    static let maxKeyTerms = 100
    static let maxKeyTermLength = 50
    /// Match FreeFlow's realtime PCM tap (`AudioRecorder` emits 24 kHz PCM16).
    static let streamingSampleRate = 24_000
    static let streamingEndpointingMs = 400

    /// Languages for which Grok STT accepts `format=true` (inverse text
    /// normalization of numbers, currencies, and units).
    static let formattingLanguages: Set<String> = [
        "ar", "cs", "da", "nl", "en", "fil", "fr", "de", "hi", "id", "it",
        "ja", "ko", "mk", "ms", "fa", "pl", "pt", "ro", "ru", "es", "sv",
        "th", "tr", "vi"
    ]

    /// Grok STT rejects `auto`. Empty/auto → system locale if catalogued, else `en`.
    static func languageForAPI(_ preferred: String?) -> String {
        let trimmed = preferred?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, trimmed.lowercased() != "auto" {
            return trimmed
        }
        if let code = Locale.current.language.languageCode?.identifier,
           formattingLanguages.contains(code) {
            return code
        }
        return "en"
    }

    static let llmModels = ["grok-4.5", "grok-4.3"]
    static let visionModels = ["grok-4.5"]
    static let transcriptionModels = ["grok-stt"]

    let id = "xai"
    let displayName = "Grok (xAI)"
    let keyPlaceholder = "Paste your Grok API key"
    let apiKeyAccount = "xai_api_key"
    let iconResourceName: String? = "GrokMark"

    let onboardingHeading = "Using Grok (xAI)?"
    let onboardingSteps = [
        "Go to [console.x.ai](https://console.x.ai)",
        "Create an account and an API key",
        "Paste the key below — Grok STT, cleanup, and context all use it"
    ]

    var defaults: ProviderConfiguration {
        ProviderConfiguration(
            apiBaseURL: Self.defaultBaseURL,
            transcriptionModel: Self.defaultSTTModel,
            transcriptionAPIURL: "",
            transcriptionAPIKey: "",
            realtimeStreamingModel: "",
            postProcessingModel: "grok-4.5",
            postProcessingFallbackModel: "grok-4.3",
            contextModel: "grok-4.5"
        )
    }

    func matches(baseURL: String) -> Bool {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = URL(string: trimmed)?.host?.lowercased(), !host.isEmpty else {
            return false
        }
        return host == "api.x.ai" || host.hasSuffix(".api.x.ai") || host == "x.ai"
    }

    func transcriptionURL(from baseURL: URL) -> URL {
        let normalizedPath = baseURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        if normalizedPath.hasSuffix("stt") {
            return baseURL
        }
        return baseURL.appendingPathComponent("stt")
    }

    func transcriptionFormFields(
        model: String,
        responseFormat: String,
        language: String?,
        includeFillerWords: Bool,
        keyTerms: [String]
    ) -> [(name: String, value: String)] {
        var fields: [(String, String)] = []

        if let language, !language.isEmpty {
            fields.append(("language", language))
            if Self.formattingLanguages.contains(language) {
                fields.append(("format", "true"))
            }
        }

        // API default is false (strip uh/um). Exact wording is LLM-only; don't
        // force fillers on just because cleanup is skipped.
        fields.append(("filler_words", "false"))

        for term in keyTerms.prefix(Self.maxKeyTerms) {
            let trimmed = String(term.prefix(Self.maxKeyTermLength))
            guard !trimmed.isEmpty else { continue }
            fields.append(("keyterm", trimmed))
        }

        return fields
    }

    func vocabularyKeyTerms(from raw: String) -> [String] {
        Self.keyTerms(fromVocabulary: raw)
    }

    func makeRealtimeSession(
        config: RealtimeTranscriptionService.Configuration
    ) -> any LiveTranscriptionSession {
        GrokRealtimeTranscriptionService(
            config: GrokRealtimeTranscriptionService.Configuration(
                baseURL: config.baseURL,
                apiKey: config.apiKey,
                language: config.language,
                keyTerms: config.keyTerms,
                includeFillerWords: config.includeFillerWords,
                sampleRate: Self.streamingSampleRate
            )
        )
    }

    /// Parse custom vocabulary into Grok `keyterm` values.
    static func keyTerms(fromVocabulary raw: String) -> [String] {
        let terms = raw
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= maxKeyTermLength }

        var seen = Set<String>()
        var unique: [String] = []
        unique.reserveCapacity(min(terms.count, maxKeyTerms))
        for term in terms {
            guard seen.insert(term.lowercased()).inserted else { continue }
            unique.append(term)
            if unique.count == maxKeyTerms { break }
        }
        return unique
    }

    static func modelConfig(for model: String) -> ModelConfig? {
        switch model {
        case "grok-4.5":
            return ModelConfig(
                maxCompletionTokens: 4096,
                reasoningEffort: "low",
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        case "grok-4.3":
            return ModelConfig(
                maxCompletionTokens: 4096,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        default:
            return nil
        }
    }

    static func isSTTModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == defaultSTTModel
            || normalized.hasPrefix("grok-stt-")
            || normalized == "grok-speech-to-text"
    }

    /// `wss://api.x.ai/v1/stt` with query-parameter configuration.
    static func streamingWebSocketURL(
        baseURL: String,
        language: String?,
        keyTerms: [String],
        includeFillerWords: Bool,
        sampleRate: Int = streamingSampleRate
    ) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return nil }

        switch components.scheme?.lowercased() {
        case "http": components.scheme = "ws"
        case "https": components.scheme = "wss"
        case "ws", "wss": break
        default: return nil
        }

        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/stt") {
            // already the streaming endpoint
        } else if path.hasSuffix("/v1") {
            path += "/stt"
        } else {
            path += "/v1/stt"
        }
        components.path = path

        var queryItems = (components.queryItems ?? []).filter { item in
            !["sample_rate", "encoding", "interim_results", "filler_words", "language", "keyterm", "endpointing", "format"].contains(item.name)
        }
        let languageCode = languageForAPI(language)
        queryItems.append(URLQueryItem(name: "sample_rate", value: String(sampleRate)))
        queryItems.append(URLQueryItem(name: "encoding", value: "pcm"))
        queryItems.append(URLQueryItem(name: "interim_results", value: "true"))
        queryItems.append(URLQueryItem(name: "endpointing", value: String(streamingEndpointingMs)))
        queryItems.append(URLQueryItem(name: "filler_words", value: "false"))
        queryItems.append(URLQueryItem(name: "language", value: languageCode))
        if formattingLanguages.contains(languageCode) {
            queryItems.append(URLQueryItem(name: "format", value: "true"))
        }
        for term in keyTerms.prefix(maxKeyTerms) {
            let trimmedTerm = String(term.prefix(maxKeyTermLength))
            guard !trimmedTerm.isEmpty else { continue }
            queryItems.append(URLQueryItem(name: "keyterm", value: trimmedTerm))
        }
        components.queryItems = queryItems
        return components.url
    }

    /// If an earlier build stored an xAI key in the Groq slot while the base URL
    /// already pointed at api.x.ai, copy it into the Grok slot once.
    static func migrateLegacySharedKeyIfNeeded() {
        let flagKey = "grok_provider_key_migrated_v1"
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: flagKey) == nil else { return }

        let grok = shared
        if ProviderSettingsStore.loadAPIKey(for: grok).isEmpty {
            let groqKey = ProviderSettingsStore.loadAPIKey(for: GroqProvider.shared)
            let groqConfig = ProviderSettingsStore.loadConfiguration(for: GroqProvider.shared)
            if !groqKey.isEmpty, grok.matches(baseURL: groqConfig.apiBaseURL) {
                ProviderSettingsStore.saveAPIKey(groqKey, for: grok)
            }
        }

        defaults.set(true, forKey: flagKey)
    }
}
