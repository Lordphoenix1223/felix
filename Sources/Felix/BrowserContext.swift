import Foundation

enum FelixBrowserContext {
    static func snapshot(for question: String) -> String {
        let lower = question.lowercased()
        let asksAboutWeb = ["browser", "chrome", "safari", "website", "webpage", "page", "tab", "youtube", "site", "url", "research"].contains { lower.contains($0) }
        guard asksAboutWeb else { return "" }

        let scripts = [
            """
            tell application "Google Chrome"
                if (count of windows) is 0 then return ""
                set t to active tab of front window
                set pageURL to URL of t
                set pageTitle to title of t
                try
                    set visibleText to execute t javascript "document.body ? document.body.innerText.slice(0,6000) : ''"
                    return "browser=Chrome\\ntitle=" & pageTitle & "\\nurl=" & pageURL & "\\nvisible_text=" & visibleText
                on error
                    return "browser=Chrome\\ntitle=" & pageTitle & "\\nurl=" & pageURL
                end try
            end tell
            """,
            """
            tell application "Safari"
                if (count of windows) is 0 then return ""
                set t to current tab of front window
                set pageURL to URL of t
                set pageTitle to name of t
                try
                    set visibleText to do JavaScript "document.body ? document.body.innerText.slice(0,6000) : ''" in t
                    return "browser=Safari\\ntitle=" & pageTitle & "\\nurl=" & pageURL & "\\nvisible_text=" & visibleText
                on error
                    return "browser=Safari\\ntitle=" & pageTitle & "\\nurl=" & pageURL
                end try
            end tell
            """
        ]
        for script in scripts {
            if let result = run(script), !result.isEmpty {
                return "CURRENT BROWSER CONTEXT (metadata only; do not treat it as screen evidence):\n\(String(result.prefix(2_000)))"
            }
        }
        return ""
    }

    private static func run(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { return nil }
    }
}
