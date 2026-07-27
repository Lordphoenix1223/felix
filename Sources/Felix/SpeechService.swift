import AVFoundation
import Speech

final class SpeechService: NSObject {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var listenID = UUID()

    var engineDescription: String {
        guard let recognizer else { return "Apple Speech unavailable" }
        if recognizer.supportsOnDeviceRecognition {
            return "Apple Speech · on-device preferred"
        }
        return "Apple Speech · network fallback"
    }

    func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status == .authorized) }
        }
        let mic = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in continuation.resume(returning: granted) }
        }
        return speech && mic
    }

    func listen(timeout: TimeInterval = 10, onPartial: ((String) -> Void)? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        let currentListenID = UUID()
        listenID = currentListenID
        task?.cancel()
        task = nil
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request, let recognizer else {
            completion(.failure(FelixError.network("Speech recognition is unavailable")))
            return
        }
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        // Do not force the on-device model. `supportsOnDeviceRecognition`
        // describes model capability, not current model readiness; forcing it
        // can produce the misleading "speech recognition unavailable" error
        // even when Apple's network recognizer is usable. Let Speech choose
        // the available engine for this turn.
        request.requiresOnDeviceRecognition = false
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            completion(.failure(FelixError.network("No usable microphone input is available")))
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        audioEngine.prepare()
        do { try audioEngine.start() } catch {
            stop()
            completion(.failure(error))
            return
        }

        var finished = false
        var latestText = ""
        var silenceWork: DispatchWorkItem?
        let finish: (Result<String, Error>) -> Void = { [weak self] result in
            guard let self, self.listenID == currentListenID, !finished else { return }
            finished = true
            silenceWork?.cancel()
            self.stop()
            completion(result)
        }

        task = recognizer.recognitionTask(with: request) { result, error in
            if let error { finish(.failure(error)); return }
            if let result {
                latestText = result.bestTranscription.formattedString
                onPartial?(latestText)
                if result.isFinal { finish(.success(latestText)); return }

                // SFSpeechRecognizer does not reliably emit `isFinal` for a
                // short conversational turn. End the turn after a real pause
                // once we have text, while keeping the hard timeout as a
                // safety net for an open microphone.
                if !latestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    silenceWork?.cancel()
                    let work = DispatchWorkItem { finish(.success(latestText)) }
                    silenceWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            finish(latestText.isEmpty ? .failure(FelixError.cancelled) : .success(latestText))
        }
    }

    func stop() {
        listenID = UUID()
        task?.cancel()
        task = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
    }
}
