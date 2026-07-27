import Foundation

struct ComposioClient: Sendable {
    let configuration: FelixConfiguration
    private let session: URLSession = .shared

    func createSession() async throws -> String {
        guard let apiKey = configuration.composioAPIKey else { throw FelixError.missingConfiguration("Composio is not configured.") }
        var request = makeRequest(path: "/tool_router/session", apiKey: apiKey)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["user_id": configuration.composioUserID])
        let data = try await send(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let id = json["session_id"] as? String else { throw FelixError.invalidResponse("Composio did not return a session_id") }
        return id
    }

    func search(sessionID: String, useCase: String) async throws -> String {
        guard let apiKey = configuration.composioAPIKey else { return "No Composio tools configured." }
        var request = makeRequest(path: "/tool_router/session/\(sessionID)/search", apiKey: apiKey)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["queries": [["use_case": useCase]]])
        return String(data: try await send(request), encoding: .utf8) ?? ""
    }

    func link(sessionID: String, toolkit: String) async throws -> URL {
        guard let apiKey = configuration.composioAPIKey else { throw FelixError.missingConfiguration("Composio is not configured.") }
        var request = makeRequest(path: "/tool_router/session/\(sessionID)/link", apiKey: apiKey)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["toolkit": toolkit.lowercased()])
        let data = try await send(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FelixError.invalidResponse("Composio returned an invalid link response") }
        let candidates = ["redirect_url", "redirect_uri", "url", "link"]
        for key in candidates where json[key] is String {
            if let urlString = json[key] as? String, let url = URL(string: urlString) { return url }
        }
        throw FelixError.invalidResponse("Composio did not return an authorization URL")
    }

    func execute(sessionID: String, toolSlug: String, arguments: [String: AnySendable]) async throws -> String {
        guard let apiKey = configuration.composioAPIKey else { throw FelixError.missingConfiguration("Composio is not configured.") }
        var request = makeRequest(path: "/tool_router/session/\(sessionID)/execute", apiKey: apiKey)
        request.httpMethod = "POST"
        let args = arguments.mapValues { $0.value }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["tool_slug": toolSlug, "arguments": args])
        return String(data: try await send(request), encoding: .utf8) ?? ""
    }

    private func makeRequest(path: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: configuration.composioBaseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FelixError.network("No Composio HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw FelixError.network(body.isEmpty ? "Composio returned HTTP \(http.statusCode)" : body)
        }
        return data
    }
}
