import Foundation
import os.log

private let grokRealtimeLog = OSLog(subsystem: "com.zachlatta.freeflow", category: "GrokRealtimeTranscription")

/// xAI Grok STT streaming client (`wss://api.x.ai/v1/stt`).
///
/// Protocol differs from OpenAI Realtime: configuration is query params,
/// audio is raw binary PCM frames, and the server emits `transcript.*` events.
final class GrokRealtimeTranscriptionService: LiveTranscriptionSession {
    struct Configuration {
        let baseURL: String
        let apiKey: String
        let language: String?
        let keyTerms: [String]
        let includeFillerWords: Bool
        let sampleRate: Int

        init(
            baseURL: String,
            apiKey: String,
            language: String?,
            keyTerms: [String] = [],
            includeFillerWords: Bool = false,
            sampleRate: Int = GrokProvider.streamingSampleRate
        ) {
            self.baseURL = baseURL
            self.apiKey = apiKey
            self.language = language
            self.keyTerms = keyTerms
            self.includeFillerWords = includeFillerWords
            self.sampleRate = sampleRate
        }
    }

    private let config: Configuration
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    private let stateQueue = DispatchQueue(label: "com.zachlatta.freeflow.grok.realtime.state")
    private var isReady = false
    private var pendingChunks: [Data] = []
    private var outbound: [URLSessionWebSocketTask.Message] = []
    private var sending = false
    private var commitSent = false
    private var closed = false
    private var terminalError: Error?
    private var finalizedParts: [String] = []
    private var currentInterim = ""
    private var doneText: String?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var finalContinuation: CheckedContinuation<String, Error>?

    var onPartialUpdate: ((String) -> Void)?

