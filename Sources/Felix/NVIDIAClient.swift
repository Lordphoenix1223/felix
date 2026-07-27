import AppKit
import Foundation
import ImageIO

struct NVIDIAClient: Sendable {
    let configuration: FelixConfiguration

    func ask(imageJPEG: Data, question: String, context: String) async throws -> FelixResponse {
        guard let apiKey = configuration.nvidiaAPIKey else { return .demo }

        let lowerQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let simpleQuestion = Self.isSimpleQuestion(lowerQuestion)
        let imageData = Self.prepareImage(imageJPEG, maxBytes: simpleQuestion ? 100_000 : 170_000, maxPixelSize: simpleQuestion ? 1000 : 1400)
        let imageURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        let system = """
        You are Felix, a concise screen-aware desktop companion. The image attached to this request is a fresh capture and is the authoritative visual context for this turn.
        Never answer a current-screen question from historical memory. Historical memory may resolve phrases such as "the other one", but it must never override what is visibly present in the attached image.
        Answer as text that can also be spoken: use plain lowercase conversational words, no headings, no confidence scores, no essay, no markdown. Keep every answer to one or two short sentences and at most 280 characters.
        For questions like "what is this?", "what am I looking at?", or "what's on my screen?", give a concrete best-effort description of the most important visible content, app, document, page, or object. Do not ask the user to provide more details when the image is present. Never say you cannot identify the image unless the image is genuinely blank, corrupted, or unreadable.
        If the user selected the whole screen, identify the dominant foreground application/window first. Treat the desktop background as secondary unless the user explicitly asks about the wallpaper or desktop.
        Use OCR and Accessibility context when supplied, but still inspect the image itself.
        Think in this order before writing spoken_text: identify the dominant visible subject, use supplied OCR/accessibility evidence to disambiguate it, answer the user's actual intent directly, then choose a point only if it improves the explanation. Do not narrate this reasoning or mention internal context.
        For side effects, internally form a short plan, choose only the next action that is directly supported by current evidence, then rely on Felix's local verifier after execution. Never invent a completed result. If the target or result is uncertain, explain the uncertainty and stop.
        If an external action is clearly requested, return a single JSON object with spoken_text, action (for one action), or steps (for a short multi-step plan), and requires_confirmation. Distinguish commands such as "open a new chat", "show me where", "find", and "what is this"; they are not interchangeable.
        For a multi-step request, steps must contain at most five allowlisted actions, in order. Never invent a target, coordinates, completion, or a result. If any step is ambiguous, return only the safe steps and explain what needs confirmation.
        If no action is requested, action must be null. Never invent tool slugs. Use only the supplied tool list.
        For identification, explanation, or guidance, return point whenever you can identify a meaningful target so Felix can point at it. Return point as normalized coordinates within the selected image: x and y from 0 to 1000, plus a short label. Only return null when there is no meaningful target to point at.
        For a "find", "where is", or "locate" request, match the requested object against OCR/accessibility evidence first. Point to the matching evidence coordinates, not the nearest generic button. If the requested object is not visible or cannot be matched, say that clearly and return point null.
        Never use labels such as "target", "here", "matching item", or "the target". Never return a point merely because some point is available; a location point must be grounded in a matching OCR or Accessibility line.
        The action kind must be "composio" for an integration tool or "local" for one of these allowlisted local actions: copy_selection, open_url, open_app, close_app, type_text, click_point, close_browser_tab, new_browser_tab, focus_browser_tab, create_automation.
        When the user explicitly asks to open or navigate to a website, you may return local open_url with a complete https URL in arguments.url. Opening a website requires confirmation, but is safe to propose.
        When the user explicitly asks to launch a named Mac application, you may return local open_app with arguments.name. Launching an app requires confirmation.
        When the user explicitly asks to close a named Mac application, you may return local close_app with arguments.name. Closing an app requires confirmation.
        When the user explicitly asks Felix to enter or paste text into the currently focused field, you may return local type_text with arguments.text. Typing requires confirmation and must never be inferred from a general question.
        Only propose click_point when the user explicitly asks Felix to click, and only when a point is also present. Clicks always require confirmation.
        For browser requests, use the supplied browser metadata. "close my youtube tab" means close a matching Chrome/Safari tab by title or URL, not search the screenshot for the words. "teach me how to open a new chat" means provide a short numbered teaching response and a point to the real control. Do not say "attached image" or ask the user to inspect an attachment.
        For an explicitly recurring request such as "every five minutes, do X", return local create_automation with arguments.description and arguments.interval_seconds. Never create an automation from a vague mention of a schedule.
        Side effects such as sending, deleting, publishing, creating, editing, or posting always require confirmation.
        Return JSON only in this exact shape:
        {"spoken_text":"...","action":null,"point":null,"requires_confirmation":false}
        or
        {"spoken_text":"...","action":null,"point":{"x":500,"y":500,"label":"the button","style":"target"},"requires_confirmation":false}
        or
        {"spoken_text":"...","steps":[{"kind":"local","tool_slug":"open_url","arguments":{"url":"https://example.com"},"summary":"open the site"}],"point":null,"requires_confirmation":true}
        """
        let userText = "CURRENT USER QUESTION (highest priority): \(question)\n\nCURRENT SCREEN EVIDENCE (use this for the answer):\n\(context.isEmpty ? "No extra text context supplied; inspect the image." : context)"
        let requestID = UUID().uuidString
        guard let endpoint = URL(string: "https://integrate.api.nvidia.com/v1/chat/completions") else {
            throw FelixError.network("NVIDIA endpoint is invalid")
        }
        let difficultTerms = ["research", "compare", "plan", "multi-step", "automation", "navigate", "edit", "find", "where is", "locate", "why", "analyze"]
        let isDifficult = difficultTerms.contains { lowerQuestion.contains($0) } || question.count > 140
        var models = [isDifficult ? configuration.nvidiaModel : (configuration.nvidiaFastModel ?? "meta/llama-3.2-11b-vision-instruct")]
        if !isDifficult && simpleQuestion { models.append(configuration.nvidiaModel) }
        if let fallback = configuration.nvidiaFallbackModel,
           !fallback.isEmpty { models.append(fallback) }
        models = Array(NSOrderedSet(array: models)) as? [String] ?? models

        var lastError: Error = FelixError.network("NVIDIA request failed")
        for model in models {
            let attempts = simpleQuestion ? 1 : 2
            for attempt in 0..<attempts {
                do {
                    let body: [String: Any] = [
                        "model": model,
                        "temperature": simpleQuestion ? 0.1 : 0.15,
                        "max_tokens": simpleQuestion ? 180 : 450,
                        "stream": false,
                        "messages": [
                            ["role": "system", "content": system],
                            ["role": "user", "content": [
                                ["type": "text", "text": userText],
                                ["type": "image_url", "image_url": ["url": imageURL]]
                            ]]
                        ]
                    ]
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = simpleQuestion ? 14 : 30
                    request.setValue(requestID, forHTTPHeaderField: "X-Felix-Request-ID")
                    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse else { throw FelixError.network("No HTTP response") }
                    guard (200..<300).contains(http.statusCode) else {
                        let message = String(data: data, encoding: .utf8) ?? "NVIDIA returned HTTP \(http.statusCode)"
                        let error = FelixError.network("NVIDIA HTTP \(http.statusCode): \(message)")
                        lastError = error
                        if [401, 403, 404].contains(http.statusCode) { break }
                        throw error
                    }

                    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = root["choices"] as? [[String: Any]],
                          let message = choices.first?["message"] as? [String: Any],
                          let content = message["content"] as? String else {
                        throw FelixError.invalidResponse("NVIDIA response did not contain message content")
                    }
                    return parseResponse(content)
                } catch {
                    lastError = error
                    if attempt == 0 { try? await Task.sleep(nanoseconds: 350_000_000) }
                }
            }
        }
        throw lastError
    }

