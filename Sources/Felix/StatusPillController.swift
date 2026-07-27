import AppKit

private final class FelixPillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class StatusPillController: NSObject {
    private var panel: NSPanel?
    private let title = NSTextField(labelWithString: "Felix")
    private let dots = NSTextField(labelWithString: "•••")
    private var timer: Timer?
    private var transcript = ""

    func update(status: String, transcript: String? = nil) {
        if let transcript { self.transcript = String(transcript.prefix(72)) }
        let normalized = status.uppercased()
        if transcript == nil && !normalized.contains("LISTENING") { self.transcript = "" }
        let state: (String, NSColor)? = normalized.contains("LISTENING") ? ("Listening", .systemOrange) :
            normalized.contains("THINKING") ? ("Thinking", .systemPurple) :
            normalized.contains("SPEAKING") ? ("Speaking", .systemTeal) :
            normalized.contains("ERROR") ? ("Needs attention", .systemRed) : nil
        guard let state else { hide(); return }
        ensurePanel(color: state.1)
        title.stringValue = self.transcript.isEmpty ? state.0 : "\(state.0)  \(self.transcript)"
        panel?.orderFrontRegardless()
    }

    func hide() {
        transcript = ""
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
    }

    private func ensurePanel(color: NSColor) {
        if panel == nil {
            let card = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 230, height: 30))
            card.material = .hudWindow
            card.blendingMode = .behindWindow
            card.state = .active
            card.wantsLayer = true
            card.layer?.cornerRadius = 15
            card.layer?.borderWidth = 1
            card.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
            title.font = .systemFont(ofSize: 12, weight: .semibold)
            title.textColor = .labelColor
            title.lineBreakMode = .byTruncatingTail
            dots.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
            dots.alignment = .center
            let stack = NSStackView(views: [title, NSView(), dots])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.edgeInsets = NSEdgeInsets(top: 5, left: 12, bottom: 5, right: 10)
            card.addSubview(stack)
            stack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: card.leadingAnchor), stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                stack.topAnchor.constraint(equalTo: card.topAnchor), stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
            ])
            let next = FelixPillPanel(contentRect: card.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            next.isOpaque = false
            next.backgroundColor = .clear
            next.hasShadow = true
            next.level = .statusBar
            next.ignoresMouseEvents = false
            next.isMovableByWindowBackground = true
            next.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            next.contentView = card
            next.delegate = self
            panel = next
        }
        if let panel {
            if let savedX = UserDefaults.standard.object(forKey: "Felix.statusPill.x") as? NSNumber,
               let savedY = UserDefaults.standard.object(forKey: "Felix.statusPill.y") as? NSNumber {
                panel.setFrameOrigin(NSPoint(x: savedX.doubleValue, y: savedY.doubleValue))
            } else {
                let screen = NSScreen.main ?? NSScreen.screens.first
                if let screen { panel.setFrameOrigin(NSPoint(x: screen.frame.midX - panel.frame.width / 2, y: screen.frame.maxY - panel.frame.height - 8)) }
            }
        }
        dots.textColor = color
        timer?.invalidate()
        var phase = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: true) { [weak self] _ in
            guard let self else { return }
            let frames = ["•  ·  ·", "·  •  ·", "·  ·  •", "·  •  ·"]
            self.dots.stringValue = frames[phase % frames.count]
            phase += 1
        }
    }
}

extension StatusPillController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        UserDefaults.standard.set(panel.frame.origin.x, forKey: "Felix.statusPill.x")
        UserDefaults.standard.set(panel.frame.origin.y, forKey: "Felix.statusPill.y")
    }
}
