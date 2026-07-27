import AppKit

final class SelectionOverlayController: NSObject {
    private var windows: [NSWindow] = []
    private var completion: ((NSRect, NSScreen) -> Void)?
    private var cancellation: (() -> Void)?

    func begin(initialPoint: NSPoint? = nil, completion: @escaping (NSRect, NSScreen) -> Void, cancellation: (() -> Void)? = nil) {
        guard windows.isEmpty, !NSScreen.screens.isEmpty else { return }
        self.completion = completion
        self.cancellation = cancellation
        let selectedScreen = initialPoint.flatMap { point in
            NSScreen.screens.first { $0.frame.contains(point) }
        }
        for screen in NSScreen.screens {
            let localStart: NSPoint?
            if let initialPoint, selectedScreen == screen {
                localStart = NSPoint(
                    x: initialPoint.x - screen.frame.origin.x,
                    y: initialPoint.y - screen.frame.origin.y
                )
            } else {
                localStart = nil
            }
            // Do not use NSWindow's `screen:` convenience initializer here.
            // On macOS 26 it can abort with EXC_BREAKPOINT for a borderless
            // screen-sized window (the crash report points directly at that
            // initializer). Create the window with the designated initializer
            // and place it explicitly in global screen coordinates instead.
            let overlay = SelectionOverlayWindow(contentRect: screen.frame, initialPoint: localStart) { [weak self] rect in
                self?.finish(rect: rect, screen: screen)
            } cancel: { [weak self] in
                self?.cancel()
            }
            windows.append(overlay)
            overlay.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    private func finish(rect: NSRect, screen: NSScreen) {
        let callback = completion
        closeWindows()
        completion = nil
        cancellation = nil
        callback?(rect, screen)
    }

    private func cancel() {
        let callback = cancellation
        closeWindows()
        completion = nil
        cancellation = nil
        callback?()
    }

    private func closeWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

private final class SelectionOverlayWindow: NSWindow {
    private let onSelect: (NSRect) -> Void
    private let onCancel: () -> Void

    init(contentRect: NSRect, initialPoint: NSPoint?, onSelect: @escaping (NSRect) -> Void, cancel: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onCancel = cancel
        super.init(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(contentRect, display: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        contentView = SelectionOverlayView(frame: NSRect(origin: .zero, size: contentRect.size), initialPoint: initialPoint, onSelect: onSelect, onCancel: cancel)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionOverlayView: NSView {
    private let onSelect: (NSRect) -> Void
    private let onCancel: () -> Void
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var selectionRect: NSRect?
    private var isMoving = false
    private var moveOffset = NSPoint.zero
    private var hasStartedDrag = false
    private var autoCommit: DispatchWorkItem?

    init(frame: NSRect, initialPoint: NSPoint?, onSelect: @escaping (NSRect) -> Void, onCancel: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onCancel = onCancel
        super.init(frame: frame)
        if let initialPoint {
            startPoint = initialPoint
            currentPoint = initialPoint
            // Option-drag begins in the other app before the overlay exists;
            // the preserved initial point is that drag's mouse-down.
            hasStartedDrag = true
        }
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let rect = selectionRect ?? pendingRect else {
            drawInstruction()
            return
        }
        NSColor.systemBlue.withAlphaComponent(0.18).setFill()
        let box = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        box.fill()
        NSColor.systemBlue.setStroke()
        box.lineWidth = 2
        box.stroke()

        NSColor.systemRed.setStroke()
        let laser = NSBezierPath()
        let cursor = currentPoint ?? NSPoint(x: rect.midX, y: rect.midY)
        laser.move(to: NSPoint(x: cursor.x, y: 0))
        laser.line(to: NSPoint(x: cursor.x, y: bounds.height))
        laser.move(to: NSPoint(x: 0, y: cursor.y))
        laser.line(to: NSPoint(x: bounds.width, y: cursor.y))
        laser.lineWidth = 1
        laser.stroke()

        let prompt = NSString(string: selectionRect == nil
            ? "Release to set rectangle • drag inside to move • Return to ask Felix"
            : "Drag inside to move • Return or double-click to ask Felix • Esc to cancel")
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]
        let size = prompt.size(withAttributes: attributes)
        let labelRect = NSRect(x: (bounds.width - size.width) / 2, y: bounds.height - 74, width: size.width, height: size.height)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: labelRect.insetBy(dx: -14, dy: -8), xRadius: 10, yRadius: 10).fill()
        prompt.draw(in: labelRect, withAttributes: attributes)
    }

    private var pendingRect: NSRect? {
        guard let startPoint, let currentPoint else { return nil }
        return normalizedRect(from: startPoint, to: currentPoint)
    }

    private func drawInstruction() {
        let text = NSString(string: "Drag a rectangle around something • Return to ask Felix • Esc to cancel")
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        let rect = NSRect(x: (bounds.width - size.width) / 2, y: bounds.height - 80, width: size.width, height: size.height)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: -18, dy: -10), xRadius: 12, yRadius: 12).fill()
        text.draw(in: rect, withAttributes: attributes)
    }

    override func mouseUp(with event: NSEvent) {
        // Keep the selected rectangle alive so it can be moved or resized by
        // starting another drag. Commit explicitly with Return/double-click.
        guard hasStartedDrag else { NSCursor.crosshair.set(); return }
        hasStartedDrag = false
        let point = convert(event.locationInWindow, from: nil)
        currentPoint = point
        if isMoving {
            isMoving = false
            scheduleAutoCommit()
        }
        else if let rect = pendingRect, rect.width > 12, rect.height > 12 {
            selectionRect = clampedRect(rect)
            startPoint = nil
            currentPoint = NSPoint(x: selectionRect!.midX, y: selectionRect!.midY)
            scheduleAutoCommit()
        } else { onCancel() }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        hasStartedDrag = true
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount >= 2, selectionRect != nil {
            commitSelection()
            return
        }
        if let rect = selectionRect, rect.insetBy(dx: -10, dy: -10).contains(point) {
            autoCommit?.cancel()
            isMoving = true
            moveOffset = NSPoint(x: point.x - rect.origin.x, y: point.y - rect.origin.y)
            currentPoint = point
        } else {
            autoCommit?.cancel()
            isMoving = false
            selectionRect = nil
            startPoint = point
            currentPoint = point
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentPoint = point
        if isMoving, let rect = selectionRect {
            selectionRect = clampedRect(NSRect(x: point.x - moveOffset.x, y: point.y - moveOffset.y, width: rect.width, height: rect.height))
        }
        needsDisplay = true
    }

    private func normalizedRect(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func clampedRect(_ rect: NSRect) -> NSRect {
        var result = rect
        result.origin.x = min(max(0, result.origin.x), max(0, bounds.width - result.width))
        result.origin.y = min(max(0, result.origin.y), max(0, bounds.height - result.height))
        return result
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76, selectionRect != nil {
            commitSelection()
        } else if event.keyCode == 53 {
            autoCommit?.cancel()
            hasStartedDrag = false
            onCancel()
        }
    }

    private func scheduleAutoCommit() {
        autoCommit?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commitSelection() }
        autoCommit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func commitSelection() {
        guard let selectionRect, selectionRect.width > 12, selectionRect.height > 12 else { return }
        autoCommit?.cancel()
        autoCommit = nil
        onSelect(selectionRect)
    }
}
