import AppKit

@MainActor
final class ResponsePanelController: NSObject {
    var onClose: (() -> Void)?
    var onStop: (() -> Void)?
    var onReplay: (() -> Void)?
    private var panel: NSPanel?
    private let titleLabel = NSTextField(labelWithString: "Felix")
    private let statusDot = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
    private let bodyView = NSTextView(frame: .zero)
    private let closeButton = NSButton(title: "×", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let replayButton = NSButton(title: "Replay", target: nil, action: nil)
    private let targetLabel = NSTextField(labelWithString: "SCREEN TARGET LOCKED")
    private let listeningIndicator = NSTextField(labelWithString: "•••")
    private var listeningTimer: Timer?

    func showListening(partial: String = "", targetLocked: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.ensurePanel()
            self.titleLabel.stringValue = "Listening"
            self.bodyView.string = partial.isEmpty ? "I'm listening…" : "\"\(partial)\""
            self.targetLabel.isHidden = !targetLocked
            self.statusDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
            self.listeningIndicator.isHidden = false
            self.stopButton.title = "Cancel"
            self.stopButton.isHidden = false
            self.positionPanel()
            self.panel?.orderFrontRegardless()
            self.listeningTimer?.invalidate()
            var phase = 0
            self.listeningTimer = Timer.scheduledTimer(withTimeInterval: 0.24, repeats: true) { [weak self] _ in
                guard let self else { return }
                let frames = ["•  ·  ·", "·  •  ·", "·  ·  •", "·  •  ·"]
                self.listeningIndicator.stringValue = frames[phase % frames.count]
                phase += 1
            }
        }
    }

    func show(_ text: String, title: String = "Felix") {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.listeningTimer?.invalidate()
            self.listeningTimer = nil
            self.ensurePanel()
            self.titleLabel.stringValue = title
            self.bodyView.string = Self.clean(text)
            // The target chip is meaningful for a region turn; quick screen
            // questions intentionally have no locked rectangle.
            self.replayButton.isHidden = !SpeechOutput.outputEnabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            self.listeningIndicator.isHidden = true
            self.stopButton.title = "Stop"
            self.stopButton.isHidden = false
            self.statusDot.layer?.backgroundColor = title.lowercased().contains("error") ? NSColor.systemRed.cgColor : NSColor.systemTeal.cgColor
            self.positionPanel()
            self.panel?.orderFrontRegardless()
        }
    }

    func showThinking(targetLocked: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.listeningTimer?.invalidate()
            self.listeningTimer = nil
            self.ensurePanel()
            self.titleLabel.stringValue = "Thinking"
            self.bodyView.string = "I heard you. I’m checking the selected screen…"
            self.targetLabel.isHidden = !targetLocked
            self.listeningIndicator.isHidden = true
            self.replayButton.isHidden = true
            self.stopButton.title = "Stop"
            self.stopButton.isHidden = false
            self.statusDot.layer?.backgroundColor = NSColor.systemPurple.cgColor
            self.positionPanel()
            self.panel?.orderFrontRegardless()
        }
    }

    func close() {
        listeningTimer?.invalidate()
        listeningTimer = nil
        onClose?()
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.layer?.backgroundColor = NSColor.systemTeal.cgColor
        bodyView.isEditable = false
        bodyView.isSelectable = true
        bodyView.drawsBackground = false
        bodyView.textContainerInset = NSSize(width: 0, height: 2)
        bodyView.font = .systemFont(ofSize: 16, weight: .regular)
        bodyView.textColor = .labelColor
        bodyView.isVerticallyResizable = true
        bodyView.isHorizontallyResizable = false
        bodyView.textContainer?.widthTracksTextView = true
        bodyView.textContainer?.lineFragmentPadding = 0

        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 22, weight: .regular)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "Close Felix"
        closeButton.target = self
        closeButton.action = #selector(closePressed)

        stopButton.bezelStyle = .rounded
        stopButton.controlSize = .small
        stopButton.font = .systemFont(ofSize: 11, weight: .semibold)
        stopButton.target = self
        stopButton.action = #selector(stopPressed)
        stopButton.isHidden = true

        replayButton.bezelStyle = .rounded
        replayButton.controlSize = .small
        replayButton.font = .systemFont(ofSize: 11, weight: .semibold)
        replayButton.target = self
        replayButton.action = #selector(replayPressed)
        replayButton.isHidden = true

        targetLabel.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        targetLabel.textColor = .secondaryLabelColor
        targetLabel.isHidden = true

        listeningIndicator.font = .monospacedSystemFont(ofSize: 16, weight: .semibold)
        listeningIndicator.textColor = .systemOrange
        listeningIndicator.alignment = .center
        listeningIndicator.isHidden = true

        let heading = NSStackView(views: [statusDot, titleLabel, NSView(), replayButton, stopButton, closeButton])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 8
        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 16
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        let stack = NSStackView(views: [heading, targetLabel, listeningIndicator, bodyView])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 14, right: 14)
        card.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor), stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor), stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            card.widthAnchor.constraint(equalToConstant: 420), bodyView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            bodyView.heightAnchor.constraint(lessThanOrEqualToConstant: 190), closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24), statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8), stopButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
            replayButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])
        let next = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 118), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        next.isOpaque = false
        next.backgroundColor = .clear
        next.hasShadow = true
        next.level = .floating
        next.hidesOnDeactivate = false
        next.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        next.contentView = card
        next.delegate = self
        panel = next
    }

    private func positionPanel() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let screen else { return }
        let margin: CGFloat = 18
        var x = mouse.x + 18
        var y = mouse.y - panel.frame.height - 18
        if x + panel.frame.width > screen.visibleFrame.maxX - margin { x = mouse.x - panel.frame.width - 18 }
        if y < screen.visibleFrame.minY + margin { y = mouse.y + 24 }
        x = min(max(x, screen.visibleFrame.minX + margin), screen.visibleFrame.maxX - panel.frame.width - margin)
        y = min(max(y, screen.visibleFrame.minY + margin), screen.visibleFrame.maxY - panel.frame.height - margin)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func closePressed() { close() }
    @objc private func stopPressed() { onStop?() }
    @objc private func replayPressed() { onReplay?() }

    private static func clean(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.first == "{", let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return text }
        if let detail = json["detail"] as? String, !detail.isEmpty { return detail }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let message = json["message"] as? String { return message }
        return "Felix received an unexpected provider response. Check the NVIDIA model and API key, then try again."
    }
}

extension ResponsePanelController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}
