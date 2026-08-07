import Foundation

/// Groq Cloud — FreeFlow's default OpenAI-compatible preset.
struct GroqProvider: ProviderPreset {
    static let shared = GroqProvider()

    let id = "groq"
    let displayName = "Groq"
    let keyPlaceholder = "Enter your Groq API key"
    /// Keep the historical account name so existing installs do not lose their key.
    let apiKeyAccount = "groq_api_key"

    let onboardingHeading = "Using Groq?"
    let onboardingSteps = [
        "Go to [console.groq.com/keys](https://console.groq.com/keys)",
        "Create a free account (if you don't have one)",
        "Click **Create API Key** and copy it"
    ]

    var defaults: ProviderConfiguration {
        ProviderConfiguration(
            apiBaseURL: "https://api.groq.com/openai/v1",
            transcriptionModel: "whisper-large-v3",
            transcriptionAPIURL: "",
            transcriptionAPIKey: "",
            realtimeStreamingModel: "",
            postProcessingModel: "openai/gpt-oss-20b",
            postProcessingFallbackModel: "qwen/qwen3.6-27b",
            contextModel: "qwen/qwen3.6-27b"
        )
    }

    func matches(baseURL: String) -> Bool {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = URL(string: trimmed)?.host?.lowercased(), !host.isEmpty else {
            return false
        }
        return host == "api.groq.com" || host.hasSuffix(".api.groq.com")
    }
}
