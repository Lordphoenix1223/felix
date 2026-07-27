import AppKit
import ApplicationServices
import AVFoundation
import Speech

struct FelixPermissionSnapshot: Sendable {
    let screenRecording: Bool
    let accessibility: Bool
    let microphone: Bool
    let speechRecognition: Bool

    var allGranted: Bool { screenRecording && accessibility && microphone && speechRecognition }

    var missing: [String] {
        var result: [String] = []
        if !screenRecording { result.append("Screen Recording") }
        if !accessibility { result.append("Accessibility") }
        if !microphone { result.append("Microphone") }
        if !speechRecognition { result.append("Speech Recognition") }
        return result
    }
}

@MainActor
final class FelixPermissionCoordinator {
    func snapshot() -> FelixPermissionSnapshot {
        FelixPermissionSnapshot(
            screenRecording: CGPreflightScreenCaptureAccess(),
            accessibility: AXIsProcessTrusted(),
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            speechRecognition: SFSpeechRecognizer.authorizationStatus() == .authorized
        )
    }

    func requestInitialPermissions() async {
        let current = snapshot()
        if !current.screenRecording { _ = CGRequestScreenCaptureAccess() }
        if !current.accessibility {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        if current.microphone == false { _ = await AVCaptureDevice.requestAccess(for: .audio) }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    func openSettings(for permission: String? = nil) {
        let anchor: String
        switch permission {
        case "Screen Recording": anchor = "Privacy_ScreenCapture"
        case "Accessibility": anchor = "Privacy_Accessibility"
        case "Microphone": anchor = "Privacy_Microphone"
        case "Speech Recognition": anchor = "Privacy_SpeechRecognition"
        default: anchor = "Privacy"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    func presentIfNeeded() async {
        await requestInitialPermissions()
        // Permission setup is on-demand. Showing a modal alert at startup made
        // Felix claim Screen Recording was missing even when the TCC row was
        // already enabled, and it blocked the lasso. The popover reports the
        // current snapshot; capture failure provides the actionable settings
        // link only when macOS actually rejects the image request.
    }
}
