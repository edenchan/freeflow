import Foundation

/// Streaming speech-to-text session used while the user is still recording.
///
/// OpenAI-compatible providers speak `/v1/realtime`. Other presets may supply
/// a different wire protocol as long as they accept PCM16 chunks and can
/// produce a final transcript on commit.
protocol LiveTranscriptionSession: AnyObject {
    var onPartialUpdate: ((String) -> Void)? { get set }

    func start() throws
    func appendPCM16(_ data: Data)
    func commitAndAwaitFinal() async throws -> String
    func cancel()
}
