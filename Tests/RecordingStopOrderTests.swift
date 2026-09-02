import Foundation

enum RecordingStopOrderTests {
    static func run() {
        testCaptureStoppedRunsBeforeFileCompletion()
        print("RecordingStopOrderTests passed")
    }

    /// Drives shipped `AudioRecorder.stopRecording` and asserts capture-stop
    /// is delivered before the file-completion callback.
    private static func testCaptureStoppedRunsBeforeFileCompletion() {
        let recorder = AudioRecorder()
        var order: [String] = []
        let lock = NSLock()
        recorder.stopRecording(
            onCaptureStopped: {
                lock.lock()
                order.append("capture")
                lock.unlock()
            },
            completion: { _ in
                lock.lock()
                order.append("file")
                lock.unlock()
            }
        )

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            lock.lock()
            let done = order.count >= 2
            lock.unlock()
            if done { break }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }

        lock.lock()
        let observed = order
        lock.unlock()
        if observed != ["capture", "file"] {
            fatalError("expected [capture, file], got \(observed)")
        }
    }
}
