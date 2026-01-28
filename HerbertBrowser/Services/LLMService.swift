import Foundation

/// Service for Claude API integration with vision support
class LLMService {
    private var apiKey: String?
    private let baseURL = "https://api.anthropic.com/v1/messages"

    init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    func setAPIKey(_ key: String?) {
        self.apiKey = key?.isEmpty == true ? nil : key
    }

    var isConfigured: Bool {
        apiKey != nil && !apiKey!.isEmpty
    }

    /// Parse a complex instruction into browser actions using Claude with optional screenshot
    func parseInstruction(
        _ instruction: String,
        pageContext: PageAnalysis?,
        screenshot: String? = nil
    ) async throws -> [BrowserAction] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw LLMError.notConfigured
        }

        let response = try await sendRequest(
            instruction: instruction,
            pageContext: pageContext,
            screenshotBase64: screenshot
        )
        return parseResponse(response)
    }

    /// Send request to Claude API with optional vision
    private func sendRequest(
        instruction: String,
        pageContext: PageAnalysis?,
        screenshotBase64: String?
    ) async throws -> String {
        guard let apiKey = apiKey else {
            throw LLMError.notConfigured
        }

        guard let url = URL(string: baseURL) else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Build the content array
        var contentArray: [[String: Any]] = []

        // Add screenshot if available
        if let screenshot = screenshotBase64 {
            contentArray.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": screenshot
                ]
            ])
        }

        // Build the text prompt
        let textPrompt = buildPrompt(instruction: instruction, pageContext: pageContext, hasScreenshot: screenshotBase64 != nil)
        contentArray.append([
            "type": "text",
            "text": textPrompt
        ])

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 2048,
            "messages": [
                ["role": "user", "content": contentArray]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorBody = String(data: data, encoding: .utf8) {
                throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
            }
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: "Unknown error")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw LLMError.invalidResponse
        }

        return text
    }

    /// Build the prompt for Claude
    private func buildPrompt(instruction: String, pageContext: PageAnalysis?, hasScreenshot: Bool) -> String {
        var prompt = """
            You are a browser automation assistant. Given a user instruction\(hasScreenshot ? " and a screenshot of the current page" : ""),
            return a JSON array of actions to perform.

            IMPORTANT: Look at the screenshot carefully to identify:
            - Form fields and their labels (the label text is usually near the input field)
            - Buttons and links (identify them by their visible text)
            - Checkboxes and radio buttons (note the text next to them)
            - Dropdown menus (identify by the currently selected option or label)

            Each action should be one of:
            - {"action": "navigate", "url": "https://..."}
            - {"action": "click", "target": "exact visible text or description"}
            - {"action": "type", "text": "text to type", "target": "field label or placeholder text"}
            - {"action": "scroll", "direction": "up|down|top|bottom"}
            - {"action": "select", "option": "option text", "target": "dropdown label"}
            - {"action": "submit"}
            - {"action": "back"}
            - {"action": "forward"}
            - {"action": "wait", "seconds": 1}

            For targets, use the EXACT visible text you see in the screenshot. For form fields:
            - Use the label text that appears next to or above the field
            - For placeholder text, use what's shown inside the field
            - For buttons, use the exact button text

            User instruction: \(instruction)

            """

        if let context = pageContext {
            prompt += """

                Page info: \(context.title) (\(context.url))

                """

            // Add form information
            if !context.forms.isEmpty {
                prompt += "Forms detected: \(context.forms.count)\n"
            }

            // Add some element context (but rely primarily on screenshot)
            let inputs = context.elements.filter {
                $0.isVisible && ($0.tagName == "input" || $0.tagName == "textarea" || $0.tagName == "select")
            }
            if !inputs.isEmpty {
                prompt += "\nForm fields found:\n"
                for input in inputs.prefix(20) {
                    var desc = "- \(input.tagName)"
                    if let name = input.name, !name.isEmpty {
                        desc += " name=\"\(name)\""
                    }
                    if let placeholder = input.placeholder, !placeholder.isEmpty {
                        desc += " placeholder=\"\(placeholder)\""
                    }
                    if let type = input.type {
                        desc += " type=\"\(type)\""
                    }
                    prompt += desc + "\n"
                }
            }
        }

        if hasScreenshot {
            prompt += """

                IMPORTANT: Use the screenshot to identify the exact text labels for form fields.
                Match the user's instruction to what you can SEE in the screenshot.
                If the user says "Customer name", look for a field labeled "Customer name" or similar in the screenshot.

                """
        }

        prompt += """

            Return ONLY a valid JSON array of actions, no explanation or markdown. Example:
            [{"action": "type", "text": "John", "target": "Customer name"}]
            """

        return prompt
    }

    /// Parse Claude's response into browser actions
    private func parseResponse(_ response: String) -> [BrowserAction] {
        // Extract JSON from response (it might have markdown formatting)
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code block if present
        if jsonString.hasPrefix("```") {
            if let endIndex = jsonString.range(of: "\n") {
                jsonString = String(jsonString[endIndex.upperBound...])
            }
            if jsonString.hasSuffix("```") {
                jsonString = String(jsonString.dropLast(3))
            }
            jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = jsonString.data(using: .utf8),
              let actions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [.unknown(instruction: "Failed to parse LLM response: \(jsonString.prefix(100))")]
        }

        return actions.compactMap { parseAction($0) }
    }

    private func parseAction(_ dict: [String: Any]) -> BrowserAction? {
        guard let actionType = dict["action"] as? String else {
            return nil
        }

        switch actionType {
        case "navigate":
            guard let url = dict["url"] as? String else { return nil }
            return .navigate(url: url)

        case "click":
            guard let target = dict["target"] as? String else { return nil }
            return .click(target: targetFromString(target))

        case "type":
            guard let text = dict["text"] as? String,
                  let target = dict["target"] as? String else { return nil }
            return .type(text: text, target: targetFromString(target))

        case "scroll":
            guard let direction = dict["direction"] as? String else { return nil }
            return .scroll(direction: ScrollDirection(rawValue: direction) ?? .down)

        case "select":
            guard let option = dict["option"] as? String,
                  let target = dict["target"] as? String else { return nil }
            return .select(option: option, target: targetFromString(target))

        case "submit":
            return .submit(formTarget: nil)

        case "back":
            return .back

        case "forward":
            return .forward

        case "wait":
            let seconds = (dict["seconds"] as? Double) ?? (dict["seconds"] as? Int).map { Double($0) } ?? 1.0
            return .wait(seconds: seconds)

        default:
            return nil
        }
    }

    private func targetFromString(_ target: String) -> ElementTarget {
        // Check if it looks like a CSS selector
        if target.hasPrefix("#") || target.hasPrefix(".") || target.contains("[") || target.contains(">") {
            return .selector(target)
        }
        // Use as label/text target
        return .label(target)
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Claude API key not configured. Add your API key in Settings."
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from Claude API"
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        }
    }
}
