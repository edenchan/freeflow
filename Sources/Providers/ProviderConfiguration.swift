import Foundation

/// Persisted, per-preset connection settings. Secrets (API keys) are stored
/// separately via `ProviderPreset.apiKeyAccount`.
struct ProviderConfiguration: Equatable {
    var apiBaseURL: String
    var transcriptionModel: String
    var transcriptionAPIURL: String
    var transcriptionAPIKey: String
    var realtimeStreamingModel: String
    var postProcessingModel: String
    var postProcessingFallbackModel: String
    var contextModel: String
}
