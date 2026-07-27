import Foundation

enum SpeechOutput {
    static var onSpeakingChanged: ((Bool) -> Void)?
    private static var currentTask: Process?
    private static var pendingAudioURL: URL?
    private static var pendingSpeechText: String?
    private(set) static var isSpeaking = false

    /// Voice output is intentionally disabled in this release. The current
    /// product contract is text-only; this also prevents an older Kokoro
    /// configuration from making a fresh build speak unexpectedly.
    static var outputEnabled: Bool {
        false
    }

    static func speak(_ text: String) {
        guard outputEnabled else {
            stop()
            return
        }
        let cleaned = text.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ")
        guard !cleaned.isEmpty else { return }
        stop()
        let task = Process()
        let environment = ProcessInfo.processInfo.environment
        let settings = DotEnv.load()
        let configured: (String) -> String? = { key in settings[key] ?? environment[key] }
        // Keep the default responsive. The Kokoro CLI performs model setup on
        // every invocation on some Macs and can add many seconds before audio
        // starts. Users can opt into it with FELIX_TTS_ENGINE=kokoro, while
        // Apple speech remains the zero-setup low-latency path.
        let localKokoro = localKokoroURL()
        let engine = configured("FELIX_TTS_ENGINE")?.lowercased() ?? "system"
        if let kokoro = localKokoro, (engine == "kokoro" || engine == "neural") {
            task.executableURL = kokoro
            let voice = configured("FELIX_KOKORO_VOICE") ?? "af_heart"
            let speed = configured("FELIX_KOKORO_SPEED") ?? "1.0"
            // Generate a local WAV, then play it with afplay. Kokoro's own
            // AVAudioPlayerNode path can fail on headless/sandboxed sessions;
            // afplay is the stable macOS playback boundary and is stoppable.
            let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("felix-kokoro-\(UUID().uuidString).wav")
            pendingAudioURL = audioURL
            pendingSpeechText = cleaned
            task.arguments = ["say", "--voice", voice, "--speed", speed, "--output", audioURL.path, cleaned]
        } else {
            pendingSpeechText = nil
            task.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            // Keep the Apple voice as a reliable fallback for older Macs or
            // machines that have not installed the free neural backend.
            let voice = configured("FELIX_VOICE") ?? "Samantha"
            let rate = configured("FELIX_SPEECH_RATE") ?? "170"
            task.arguments = ["-v", voice, "-r", rate, cleaned]
        }
        task.terminationHandler = { finished in
            DispatchQueue.main.async {
                guard currentTask?.processIdentifier == finished.processIdentifier else { return }
                if let audioURL = pendingAudioURL, finished.terminationStatus == 0 {
                    pendingAudioURL = nil
                    let player = Process()
                    player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                    player.arguments = [audioURL.path]
                    player.terminationHandler = { played in
                        try? FileManager.default.removeItem(at: audioURL)
                        DispatchQueue.main.async {
                            guard currentTask?.processIdentifier == played.processIdentifier else { return }
                            currentTask = nil
                            isSpeaking = false
                            onSpeakingChanged?(false)
                        }
                    }
                    do {
                        try player.run()
                        currentTask = player
                    } catch {
                        try? FileManager.default.removeItem(at: audioURL)
                        currentTask = nil
                        isSpeaking = false
                        onSpeakingChanged?(false)
                    }
                } else {
                    if let audioURL = pendingAudioURL { try? FileManager.default.removeItem(at: audioURL) }
                    let fallback = pendingSpeechText
                    pendingAudioURL = nil
                    pendingSpeechText = nil
                    currentTask = nil
                    isSpeaking = false
                    onSpeakingChanged?(false)
                    if let fallback, finished.terminationStatus != 0 {
                        launchSystemSpeech(fallback)
                    }
                }
            }
        }
        currentTask = task
        do {
            try task.run()
            isSpeaking = true
            onSpeakingChanged?(true)
        } catch {
            currentTask = nil
            isSpeaking = false
            onSpeakingChanged?(false)
        }
    }

    static func stop() {
        currentTask?.terminate()
        currentTask = nil
        if let audioURL = pendingAudioURL {
            try? FileManager.default.removeItem(at: audioURL)
            pendingAudioURL = nil
        }
        pendingSpeechText = nil
        isSpeaking = false
        onSpeakingChanged?(false)
    }

    private static func launchSystemSpeech(_ text: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        let environment = ProcessInfo.processInfo.environment
        let settings = DotEnv.load()
        let voice = settings["FELIX_VOICE"] ?? environment["FELIX_VOICE"] ?? "Samantha"
        let rate = settings["FELIX_SPEECH_RATE"] ?? environment["FELIX_SPEECH_RATE"] ?? "180"
        task.arguments = ["-v", voice, "-r", rate, text]
        task.terminationHandler = { finished in
            DispatchQueue.main.async {
                guard currentTask?.processIdentifier == finished.processIdentifier else { return }
                currentTask = nil
                isSpeaking = false
                onSpeakingChanged?(false)
            }
        }
        do {
            try task.run()
            currentTask = task
            isSpeaking = true
            onSpeakingChanged?(true)
        } catch {
            currentTask = nil
            isSpeaking = false
            onSpeakingChanged?(false)
        }
    }

    private static func localKokoroURL() -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var candidates: [URL] = []
        if let explicit = ProcessInfo.processInfo.environment["FELIX_KOKORO_PATH"], !explicit.isEmpty {
            candidates.append(URL(fileURLWithPath: explicit))
        }
        candidates += [
            home.appendingPathComponent(".felix/bin/kokoro"),
            URL(fileURLWithPath: "/opt/homebrew/bin/kokoro"),
            URL(fileURLWithPath: "/usr/local/bin/kokoro")
        ]
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) })
    }
}
