import Foundation

/// Resolves screen targets from local evidence before the vision model is
/// allowed to guess. This is intentionally small and deterministic: a false
/// pointer is worse than saying that a control was not found.
struct FelixTargetResolver: Sendable {
    static func resolve(question: String, context: String) -> FelixPointer? {
        let query = normalize(question)
        guard isLocationRequest(query) else { return nil }

        let newChat = query.contains("new chat") || query.contains("chat button") || query.contains("chat option") || query.contains("new conversation")
        let requested = newChat ? ["new chat", "new conversation", "start chat", "new thread"] : query.split(separator: " ").map(String.init).filter { $0.count > 2 && !stopwords.contains($0) }
        guard !requested.isEmpty else { return nil }

        var ranked: [(pointer: FelixPointer, score: Int, isAX: Bool)] = []
        for rawLine in context.split(separator: "\n").map(String.init) {
            let line = rawLine.lowercased()
            guard let coordinate = coordinates(in: line), !isFelixOverlay(line) else { continue }
            let sourceIsAX = line.contains("role=") || line.contains("title=") || line.contains("description=") || line.contains("help=") || line.contains("identifier=")
            let roleIsControl = ["axbutton", "axlink", "axmenuitem", "button", "link", "menuitem", "checkbox", "radiobutton"].contains { line.contains("role=\($0)") }
            let label = labelFrom(rawLine)
            guard !label.isEmpty, !isGeneric(label) else { continue }
            let normalizedLine = normalize(line)
            var score = sourceIsAX ? 20 : 0
            score += roleIsControl ? 70 : 0
            if newChat {
                // A phrase in page prose or in Felix's surrounding chat is
                // not a control. Prefer an interactive Accessibility element,
                // but allow one unique OCR control as the fallback for apps
                // (notably browsers) that do not expose their DOM to AX.
                if sourceIsAX {
                    guard roleIsControl else { continue }
                } else {
                    guard line.contains("text=") else { continue }
                }
                if normalizedLine.contains("new chat") { score += sourceIsAX ? 300 : 240 }
                else if normalizedLine.contains("new conversation") { score += sourceIsAX ? 260 : 220 }
                else if normalizedLine.contains("start chat") || normalizedLine.contains("new thread") { score += sourceIsAX ? 210 : 200 }
                else { continue }
            } else {
                let hits = requested.filter { normalizedLine.contains($0) }
                guard !hits.isEmpty else { continue }
                score += hits.count * 55
                if normalizedLine.contains(normalize(label)) { score += 15 }
            }
            if line.contains("text=") && !sourceIsAX { score -= 8 }
            let pointer = FelixPointer(x: coordinate.x, y: coordinate.y, label: label, style: "target")
            ranked.append((pointer, score, sourceIsAX && roleIsControl))
        }
        let accessibilityMatches = ranked.filter(\.isAX)
        if !accessibilityMatches.isEmpty {
            ranked = accessibilityMatches
        } else if ranked.count != 1 {
            // Multiple OCR hits commonly mean Felix found the user's words
            // in a document/chat transcript rather than the actual button.
            return nil
        }
        ranked.sort { $0.score > $1.score }
        guard let best = ranked.first, best.score >= 180 else { return nil }
        if let second = ranked.dropFirst().first, best.score - second.score < 24, second.score >= 180 {
            return nil
        }
        return best.pointer
    }

    private static let stopwords: Set<String> = ["where", "is", "the", "a", "an", "on", "my", "screen", "current", "please", "show", "find", "locate", "teach", "me", "how", "to", "open", "button", "option"]

    private static func isLocationRequest(_ query: String) -> Bool {
        ["where", "find", "locate", "show me", "show", "teach me", "how do i", "how to"].contains { query.contains($0) }
    }

    private static func coordinates(in line: String) -> (x: Double, y: Double)? {
        guard let match = line.range(of: #"center_top_left=\(\s*(\d+)\s*,\s*(\d+)\s*\)"#, options: .regularExpression) else { return nil }
        let values = String(line[match]).split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }
        guard values.count >= 2 else { return nil }
        return (values[0], values[1])
    }

    private static func labelFrom(_ rawLine: String) -> String {
        let fields = rawLine.split(separator: "|").map { String($0) }
        let preferred = ["title=", "description=", "help=", "identifier=", "text="]
        for key in preferred {
            if let field = fields.first(where: { $0.lowercased().trimmingCharacters(in: .whitespaces).hasPrefix(key) }) {
                let value = field.drop { $0 != "=" }.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return String(value.prefix(60)) }
            }
        }
        return ""
    }

    private static func isFelixOverlay(_ line: String) -> Bool {
        ["felix", "look here", "target locked", "screen target", "replay", "listening", "thinking", "answer ready", "action blocked", "i found target"].contains { line.contains($0) }
    }

    private static func isGeneric(_ label: String) -> Bool {
        ["target", "here", "the target", "matching item", "the matching item", "unknown"].contains(normalize(label))
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression).split(separator: " ").joined(separator: " ")
    }
}
