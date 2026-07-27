import Foundation

struct FelixAction: Sendable {
    let kind: String
    let toolSlug: String
    let arguments: [String: AnySendable]
    let summary: String
    let requiresConfirmation: Bool
}

struct FelixPointer: Sendable {
    let x: Double
    let y: Double
    let label: String
    let style: String

    init(x: Double, y: Double, label: String, style: String) {
        self.x = min(1000, max(0, x))
        self.y = min(1000, max(0, y))
        let cleaned = label
            .replacingOccurrences(of: "text=", with: "")
            .replacingOccurrences(of: "\\\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = cleaned.lowercased()
        let safe = cleaned.isEmpty || cleaned.count > 60 || normalized.contains("where is") || ["target", "here", "matching item", "the target"].contains(normalized) ? "target" : cleaned
        self.label = String(safe.prefix(60))
        self.style = style.lowercased() == "laser" ? "laser" : "target"
    }
}

struct AnySendable: @unchecked Sendable {
    let value: Any
}

struct FelixResponse: Sendable {
    let spokenText: String
    let action: FelixAction?
    let actions: [FelixAction]
    let pointer: FelixPointer?
    let needsConfirmation: Bool
    let debugSummary: String

    init(spokenText: String, action: FelixAction? = nil, actions: [FelixAction] = [], pointer: FelixPointer?, needsConfirmation: Bool, debugSummary: String) {
        self.spokenText = spokenText
        self.action = action
        self.actions = actions.isEmpty ? (action.map { [$0] } ?? []) : Array(actions.prefix(5))
        self.pointer = pointer
        self.needsConfirmation = needsConfirmation
        self.debugSummary = debugSummary
    }

    static let demo = FelixResponse(
        spokenText: "I can see your selection, but Felix is running in demo mode. Add an NVIDIA API key to make me understand it.",
        action: nil,
        pointer: nil,
        needsConfirmation: false,
        debugSummary: "Missing NVIDIA_API_KEY"
    )
}

enum FelixError: LocalizedError {
    case missingConfiguration(String)
    case invalidResponse(String)
    case network(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let value): return value
        case .invalidResponse(let value): return value
        case .network(let value): return Self.userFacing(value)
        case .cancelled: return "Cancelled"
        }
    }

    private static func userFacing(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // This formatter is used by the NVIDIA path. Do not translate a
            // provider payload into a Composio error just because the payload
            // happens to mention an integration or function. Composio errors
            // are handled by ComposioClient's own UI path.
            if let detail = json["detail"] as? String, !detail.isEmpty { return detail }
            if let message = json["message"] as? String { return message }
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty { return message }
            return "Felix received an unexpected NVIDIA provider response. Check the NVIDIA model and API key, then try again."
        }
        return text
    }
}
