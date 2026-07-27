import AppKit

@MainActor
final class PointerOverlayController: NSObject {
    private var selectionPanel: NSPanel?
    private var targetPanel: NSPanel?
    private var selectionTimer: Timer?
    private var targetTimer: Timer?
    // Every visual request gets a generation. A cancelled timer can still have
    // one queued run-loop callback, so invalidating the timer alone is not
    // enough to prevent an old box from being drawn again.
    private var generation: UInt64 = 0

    private func clearSelection() {
        selectionTimer?.invalidate()
        selectionTimer = nil
        selectionPanel?.orderOut(nil)
        selectionPanel = nil
    }

    private func clearTarget() {
        targetTimer?.invalidate()
        targetTimer = nil
        targetPanel?.orderOut(nil)
        targetPanel = nil
    }

    private func clearAll() {
        generation &+= 1
        clearSelection()
        clearTarget()
    }

    func point(at rect: NSRect, on screen: NSScreen, duration: TimeInterval = 2.4) {
        // Selection and answer targets are mutually exclusive. Never leave
        // the locked selection rectangle underneath the final target box.
        clearAll()
        let requestGeneration = generation
        let frame = NSRect(x: rect.minX - 18, y: rect.minY - 18, width: rect.width + 36, height: rect.height + 36)
        let next = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        next.isOpaque = false
        next.backgroundColor = .clear
        next.hasShadow = false
        next.ignoresMouseEvents = true
        next.level = .screenSaver
        next.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        next.contentView = PointerOverlayView(frame: NSRect(origin: .zero, size: frame.size), label: nil)
        selectionPanel = next
        next.orderFrontRegardless()

        let selectionDeadline = Date().addingTimeInterval(duration)
        selectionTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self, weak next] timer in
            Task { @MainActor [weak self, weak next] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                guard requestGeneration == self.generation else {
                    timer.invalidate()
                    return
                }
                guard let view = next?.contentView as? PointerOverlayView else { return }
                view.phase += 1
                view.needsDisplay = true
                guard Date() >= selectionDeadline else { return }
                timer.invalidate()
                next?.orderOut(nil)
                if self.selectionPanel === next { self.selectionPanel = nil }
                self.selectionTimer = nil
            }
        }
    }

    func point(at globalPoint: NSPoint, label: String, style: String = "target", on screen: NSScreen, duration: TimeInterval = 8.5) {
        // A new target replaces every previous visual marker, including the
        // selection rectangle. This guarantees one visible target at a time.
        clearAll()
        let requestGeneration = generation
        let size: CGFloat = 120
        let frame = NSRect(x: globalPoint.x - size / 2, y: globalPoint.y - size / 2, width: size, height: size)
        let next = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        next.isOpaque = false
        next.backgroundColor = .clear
        next.hasShadow = false
        next.ignoresMouseEvents = true
        next.level = .screenSaver
        next.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        next.contentView = PointerOverlayView(frame: NSRect(origin: .zero, size: frame.size), label: label, style: style)
        targetPanel = next
        next.orderFrontRegardless()
        let start = NSEvent.mouseLocation
        let animationStart = Date()
        let animationDuration = 0.55
        let targetDeadline = Date().addingTimeInterval(duration)
        targetTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak next] timer in
            Task { @MainActor [weak self, weak next] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                guard requestGeneration == self.generation else {
                    timer.invalidate()
                    return
                }
                guard let view = next?.contentView as? PointerOverlayView else { return }
                let elapsed = Date().timeIntervalSince(animationStart)
                let progress = min(1.0, max(0.0, elapsed / animationDuration))
                let eased = 1.0 - pow(1.0 - progress, 3.0)
                let x = start.x + (globalPoint.x - start.x) * eased
                let y = start.y + (globalPoint.y - start.y) * eased
                next?.setFrameOrigin(NSPoint(x: x - size / 2, y: y - size / 2))
                view.phase += 1
                view.needsDisplay = true
                guard Date() >= targetDeadline else { return }
                timer.invalidate()
                next?.orderOut(nil)
                if self.targetPanel === next { self.targetPanel = nil }
                self.targetTimer = nil
            }
        }
    }

    func hide() {
        clearAll()
    }
}

private final class PointerOverlayView: NSView {
    var phase = 0
    private let label: String?
    private let style: String

    init(frame: NSRect, label: String?, style: String = "target") {
        self.label = label
        self.style = style
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let inset = 16.0
        let target = bounds.insetBy(dx: inset, dy: inset)
        let accent = style == "laser" ? NSColor.systemRed : NSColor.systemTeal
        let pulse = CGFloat(phase % 10) * 0.7
        let ring = target.insetBy(dx: -pulse, dy: -pulse)
        accent.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: ring, xRadius: 10, yRadius: 10).fill()
        accent.setStroke()
        let path = NSBezierPath(roundedRect: ring, xRadius: 10, yRadius: 10)
        path.lineWidth = 3
        path.stroke()
        let arrow = NSBezierPath()
        let point = NSPoint(x: bounds.midX, y: bounds.maxY - 4)
        arrow.move(to: point)
        arrow.line(to: NSPoint(x: point.x - 8, y: point.y - 18))
        arrow.line(to: NSPoint(x: point.x + 8, y: point.y - 18))
        arrow.close()
        accent.setFill()
        arrow.fill()
        if let label, !label.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let text = NSString(string: label)
            let size = text.size(withAttributes: attributes)
            let labelRect = NSRect(x: bounds.midX - size.width / 2 - 10, y: 2, width: size.width + 20, height: 22)
            NSColor.black.withAlphaComponent(0.82).setFill()
            NSBezierPath(roundedRect: labelRect, xRadius: 8, yRadius: 8).fill()
            text.draw(in: labelRect.insetBy(dx: 10, dy: 3), withAttributes: attributes)
        }
    }
}
