import Foundation

enum GrokProviderTests {
    static func run() {
        testGrokMatchesXAIHost()
        testGrokBatchURLUsesSttPath()
        testGrokBatchURLDoesNotDoubleSttSuffix()
        testGrokFormFieldsOrderAndFormatting()
        testKeyTermsParseDedupeAndCap()
        testStreamingWebSocketURL()
        testGrokModelsArePredefined()
        testGrokCleanupUsesLowReasoning()
        print("GrokProviderTests passed")
    }

    private static func testGrokMatchesXAIHost() {
        let grok = GrokProvider.shared
        expect(grok.matches(baseURL: "https://api.x.ai/v1"), "api.x.ai should match Grok")
        expect(!grok.matches(baseURL: "https://api.groq.com/openai/v1"), "Groq host should not match Grok")
        expectEqual(
            ProviderRegistry.resolve(id: nil, baseURL: "https://api.x.ai/v1").id,
            "xai"
        )
    }

    private static func testGrokBatchURLUsesSttPath() {
        let base = URL(string: "https://api.x.ai/v1")!
        expectEqual(
            GrokProvider.shared.transcriptionURL(from: base).absoluteString,
            "https://api.x.ai/v1/stt"
        )
    }

    private static func testGrokBatchURLDoesNotDoubleSttSuffix() {
        let base = URL(string: "https://api.x.ai/v1/stt")!
        expectEqual(
            GrokProvider.shared.transcriptionURL(from: base).absoluteString,
            "https://api.x.ai/v1/stt"
        )
    }

    private static func testGrokFormFieldsOrderAndFormatting() {
        let fields = GrokProvider.shared.transcriptionFormFields(
            model: "grok-stt",
            responseFormat: "json",
            language: "en",
            includeFillerWords: true,
            keyTerms: ["FreeFlow", "xAI"]
        )
        expectEqual(
            stringifyFields(fields),
            "language=en | format=true | filler_words=true | keyterm=FreeFlow | keyterm=xAI"
        )

        let chinese = GrokProvider.shared.transcriptionFormFields(
            model: "grok-stt",
            responseFormat: "json",
            language: "zh",
            includeFillerWords: false,
            keyTerms: []
        )
        expectEqual(stringifyFields(chinese), "language=zh | filler_words=false")
    }

    private static func testKeyTermsParseDedupeAndCap() {
        let raw = """
        FreeFlow
        freeflow
        Wispr Flow
        \(String(repeating: "a", count: 51))
        valid-term
        """
        let terms = GrokProvider.keyTerms(fromVocabulary: raw)
        expect(terms == ["FreeFlow", "Wispr Flow", "valid-term"], "Unexpected key terms: \(terms)")

        let many = (1...150).map { "term-\($0)" }.joined(separator: "\n")
        let capped = GrokProvider.keyTerms(fromVocabulary: many)
        expect(capped.count == GrokProvider.maxKeyTerms, "Expected \(GrokProvider.maxKeyTerms) terms, got \(capped.count)")
    }

    private static func testStreamingWebSocketURL() {
        let url = GrokProvider.streamingWebSocketURL(
            baseURL: "https://api.x.ai/v1",
            language: "en",
            keyTerms: ["FreeFlow"],
            includeFillerWords: false,
            sampleRate: 24_000
        )
        let string = url?.absoluteString ?? ""
        expect(string.hasPrefix("wss://api.x.ai/v1/stt?"), "Unexpected streaming URL: \(string)")
        expect(string.contains("sample_rate=24000"), "Missing sample_rate: \(string)")
        expect(string.contains("encoding=pcm"), "Missing encoding: \(string)")
        expect(string.contains("interim_results=true"), "Missing interim_results: \(string)")
        expect(string.contains("endpointing=400"), "Missing endpointing: \(string)")
        expect(string.contains("filler_words=false"), "Missing filler_words: \(string)")
        expect(string.contains("language=en"), "Missing language: \(string)")
        expect(string.contains("keyterm=FreeFlow"), "Missing keyterm: \(string)")

        let autoLanguage = GrokProvider.streamingWebSocketURL(
            baseURL: "https://api.x.ai/v1",
            language: "auto",
            keyTerms: [],
            includeFillerWords: false
        )?.absoluteString ?? ""
        expect(!autoLanguage.contains("language=auto"), "must never send language=auto: \(autoLanguage)")
        expectEqual(GrokProvider.languageForAPI("ja"), "ja")
    }

    private static func testGrokModelsArePredefined() {
        expect(ModelConfiguration.llmModels.contains("grok-4.5"), "grok-4.5 missing from LLM picker")
        expect(ModelConfiguration.llmModels.contains("grok-4.3"), "grok-4.3 missing from LLM picker")
        expect(ModelConfiguration.visionModels.contains("grok-4.5"), "grok-4.5 missing from vision picker")
        expect(ModelConfiguration.transcriptionModels.contains("grok-stt"), "grok-stt missing from transcription picker")
    }

    private static func testGrokCleanupUsesLowReasoning() {
        let config = ModelConfiguration.config(for: "grok-4.5")
        expect(config.reasoningEffort == "low", "Grok 4.5 cleanup should use low reasoning")
        expect(config.includeReasoning == nil, "Grok should not send Groq include_reasoning")
    }

    private static func stringifyFields(_ fields: [(name: String, value: String)]) -> String {
        fields.map { "\($0.name)=\($0.value)" }.joined(separator: " | ")
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
