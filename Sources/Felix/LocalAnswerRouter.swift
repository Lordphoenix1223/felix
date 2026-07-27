import Foundation

/// Handles requests that do not need a remote vision model.
///
/// Keeping these answers local is both faster and more reliable: the model
/// should not be asked to identify the frontmost app when AppKit already
/// knows it, and it should not be asked to invent navigation guidance when
/// OCR/Accessibility already found an exact target.
struct FelixLocalAnswerRouter: Sendable {
    static func foregroundAnswer(for question: String, appName: String?) -> String? {
        let normalized = normalize(question)
        let asksForApp = [
            "what application am i using",
            "which application am i using",
            "what app am i using",
            "which app am i using",
            "what application is this",
            "what app is this",
            "what is this app",
            "which app is open"
        ].contains { normalized.contains($0) }
        guard asksForApp, let appName, !appName.isEmpty else { return nil }
        return "you’re using \(appName.lowercased())."
    }

    static func navigationAnswer(for question: String, pointer: FelixPointer?) -> String? {
        let normalized = normalize(question)
        let asksForLocation = ["where", "find", "locate", "show me", "show"]
            .contains { normalized.contains($0) }
        guard asksForLocation, let pointer else { return nil }
        return "i found \(pointer.label.lowercased()). look here."
    }

    static func teachingAnswer(for question: String, pointer: FelixPointer?) -> String? {
        let normalized = normalize(question)
        guard normalized.contains("teach") || normalized.contains("how do i") || normalized.contains("how to") else { return nil }
        guard normalized.contains("new chat") || normalized.contains("chat button") || normalized.contains("chat option") else { return nil }
        guard let pointer else { return "i can’t see a new chat control in the current foreground app." }
        return "i’ll teach you: look at \(pointer.label.lowercased()), then click it to start a new chat."
    }

    static func browserTabAction(for question: String, context: String) -> FelixAction? {
        let normalized = normalize(question)
        guard normalized.contains("close") else { return nil }
        guard normalized.contains("tab") || normalized.contains("page") || normalized.contains("youtube") || normalized.contains("github") else { return nil }
        guard context.contains("browser=Chrome") || context.contains("browser=Safari") else { return nil }

        let browser = context.contains("browser=Safari") ? "Safari" : "Google Chrome"
        let current = normalized.contains("this tab") || normalized.contains("current tab") || normalized.contains("current page")
        let target: String
        if current {
            target = "__current__"
        } else {
            var candidate = normalized
            ["please", "close", "the", "my", "tab", "page", "app", "application", "on", "in", "browser", "chrome", "safari"].forEach {
                candidate = candidate.replacingOccurrences(of: "\\b\($0)\\b", with: " ", options: .regularExpression)
            }
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { return nil }
            // Keep common site names canonical. This prevents phrases such as
            // “close my YouTube tab” from becoming the literal target “youtube app”.
            if candidate.contains("youtube") { candidate = "youtube" }
            else if candidate.contains("github") { candidate = "github" }
            target = candidate
        }
        let summary = target == "__current__" ? "close the current browser tab" : "close the \(target) browser tab"
        return FelixAction(kind: "local", toolSlug: "close_browser_tab", arguments: [
            "browser": AnySendable(value: browser),
            "target": AnySendable(value: target)
        ], summary: summary, requiresConfirmation: true)
    }

    static func namedSiteAction(for question: String) -> FelixAction? {
        let normalized = normalize(question)
        let openWords = ["open", "go to", "navigate to", "take me to", "visit"]
        guard openWords.contains(where: { normalized.contains($0) }),
              let url = FelixNamedSiteResolver.url(for: normalized) else { return nil }
        let site = url.host?.replacingOccurrences(of: "www.", with: "") ?? "that site"
        return FelixAction(kind: "local", toolSlug: "open_url",
            arguments: ["url": AnySendable(value: url.absoluteString)],
            summary: "open \(site)", requiresConfirmation: true)
    }

    static func automationRequest(for question: String) -> (description: String, interval: TimeInterval)? {
        let normalized = normalize(question)
        guard normalized.contains("every") || normalized.contains("automate") else { return nil }
        let pattern = #"every\s+([a-z]+|\d+)\s+(seconds|second|minutes|minute|hours|hour)"#
        guard let match = normalized.range(of: pattern, options: .regularExpression) else { return nil }
        let phrase = String(normalized[match])
        let parts = phrase.split(separator: " ")
        guard parts.count >= 3, let amount = number(String(parts[1])) else { return nil }
        let unit = String(parts[2])
        let multiplier: Double = unit.hasPrefix("second") ? 1 : unit.hasPrefix("minute") ? 60 : 3600
        let description = normalized
            .replacingOccurrences(of: phrase, with: "")
            .replacingOccurrences(of: "automate", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return nil }
        return (description, max(30, amount * multiplier))
    }

    private static func number(_ value: String) -> Double? {
        if let numeric = Double(value) { return numeric }
        let words: [String: Double] = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3,
            "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
            "ten": 10, "fifteen": 15, "twenty": 20, "thirty": 30]
        return words[value]
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
    }
}