    private static func prepareImage(_ data: Data, maxBytes: Int = 170_000, maxPixelSize: Int = 1400) -> Data {
        guard data.count > maxBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                  kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return data }

        let bitmap = NSBitmapImageRep(cgImage: image)
        var quality = 0.72
        var compressed = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) ?? data
        while compressed.count > maxBytes && quality > 0.28 {
            quality -= 0.08
            compressed = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) ?? compressed
        }
        return compressed
    }

    private static func isSimpleQuestion(_ question: String) -> Bool {
        let simpleOpeners = ["what is this", "what's this", "what am i looking at", "what is on my screen", "what's on my screen", "describe this screen", "describe the screen"]
        let hasSimpleOpener = simpleOpeners.contains { question.contains($0) }
        let actionWords = ["find", "where", "locate", "open", "close", "click", "type", "move", "research", "compare", "edit", "do this", "automate"]
        return hasSimpleOpener && question.count <= 120 && !actionWords.contains { question.contains($0) }
    }

    private func parseResponse(_ content: String) -> FelixResponse {
        let withoutThinking = content.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
        let fenced = withoutThinking.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned: String
        if let start = fenced.firstIndex(of: "{"), let end = fenced.lastIndex(of: "}"), start <= end {
            cleaned = String(fenced[start...end])
        } else {
            cleaned = fenced
        }
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let spoken = json["spoken_text"] as? String else {
            return FelixResponse(spokenText: Self.conciseSpeech(withoutThinking), pointer: nil, needsConfirmation: false, debugSummary: "Plain response fallback")
        }

        func parseAction(_ rawAction: [String: Any]) -> FelixAction? {
            guard let slug = rawAction["tool_slug"] as? String,
                  let summary = rawAction["summary"] as? String,
                  !slug.isEmpty, !summary.isEmpty else { return nil }
            let rawArguments = rawAction["arguments"] as? [String: Any] ?? [:]
            let kind = (rawAction["kind"] as? String)?.lowercased() ?? "composio"
            let safeKind = ["composio", "local"].contains(kind) ? kind : "composio"
            return FelixAction(kind: safeKind, toolSlug: slug, arguments: rawArguments.mapValues(AnySendable.init), summary: summary, requiresConfirmation: true)
        }
        let action = (json["action"] as? [String: Any]).flatMap(parseAction)
        let steps = Array(((json["steps"] as? [[String: Any]])?.compactMap(parseAction).prefix(5)) ?? [])
        let pointer: FelixPointer? = {
            guard let raw = json["point"] as? [String: Any],
                  let x = raw["x"] as? NSNumber,
                  let y = raw["y"] as? NSNumber else { return nil }
            let clampedX = min(1000, max(0, x.doubleValue))
            let clampedY = min(1000, max(0, y.doubleValue))
            let label = (raw["label"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !["", "target", "here", "matching item", "the target"].contains(label.lowercased()) else { return nil }
            let style = (raw["style"] as? String)?.lowercased() == "laser" ? "laser" : "target"
            return FelixPointer(x: clampedX, y: clampedY, label: String(label.prefix(40)), style: style)
        }()
        return FelixResponse(spokenText: Self.conciseSpeech(spoken), action: action, actions: steps, pointer: pointer, needsConfirmation: (json["requires_confirmation"] as? Bool) ?? (action != nil || !steps.isEmpty), debugSummary: steps.isEmpty ? "Structured NVIDIA response" : "Structured multi-step response")
    }

    private static func conciseSpeech(_ text: String) -> String {
        let plain = text
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sentences = plain.split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" })
            .prefix(2)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let result = sentences.joined(separator: ". ")
        return String((result.isEmpty ? plain : result).lowercased().prefix(280))
    }
}
