import Foundation

struct FelixConfiguration: Sendable {
    let nvidiaAPIKey: String?
    let nvidiaAPIKeyIssue: String?
    let nvidiaModel: String
    let nvidiaFastModel: String?
    let nvidiaFallbackModel: String?
    let composioAPIKey: String?
    let composioUserID: String
    let composioBaseURL: URL
    let contextFile: URL?

    static func load() -> FelixConfiguration {
        let values = DotEnv.load()
        let env = ProcessInfo.processInfo.environment

        func value(_ key: String) -> String? {
            let raw = values[key] ?? env[key]
            guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return raw
        }

        let defaultBaseURL = URL(string: "https://backend.composio.dev/api/v3.1") ?? URL(fileURLWithPath: "/")
        let baseURL = URL(string: value("COMPOSIO_BASE_URL") ?? "") ?? defaultBaseURL
        let context = value("FELIX_CONTEXT_FILE").map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
        let rawNVIDIAKey = value("NVIDIA_API_KEY")
        let validNVIDIAKey: String? = rawNVIDIAKey.flatMap { key in
            guard key.hasPrefix("nvapi-"), !key.contains(where: { $0.isWhitespace }) else { return nil }
            return key
        }
        let issue = rawNVIDIAKey == nil ? nil : (validNVIDIAKey == nil ? "NVIDIA_API_KEY looks malformed. Re-enter the nvapi-… key with the setup script." : nil)
        // Treat malformed optional integration credentials as absent. This
        // keeps ordinary screen questions reliable when a copied JSON value,
        // quote, or whitespace accidentally lands in the Composio setting.
        let rawComposioKey = value("COMPOSIO_API_KEY")
        let validComposioKey: String? = rawComposioKey.flatMap { key in
            guard !key.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "'" }) else { return nil }
            return key.count >= 12 ? key : nil
        }
        return FelixConfiguration(
            nvidiaAPIKey: validNVIDIAKey,
            nvidiaAPIKeyIssue: issue,
            nvidiaModel: value("NVIDIA_MODEL") ?? "meta/llama-3.2-90b-vision-instruct",
            nvidiaFastModel: value("NVIDIA_FAST_MODEL") ?? "meta/llama-3.2-11b-vision-instruct",
            nvidiaFallbackModel: value("NVIDIA_FALLBACK_MODEL"),
            composioAPIKey: validComposioKey,
            composioUserID: value("COMPOSIO_USER_ID") ?? "felix-local-user",
            composioBaseURL: baseURL,
            contextFile: context
        )
    }
}

enum DotEnv {
    static func load() -> [String: String] {
        var candidates = [URL]()
        let homeFile = URL(fileURLWithPath: NSString(string: "~/.felix/.env").expandingTildeInPath)
        candidates.append(homeFile)

        if let bundleURL = Bundle.main.bundleURL as URL? {
            candidates.append(bundleURL.deletingLastPathComponent().appendingPathComponent(".env"))
        }

        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env"))

        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let contents = try? String(contentsOf: url, encoding: .utf8) else { return [:] }

        return parse(contents)
    }

    static func parse(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            result[key] = value
        }
        return result
    }
}
