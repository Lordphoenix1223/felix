import AppKit
import ApplicationServices

enum LocalActionExecutor {
    static func execute(_ action: FelixAction, context: String) throws -> String {
        guard action.kind == "local" else { throw FelixError.invalidResponse("Unsupported local action kind") }
        switch action.toolSlug.lowercased() {
        case "copy_selection":
            let requested = action.arguments["text"]?.value as? String
            let text = (requested?.isEmpty == false ? requested! : context).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw FelixError.invalidResponse("There is no text to copy") }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(text, forType: .string) else { throw FelixError.network("macOS did not accept the clipboard write") }
            return "Copied the selected context to your clipboard."

        case "open_url":
            guard let raw = action.arguments["url"]?.value as? String,
                  let url = URL(string: raw),
                  ["http", "https"].contains(url.scheme?.lowercased()) else {
                throw FelixError.invalidResponse("Felix can only open an explicit http or https URL")
            }
            guard NSWorkspace.shared.open(url) else { throw FelixError.network("macOS could not open that URL") }
            return "Opened the link."

        case "open_app":
            guard let name = action.arguments["name"]?.value as? String,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw FelixError.invalidResponse("Felix did not provide an application name")
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", name.trimmingCharacters(in: .whitespacesAndNewlines)]
            do { try process.run() } catch { throw FelixError.network("macOS could not open \(name)") }
            return "Opened \(name)."

        case "close_app":
            guard let name = action.arguments["name"]?.value as? String,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw FelixError.invalidResponse("Felix did not provide an application name")
            }
            let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = NSWorkspace.shared.runningApplications.filter {
                $0.localizedName?.caseInsensitiveCompare(wanted) == .orderedSame
            }
            guard let app = matches.first else { throw FelixError.invalidResponse("\(wanted) is not running") }
            guard app.terminate() else { throw FelixError.network("macOS could not close \(wanted)") }
            return "Closed \(wanted)."

