import Foundation

enum ProviderPresetTests {
    static func run() {
        testRegistryDefaultsToGroq()
        testGroqMatchesHostedAPI()
        testGroqTranscriptionURL()
        testGroqFormFieldsAreOpenAICompatible()
        testResolveFallsBackToGroq()
        print("ProviderPresetTests passed")
    }

    private static func testRegistryDefaultsToGroq() {
        expect(ProviderRegistry.default.id == "groq", "Default preset should be Groq")
        expect(ProviderRegistry.all.contains(where: { $0.id == "groq" }), "Groq should be registered")
        expectEqual(ProviderRegistry.all.count, 1)
    }

    private static func testGroqMatchesHostedAPI() {
        let groq = GroqProvider.shared
        expect(groq.matches(baseURL: "https://api.groq.com/openai/v1"), "Groq host should match")
        expect(groq.matches(baseURL: "https://api.groq.com/openai/v1/") == true, "Trailing slash should match")
        expect(!groq.matches(baseURL: "https://api.openai.com/v1"), "OpenAI host should not match Groq")
    }

    private static func testGroqTranscriptionURL() {
        let base = URL(string: "https://api.groq.com/openai/v1")!
        expectEqual(
            GroqProvider.shared.transcriptionURL(from: base).absoluteString,
            "https://api.groq.com/openai/v1/audio/transcriptions"
        )

        let alreadySuffixed = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        expectEqual(
            GroqProvider.shared.transcriptionURL(from: alreadySuffixed).absoluteString,
            "https://api.groq.com/openai/v1/audio/transcriptions"
        )
    }

    private static func testGroqFormFieldsAreOpenAICompatible() {
        let fields = GroqProvider.shared.transcriptionFormFields(
            model: "whisper-large-v3",
            responseFormat: "verbose_json",
            language: "en",
            includeFillerWords: true,
            keyTerms: ["FreeFlow"]
        )
        let encoded = fields.map { "\($0.name)=\($0.value)" }.joined(separator: " | ")
        expectEqual(encoded, "model=whisper-large-v3 | response_format=verbose_json | language=en")
    }

    private static func testResolveFallsBackToGroq() {
        expectEqual(ProviderRegistry.resolve(id: nil, baseURL: "").id, "groq")
        expectEqual(ProviderRegistry.resolve(id: "missing", baseURL: "https://example.com/v1").id, "groq")
        expectEqual(
            ProviderRegistry.resolve(id: nil, baseURL: "https://api.groq.com/openai/v1").id,
            "groq"
        )
    }

    private static func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        expect(actual == expected, "Expected \(expected), got \(actual)", file: file, line: line)
    }

    private static func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
