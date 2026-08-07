import Foundation

/// Loads and saves per-preset keys and configuration.
///
/// Pre-preset installs stored a single global key plus global model/URL values.
/// Those are copied into the Groq namespace once so Groq keeps working and a
/// second preset can have its own slot.
enum ProviderSettingsStore {
    static let selectedProviderIDKey = "selected_provider_id"
    private static let migratedFlagKey = "provider_settings_migrated_v1"

    static let legacyAPIBaseURLAccount = "api_base_url"
    static let legacyTranscriptionAPIURLAccount = "transcription_api_url"
    static let legacyTranscriptionAPIKeyAccount = "transcription_api_key"
    static let legacyTranscriptionModelKey = "transcription_model"
    static let legacyPostProcessingModelKey = "post_processing_model"
    static let legacyPostProcessingFallbackModelKey = "post_processing_fallback_model"
    static let legacyContextModelKey = "context_model"
    static let legacyRealtimeStreamingModelKey = "realtime_streaming_model"

    static func migrateLegacyGlobalSettingsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: migratedFlagKey) == false,
              defaults.object(forKey: migratedFlagKey) == nil else {
            return
        }

        let groq = GroqProvider.shared
        copyUserDefault(legacyTranscriptionModelKey, to: groq.userDefaultsKey("transcription_model"))
        copyUserDefault(legacyPostProcessingModelKey, to: groq.userDefaultsKey("post_processing_model"))
        copyUserDefault(legacyPostProcessingFallbackModelKey, to: groq.userDefaultsKey("post_processing_fallback_model"))
        copyUserDefault(legacyContextModelKey, to: groq.userDefaultsKey("context_model"))
        copyUserDefault(legacyRealtimeStreamingModelKey, to: groq.userDefaultsKey("realtime_streaming_model"))
        copySecret(from: legacyAPIBaseURLAccount, to: groq.apiBaseURLAccount)
        copySecret(from: legacyTranscriptionAPIURLAccount, to: groq.transcriptionAPIURLAccount)
        copySecret(from: legacyTranscriptionAPIKeyAccount, to: groq.transcriptionAPIKeyAccount)

        if loadSelectedProviderID() == nil {
            let legacyBase = AppSettingsStorage.load(account: legacyAPIBaseURLAccount) ?? groq.defaults.apiBaseURL
            let resolved = ProviderRegistry.resolve(id: nil, baseURL: legacyBase)
            saveSelectedProviderID(resolved.id)
        }

        defaults.set(true, forKey: migratedFlagKey)
    }

    static func loadSelectedProviderID() -> String? {
        UserDefaults.standard.string(forKey: selectedProviderIDKey)
    }

    static func saveSelectedProviderID(_ id: String) {
        UserDefaults.standard.set(id, forKey: selectedProviderIDKey)
    }

    static func loadAPIKey(for provider: any ProviderPreset) -> String {
        loadSecret(account: provider.apiKeyAccount)
    }

    static func saveAPIKey(_ value: String, for provider: any ProviderPreset) {
        saveSecret(value, account: provider.apiKeyAccount)
    }

    static func loadConfiguration(for provider: any ProviderPreset) -> ProviderConfiguration {
        let defaults = provider.defaults
        return ProviderConfiguration(
            apiBaseURL: nonEmpty(loadSecret(account: provider.apiBaseURLAccount), fallback: defaults.apiBaseURL),
            transcriptionModel: nonEmpty(
                UserDefaults.standard.string(forKey: provider.userDefaultsKey("transcription_model")),
                fallback: defaults.transcriptionModel
            ),
            transcriptionAPIURL: loadSecret(account: provider.transcriptionAPIURLAccount),
            transcriptionAPIKey: loadSecret(account: provider.transcriptionAPIKeyAccount),
            realtimeStreamingModel: UserDefaults.standard.string(
                forKey: provider.userDefaultsKey("realtime_streaming_model")
            ) ?? defaults.realtimeStreamingModel,
            postProcessingModel: nonEmpty(
                UserDefaults.standard.string(forKey: provider.userDefaultsKey("post_processing_model")),
                fallback: defaults.postProcessingModel
            ),
            postProcessingFallbackModel: nonEmpty(
                UserDefaults.standard.string(forKey: provider.userDefaultsKey("post_processing_fallback_model")),
                fallback: defaults.postProcessingFallbackModel
            ),
            contextModel: nonEmpty(
                UserDefaults.standard.string(forKey: provider.userDefaultsKey("context_model")),
                fallback: defaults.contextModel
            )
        )
    }

    static func saveConfiguration(_ configuration: ProviderConfiguration, for provider: any ProviderPreset) {
        saveSecret(
            configuration.apiBaseURL == provider.defaults.apiBaseURL ? "" : configuration.apiBaseURL,
            account: provider.apiBaseURLAccount
        )
        saveSecret(configuration.transcriptionAPIURL, account: provider.transcriptionAPIURLAccount)
        saveSecret(configuration.transcriptionAPIKey, account: provider.transcriptionAPIKeyAccount)
        setUserDefault(configuration.transcriptionModel, key: provider.userDefaultsKey("transcription_model"))
        setUserDefault(configuration.realtimeStreamingModel, key: provider.userDefaultsKey("realtime_streaming_model"))
        setUserDefault(configuration.postProcessingModel, key: provider.userDefaultsKey("post_processing_model"))
        setUserDefault(
            configuration.postProcessingFallbackModel,
            key: provider.userDefaultsKey("post_processing_fallback_model")
        )
        setUserDefault(configuration.contextModel, key: provider.userDefaultsKey("context_model"))
    }

    // MARK: - Helpers

    private static func loadSecret(account: String) -> String {
        let stored = AppSettingsStorage.load(account: account) ?? ""
        return stored.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func saveSecret(_ value: String, account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            AppSettingsStorage.delete(account: account)
        } else {
            AppSettingsStorage.save(trimmed, account: account)
        }
    }

    private static func copySecret(from legacyAccount: String, to newAccount: String) {
        let existing = loadSecret(account: newAccount)
        guard existing.isEmpty else { return }
        let legacy = loadSecret(account: legacyAccount)
        guard !legacy.isEmpty else { return }
        saveSecret(legacy, account: newAccount)
    }

    private static func copyUserDefault(_ legacyKey: String, to newKey: String) {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: newKey), !existing.isEmpty {
            return
        }
        guard let legacy = defaults.string(forKey: legacyKey), !legacy.isEmpty else { return }
        defaults.set(legacy, forKey: newKey)
    }

    private static func setUserDefault(_ value: String, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func nonEmpty(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}