        case "type_text":
            guard AXIsProcessTrusted() else {
                throw FelixError.missingConfiguration("Accessibility permission is required before Felix can type into a confirmed field.")
            }
            guard let raw = action.arguments["text"]?.value as? String,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw FelixError.invalidResponse("Felix did not provide text to insert")
            }
            let text = String(raw.prefix(2_000))
            let system = AXUIElementCreateSystemWide()
            var focused: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
            guard error == .success, let focused else {
                throw FelixError.invalidResponse("Felix could not find the focused text field")
            }
            let element = unsafeBitCast(focused, to: AXUIElement.self)
            guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success else {
                throw FelixError.invalidResponse("The focused control does not accept direct text insertion")
            }
            return "Inserted the requested text."

        case "click_point":
            guard let x = action.arguments["x"]?.value as? NSNumber,
                  let y = action.arguments["y"]?.value as? NSNumber else {
                throw FelixError.invalidResponse("Felix did not provide a click location")
            }
            return try click(at: NSPoint(x: x.doubleValue, y: y.doubleValue))

        case "close_browser_tab":
            let browser = action.arguments["browser"]?.value as? String ?? "Google Chrome"
            let target = action.arguments["target"]?.value as? String ?? "__current__"
            return try browserTabAction(browser: browser, target: target, operation: "close")

        case "new_browser_tab":
            let browser = action.arguments["browser"]?.value as? String ?? "Google Chrome"
            return try browserTabAction(browser: browser, target: "", operation: "new")

        case "focus_browser_tab":
            let browser = action.arguments["browser"]?.value as? String ?? "Google Chrome"
            let target = action.arguments["target"]?.value as? String ?? ""
            return try browserTabAction(browser: browser, target: target, operation: "focus")

        default:
            throw FelixError.invalidResponse("Local action \(action.toolSlug) is not allowlisted")
        }
    }

    static func click(at point: NSPoint) throws -> String {
        guard AXIsProcessTrusted() else {
            throw FelixError.missingConfiguration("Accessibility permission is required before Felix can click a confirmed target.")
        }
        let quartzY = (NSScreen.screens.map(\.frame.maxY).max() ?? 0) - point.y
        let location = CGPoint(x: point.x, y: quartzY)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left) else {
            throw FelixError.network("macOS could not create the click event")
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return "Clicked the confirmed target."
    }

    static func verify(_ action: FelixAction) -> String {
        switch action.toolSlug.lowercased() {
        case "open_app":
            let name = action.arguments["name"]?.value as? String ?? "the app"
            let running = NSWorkspace.shared.runningApplications.contains { $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame }
            return running ? "Verified: \(name) is running." : "Verification uncertain: \(name) has not appeared as running yet."
        case "close_app":
            let name = action.arguments["name"]?.value as? String ?? "the app"
            let running = NSWorkspace.shared.runningApplications.contains { $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame }
            return running ? "Verification failed: \(name) is still running." : "Verified: \(name) is no longer running."
        case "type_text":
            return AXIsProcessTrusted() ? "Verified: text insertion was sent to the focused accessibility element." : "Verification unavailable: Accessibility permission is missing."
        case "open_url": return "Verified: macOS accepted the URL open request."
        case "click_point": return "Verification limited: the click event was posted; Felix cannot prove the page's resulting state yet."
        case "close_browser_tab": return "Verified: the browser accepted the tab-close command."
        case "new_browser_tab": return "Verified: the browser accepted the new-tab command."
        case "focus_browser_tab": return "Verified: the browser accepted the tab-focus command."
        default: return "No verification rule exists for this action."
        }
    }

    private static func browserTabAction(browser: String, target: String, operation: String) throws -> String {
        let app: String
        switch browser.lowercased() {
        case "chrome", "google chrome": app = "Google Chrome"
        case "safari": app = "Safari"
        default: throw FelixError.invalidResponse("Felix only supports Chrome and Safari tab actions.")
        }
        let escapedTarget = target.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script: String
        if app == "Google Chrome" {
            script = """
            tell application "Google Chrome"
                if (count of windows) is 0 then error "Chrome has no open window."
                set targetText to my lowerText("\(escapedTarget)")
                if targetText is "__current__" and "\(operation)" is "close" then
                    close active tab of front window
                    return "closed the current Chrome tab"
                end if
                if "\(operation)" is "new" then
                    make new tab at end of tabs of front window
                    set active tab index of front window to (count of tabs of front window)
                    return "opened a new Chrome tab"
                end if
                repeat with w in windows
                    repeat with t in tabs of w
                        if (my lowerText(URL of t) contains targetText) or (my lowerText(title of t) contains targetText) then
                            if "\(operation)" is "focus" then
                                set index of w to 1
                                set active tab index of w to (index of t)
                                return "focused the matching Chrome tab"
                            else
                                close t
                                return "closed the matching Chrome tab"
                            end if
                        end if
                    end repeat
                end repeat
                error "No Chrome tab matched \(escapedTarget)."
            end tell
            on lowerText(valueText)
                return do shell script "/usr/bin/printf %s " & quoted form of (valueText as text) & " | /usr/bin/tr '[:upper:]' '[:lower:]'"
            end lowerText
            """
        } else {
            script = """
            tell application "Safari"
                if (count of windows) is 0 then error "Safari has no open window."
                set targetText to my lowerText("\(escapedTarget)")
                if targetText is "__current__" and "\(operation)" is "close" then
                    close current tab of front window
                    return "closed the current Safari tab"
                end if
                if "\(operation)" is "new" then
                    tell front window to make new tab at end of tabs
                    return "opened a new Safari tab"
                end if
                repeat with w in windows
                    repeat with t in tabs of w
                        if (my lowerText(URL of t) contains targetText) or (my lowerText(name of t) contains targetText) then
                            if "\(operation)" is "focus" then
                                set current tab of w to t
                                return "focused the matching Safari tab"
                            else
                                close t
                                return "closed the matching Safari tab"
                            end if
                        end if
                    end repeat
                end repeat
                error "No Safari tab matched \(escapedTarget)."
            end tell
            on lowerText(valueText)
                return do shell script "/usr/bin/printf %s " & quoted form of (valueText as text) & " | /usr/bin/tr '[:upper:]' '[:lower:]'"
            end lowerText
            """
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe(); let errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        do { try process.run(); process.waitUntilExit() } catch { throw FelixError.network("macOS could not run the browser action.") }
        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else { throw FelixError.invalidResponse(stderr.isEmpty ? "The browser rejected that tab action." : stderr) }
        return stdout.isEmpty ? "browser action complete" : stdout
    }
}