    init(config: Configuration, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func start() throws {
        guard let wsURL = GrokProvider.streamingWebSocketURL(
            baseURL: config.baseURL,
            language: config.language,
            keyTerms: config.keyTerms,
            includeFillerWords: config.includeFillerWords,
            sampleRate: config.sampleRate
        ) else {
            throw RealtimeTranscriptionError.invalidBaseURL(config.baseURL)
        }

        var request = URLRequest(url: wsURL)
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let task = session.webSocketTask(with: request)
        stateQueue.sync {
            self.task = task
        }
        task.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func cancel() {
        var readyCont: CheckedContinuation<Void, Error>?
        var finalCont: CheckedContinuation<String, Error>?
        let currentTask: URLSessionWebSocketTask? = stateQueue.sync {
            let currentTask = task
            task = nil
            outbound = []
            sending = false
            guard !closed else { return currentTask }
            closed = true
            readyCont = readyContinuation
            readyContinuation = nil
            finalCont = finalContinuation
            finalContinuation = nil
            return currentTask
        }
        readyCont?.resume(throwing: CancellationError())
        finalCont?.resume(throwing: CancellationError())
        receiveTask?.cancel()
        currentTask?.cancel(with: .normalClosure, reason: nil)
    }

    func appendPCM16(_ data: Data) {
        guard !data.isEmpty else { return }
        stateQueue.sync {
            guard !closed, !commitSent else { return }
            if isReady {
                enqueueLocked(.data(data))
            } else {
                if pendingChunks.count == 1024 { pendingChunks.removeFirst() }
                pendingChunks.append(data)
            }
        }
    }

    func commitAndAwaitFinal() async throws -> String {
        try await waitUntilReady(timeout: 8)

        let connected: Bool = stateQueue.sync {
            guard task != nil, !closed else { return false }
            let leftover = pendingChunks
            pendingChunks = []
            commitSent = true
            for chunk in leftover {
                enqueueLocked(.data(chunk))
            }
            enqueueLocked(.string(#"{"type":"audio.done"}"#))
            return true
        }
        guard connected else {
            throw RealtimeTranscriptionError.notConnected
        }

        do {
            return try await awaitFinal(timeout: Self.finalTimeout)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let assembled = stateQueue.sync { assembledTranscript() }
            cancel()
            if let assembled, !assembled.isEmpty {
                return assembled
            }
            throw error
        }
    }

    // MARK: - Receive

    private func receiveLoop() async {
        while !Task.isCancelled {
            let currentTask: URLSessionWebSocketTask? = stateQueue.sync {
                task
            }
            guard let currentTask else { break }
            do {
                let message = try await currentTask.receive()
                switch message {
                case .string(let text):
                    handleServerEvent(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleServerEvent(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                finishWithClose()
                return
            }
        }
        finishWithClose()
    }

    private func finishWithClose() {
        var readyCont: CheckedContinuation<Void, Error>?
        var readyError: Error = RealtimeTranscriptionError.closedBeforeFinal
        var finalResult: (CheckedContinuation<String, Error>, Result<String, Error>)?
        stateQueue.sync {
            guard !closed else { return }
            closed = true
            outbound = []
            sending = false
            readyError = terminalError ?? RealtimeTranscriptionError.closedBeforeFinal
            readyCont = readyContinuation
            readyContinuation = nil
            if let finalContinuation {
                self.finalContinuation = nil
                if let doneText {
                    finalResult = (finalContinuation, .success(doneText))
                } else if let assembled = assembledTranscript(), !assembled.isEmpty {
                    finalResult = (finalContinuation, .success(assembled))
                } else {
                    finalResult = (finalContinuation, .failure(readyError))
                }
            }
        }
        readyCont?.resume(throwing: readyError)
        if let (cont, result) = finalResult {
            cont.resume(with: result)
        }
    }

    private func handleServerEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = json["type"] as? String else {
            return
        }

        switch eventType {
        case "transcript.created":
            markReadyAndFlush()
        case "transcript.partial":
            applyPartial(json)
        case "transcript.done":
            applyDone(json)
        case "error":
            let message = (json["message"] as? String)
                ?? (json["error"] as? [String: Any])?["message"] as? String
                ?? "unknown grok realtime error"
            os_log(.error, log: grokRealtimeLog, "server error: %{public}@", message)
            fail(RealtimeTranscriptionError.serverError(code: "error", message: message))
        default:
            break
        }
    }

    private func markReadyAndFlush() {
        var readyCont: CheckedContinuation<Void, Error>?
        stateQueue.sync {
            isReady = true
            readyCont = readyContinuation
            readyContinuation = nil
            guard !pendingChunks.isEmpty, !commitSent else { return }
            for chunk in pendingChunks {
                enqueueLocked(.data(chunk))
            }
            pendingChunks = []
        }
        readyCont?.resume()
    }

    private func applyPartial(_ json: [String: Any]) {
        let text = (json["text"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let isFinal = boolValue(json["is_final"])
        let speechFinal = boolValue(json["speech_final"])

        let snapshot: String = stateQueue.sync {
            if speechFinal {
                if !text.isEmpty {
                    finalizedParts = [text]
                }
                currentInterim = ""
            } else if isFinal {
                if !text.isEmpty {
                    finalizedParts.append(text)
                }
                currentInterim = ""
            } else {
                currentInterim = text
            }
            return assembledTranscript() ?? ""
        }
        if !snapshot.isEmpty {
            reportPartial(snapshot)
        }
    }

    private func applyDone(_ json: [String: Any]) {
        let text = (json["text"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var pendingResume: (CheckedContinuation<String, Error>, String)?
        var currentTask: URLSessionWebSocketTask?
        stateQueue.sync {
            doneText = text.isEmpty ? (assembledTranscript() ?? "") : text
            closed = true
            outbound = []
            sending = false
            currentTask = task
            if let finalContinuation {
                self.finalContinuation = nil
                pendingResume = (finalContinuation, doneText ?? "")
            }
        }
        currentTask?.cancel(with: .normalClosure, reason: nil)
        if let (cont, result) = pendingResume {
            cont.resume(returning: result)
        }
    }

    private func assembledTranscript() -> String? {
        var parts = finalizedParts
        let interim = currentInterim.trimmingCharacters(in: .whitespacesAndNewlines)
        if !interim.isEmpty {
            parts.append(interim)
        }
        let joined = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    private func waitUntilReady(timeout: TimeInterval) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.waitUntilReadyUnbounded()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw RealtimeTranscriptionError.serverError(
                    code: "timeout",
                    message: "Timed out waiting for Grok STT stream to become ready"
                )
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func waitUntilReadyUnbounded() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let immediate: Result<Void, Error>? = stateQueue.sync {
                if let terminalError {
                    return .failure(terminalError)
                }
                if closed {
                    return .failure(RealtimeTranscriptionError.closedBeforeFinal)
                }
                if isReady {
                    return .success(())
                }
                readyContinuation = continuation
                return nil
            }
            if let immediate {
                continuation.resume(with: immediate)
            }
        }
    }

    private func fail(_ error: Error) {
        var readyCont: CheckedContinuation<Void, Error>?
        var finalCont: CheckedContinuation<String, Error>?
        var currentTask: URLSessionWebSocketTask?
        stateQueue.sync {
            terminalError = error
            closed = true
            outbound = []
            sending = false
            currentTask = task
            readyCont = readyContinuation
            readyContinuation = nil
            finalCont = finalContinuation
            finalContinuation = nil
        }
        currentTask?.cancel(with: .normalClosure, reason: nil)
        readyCont?.resume(throwing: error)
        finalCont?.resume(throwing: error)
    }

    private func reportPartial(_ text: String) {
        guard let handler = onPartialUpdate else { return }
        DispatchQueue.main.async {
            handler(text)
        }
    }

    /// One in-flight WS write, like Grok Build's writer task. Must run on `stateQueue`.
    private func enqueueLocked(_ message: URLSessionWebSocketTask.Message) {
        guard !closed, task != nil else { return }
        outbound.append(message)
        pumpLocked()
    }

    private func pumpLocked() {
        guard !sending, let task, let next = outbound.first else { return }
        outbound.removeFirst()
        sending = true
        task.send(next) { [weak self] error in
            guard let self else { return }
            self.stateQueue.async {
                self.sending = false
                if let error {
                    os_log(.error, log: grokRealtimeLog, "send failed: %{public}@", error.localizedDescription)
                }
                guard !self.closed else { return }
                self.pumpLocked()
            }
        }
    }

    private static var finalTimeout: TimeInterval {
        let override = UserDefaults.standard.double(forKey: "transcription_timeout_seconds")
        return override > 0 ? override : 20
    }

    private func awaitFinal(timeout: TimeInterval) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.awaitFinalUnbounded()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw RealtimeTranscriptionError.serverError(
                    code: "timeout",
                    message: "Timed out waiting for Grok STT final transcript"
                )
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    private func awaitFinalUnbounded() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var immediate: Result<String, Error>?
            var currentTask: URLSessionWebSocketTask?
            stateQueue.sync {
                if let terminalError {
                    immediate = .failure(terminalError)
                    return
                }
                if closed {
                    immediate = doneText.map { .success($0) }
                        ?? .failure(RealtimeTranscriptionError.closedBeforeFinal)
                    return
                }
                if let doneText {
                    closed = true
                    currentTask = task
                    immediate = .success(doneText)
                    return
                }
                finalContinuation = continuation
            }
            if let immediate {
                currentTask?.cancel(with: .normalClosure, reason: nil)
                continuation.resume(with: immediate)
            }
        }
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            return string == "true" || string == "1"
        }
        return false
    }
}
