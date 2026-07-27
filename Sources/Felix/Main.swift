import AppKit

/// Explicitly bootstrap AppKit instead of relying on the synthesized
/// NSApplicationDelegate.main() entry point. This guarantees that FelixApp is
/// attached before the application run loop starts on macOS 26.
@main
@MainActor
struct FelixMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = FelixApp()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
