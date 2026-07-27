import AppKit

@MainActor
final class FelixPopoverViewController: NSViewController {
    var onTalk: (() -> Void)?
    var onDescribe: (() -> Void)?
    var onFind: (() -> Void)?
    var onGuide: (() -> Void)?
    var onHistory: (() -> Void)?
    var onSelect: (() -> Void)?
    var onConnect: (() -> Void)?
    var onPermissions: (() -> Void)?
    var onForget: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let answerLabel = NSTextField(wrappingLabelWithString: "Hold Option and drag around anything on screen.")

    override func loadView() {
        let root = FelixCardView(frame: NSRect(x: 0, y: 0, width: 340, height: 500))
        let eyebrow = NSTextField(labelWithString: "FELIX")
        eyebrow.font = .systemFont(ofSize: 18, weight: .bold)
        eyebrow.textColor = .labelColor
        let close = NSButton(title: "Close", target: self, action: #selector(closePressed))
        close.bezelStyle = .rounded
        close.controlSize = .small
        close.keyEquivalent = "\u{1b}"
        let header = NSStackView(views: [eyebrow, NSView(), close])
        header.orientation = .horizontal
        header.alignment = .centerY
        let rule = NSBox()
        rule.boxType = .separator
        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = .secondaryLabelColor
        answerLabel.font = .systemFont(ofSize: 14, weight: .regular)
        answerLabel.textColor = .labelColor
        answerLabel.maximumNumberOfLines = 5
        answerLabel.lineBreakMode = .byWordWrapping
        let select = button("Select a region", action: #selector(selectPressed))
        let talk = button("Talk about current screen", action: #selector(talkPressed))
        let describe = button("Describe current screen", action: #selector(describePressed))
        let find = button("Find something on screen", action: #selector(findPressed))
        let guide = button("Show me where to click", action: #selector(guidePressed))
        let history = button("Show recent actions", action: #selector(historyPressed))
        let connect = button("Connect an integration", action: #selector(connectPressed))
        let permissions = button("Open permissions", action: #selector(permissionsPressed))
        let forget = button("Forget local memory", action: #selector(forgetPressed))
        let quit = button("Quit Felix", action: #selector(quitPressed))
        let actions = NSStackView(views: [select, talk, describe, find, guide, history, connect, permissions, forget, quit])
        actions.orientation = .vertical
        actions.alignment = .width
        actions.spacing = 5
        let stack = NSStackView(views: [header, rule, statusLabel, answerLabel, actions])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 11
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            actions.heightAnchor.constraint(equalToConstant: 290)
        ])
        view = root
    }

    func update(status: String, answer: String? = nil) {
        _ = view
        statusLabel.stringValue = status.replacingOccurrences(of: "//", with: "·")
        if let answer { answerLabel.stringValue = answer }
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.alignment = .left
        button.controlSize = .regular
        return button
    }

    @objc private func closePressed() { view.window?.performClose(nil) }
    @objc private func selectPressed() { onSelect?() }
    @objc private func talkPressed() { onTalk?() }
    @objc private func describePressed() { onDescribe?() }
    @objc private func findPressed() { onFind?() }
    @objc private func guidePressed() { onGuide?() }
    @objc private func historyPressed() { onHistory?() }
    @objc private func connectPressed() { onConnect?() }
    @objc private func permissionsPressed() { onPermissions?() }
    @objc private func forgetPressed() { onForget?() }
    @objc private func quitPressed() { onQuit?() }
}

private final class FelixCardView: NSVisualEffectView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.controlBackgroundColor.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
    }
}
