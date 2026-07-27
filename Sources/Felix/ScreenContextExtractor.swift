import AppKit
import ApplicationServices
import Vision

struct FelixScreenContextExtractor {
    enum ContextMode { case fast, full }

    static func extract(imageJPEG: Data, selection: NSRect, on screen: NSScreen, targetProcessID: pid_t? = nil, mode: ContextMode = .full) -> String {
        var sections: [String] = []
        let appName = targetProcessID.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
        let accessibility = accessibilityContext(selection: selection, on: screen, targetProcessID: targetProcessID, includeDescendants: mode == .full)
        if let appName, !appName.isEmpty { sections.append("Foreground application: \(appName)") }
        if !accessibility.isEmpty { sections.append("Accessible UI context:\n\(accessibility)") }
        let ocr = ocrContext(imageJPEG: imageJPEG, mode: mode)
        if !ocr.isEmpty { sections.append("OCR text in selection:\n\(ocr)") }
        return sections.joined(separator: "\n\n").prefix(12_000).description
    }

    private static func accessibilityContext(selection: NSRect, on screen: NSScreen, targetProcessID: pid_t?, includeDescendants: Bool) -> String {
        guard AXIsProcessTrusted() else { return "" }
        let processID = targetProcessID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let processID, processID > 0 else { return "" }
        let application = AXUIElementCreateApplication(processID)
        var elements: [AXUIElement] = []
        if let rawFocused = attribute(application, kAXFocusedUIElementAttribute) {
            if CFGetTypeID(rawFocused as CFTypeRef) == AXUIElementGetTypeID() {
                elements.append(rawFocused as! AXUIElement)
            }
        }
        if includeDescendants {
            if let rawWindow = attribute(application, kAXFocusedWindowAttribute),
               CFGetTypeID(rawWindow as CFTypeRef) == AXUIElementGetTypeID() {
                elements.append(rawWindow as! AXUIElement)
            }
        }

        let global = AXUIElementCreateSystemWide()
        // SelectionOverlayView reports screen-local coordinates. FelixApp
        // normalizes them to global AppKit coordinates before extraction.
        let point = CGPoint(x: selection.midX, y: screen.frame.maxY - selection.midY)
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(global, Float(point.x), Float(point.y), &hit) == .success, let hit {
            elements.append(hit)
        }

        var seen = Set<String>()
        var lines: [String] = []
        for element in elements {
            var chain: [AXUIElement] = [element]
            var current = element
            for _ in 0..<4 {
                guard let rawParent = attribute(current, kAXParentAttribute),
                      CFGetTypeID(rawParent as CFTypeRef) == AXUIElementGetTypeID() else { break }
                let parent = rawParent as! AXUIElement
                chain.append(parent)
                current = parent
            }
            for element in chain {
                appendCandidate(element, selection: selection, screen: screen, seen: &seen, lines: &lines)
                if includeDescendants { appendChildren(of: element, depth: 0, selection: selection, screen: screen, seen: &seen, lines: &lines) }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func appendChildren(of element: AXUIElement, depth: Int, selection: NSRect, screen: NSScreen, seen: inout Set<String>, lines: inout [String]) {
            // Modern web shells often nest a visible button several layers
            // below the focused window. Three levels was too shallow for
            // ChatGPT/Codex and caused Felix to fall back to fake vision
            // targets. Keep the traversal bounded, but deep enough to find
            // real controls without dumping an entire accessibility tree.
            guard depth < 6, lines.count < 500,
              let rawChildren = attribute(element, kAXChildrenAttribute),
              let children = rawChildren as? [AXUIElement] else { return }
        for child in children {
            appendCandidate(child, selection: selection, screen: screen, seen: &seen, lines: &lines)
            appendChildren(of: child, depth: depth + 1, selection: selection, screen: screen, seen: &seen, lines: &lines)
            if lines.count >= 500 { return }
        }
    }

    private static func appendCandidate(_ element: AXUIElement, selection: NSRect, screen: NSScreen, seen: inout Set<String>, lines: inout [String]) {
        let values: [(String, String)] = [
            ("role", kAXRoleAttribute),
            ("title", kAXTitleAttribute),
            ("description", kAXDescriptionAttribute),
            ("help", kAXHelpAttribute),
            ("identifier", kAXIdentifierAttribute),
            ("value", kAXValueAttribute),
            ("selected", kAXSelectedTextAttribute),
            ("url", kAXURLAttribute)
        ]
        var parts: [String] = []
        for (label, key) in values {
            guard let value = attribute(element, key), let text = printable(value), !text.isEmpty else { continue }
            parts.append("\(label)=\(text.prefix(500))")
        }
        guard !parts.isEmpty else { return }
        if let rect = frame(of: element) {
            let globalRect = NSRect(x: rect.minX, y: screen.frame.origin.y + screen.frame.height - rect.maxY, width: rect.width, height: rect.height)
            guard globalRect.intersects(selection) || selection.contains(NSPoint(x: globalRect.midX, y: globalRect.midY)) else { return }
            let x = Int((((globalRect.midX - selection.minX) / max(selection.width, 1)) * 1000).rounded())
            let y = Int((((globalRect.midY - selection.minY) / max(selection.height, 1)) * 1000).rounded())
            parts.append("center_top_left=(\(min(1000, max(0, x))),\(min(1000, max(0, y))))")
        }
        let line = parts.joined(separator: " | ")
        if seen.insert(line).inserted { lines.append(line) }
    }

    private static func frame(of element: AXUIElement) -> NSRect? {
        guard let rawPosition = attribute(element, kAXPositionAttribute),
              let rawSize = attribute(element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position),
              AXValueGetValue(rawSize as! AXValue, .cgSize, &size) else { return nil }
        return NSRect(origin: NSPoint(x: position.x, y: position.y), size: NSSize(width: size.width, height: size.height))
    }

    private static func attribute(_ element: AXUIElement, _ key: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    private static func printable(_ value: Any) -> String? {
        if let string = value as? String { return string.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let url = value as? URL { return url.absoluteString }
        return String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func ocrContext(imageJPEG: Data, mode: ContextMode) -> String {
        guard let image = NSImage(data: imageJPEG),
              var proposed = Optional(NSRect.zero),
              let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = mode == .fast ? .fast : .accurate
        request.usesLanguageCorrection = mode == .full
        request.recognitionLanguages = ["en-US"]
        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            let lines = (request.results ?? []).compactMap { observation -> String? in
                guard let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                // Vision uses a bottom-left normalized coordinate system;
                // Felix's pointer protocol uses top-left coordinates.
                let box = observation.boundingBox
                let x = Int(((box.midX) * 1000).rounded())
                let y = Int(((1 - box.midY) * 1000).rounded())
                return "text=\(text.prefix(180)) | center_top_left=(\(x),\(y))"
            }
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }
}
