import Foundation

/// Service for Claude API integration
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

    /// Parse a complex instruction into browser actions using Claude
    func parseInstruction(_ instruction: String, pageContext: PageAnalysis?) async throws -> [BrowserAction] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw LLMError.notConfigured
        }

        let prompt = buildPrompt(instruction: instruction, pageContext: pageContext)
        let response = try await sendRequest(prompt: prompt)
        return parseResponse(response)
    }

    /// Build the prompt for Claude
    private func buildPrompt(instruction: String, pageContext: PageAnalysis?) -> String {
        var prompt = """
            You are a browser automation assistant. Given a user instruction and the current page context,
            return a JSON array of actions to perform. Each action should be one of:

            - {"action": "navigate", "url": "https://..."}
            - {"action": "click", "target": "button text or selector"}
            - {"action": "type", "text": "text to type", "target": "field identifier"}
            - {"action": "scroll", "direction": "up|down|top|bottom"}
            - {"action": "select", "option": "option text", "target": "dropdown identifier"}
            - {"action": "submit"}
            - {"action": "back"}
            - {"action": "forward"}
            - {"action": "wait", "seconds": 1}

            For targets, prefer using visible text content. If that's ambiguous, use CSS selectors.

            User instruction: \(instruction)

            """

        if let context = pageContext {
            prompt += """

                Current page: \(context.title) (\(context.url))

                Interactive elements on page:
                """

            for element in context.interactiveElements.prefix(50) {
                let text = element.displayText
                if !text.isEmpty && text.count < 100 {
                    prompt += "\n- \(element.tagName): \"\(text)\" (\(element.selector))"
                }
            }

            if !context.forms.isEmpty {
                prompt += "\n\nForms on page:"
                for form in context.forms {
                    prompt += "\n- Form: \(form.name ?? "unnamed") with \(form.fieldCount) fields"
                }
            }
        }

        prompt += """


            Return ONLY a valid JSON array of actions, no explanation. Example:
            [{"action": "click", "target": "Login"}]
            """

        return prompt
    }

    /// Send request to Claude API
    private func sendRequest(prompt: String) async throws -> String {
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

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": prompt]
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
            return [.unknown(instruction: "Failed to parse LLM response")]
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
            guard let seconds = dict["seconds"] as? Double else { return nil }
            return .wait(seconds: seconds)

        default:
            return nil
        }
    }

    private func targetFromString(_ target: String) -> ElementTarget {
        if target.hasPrefix("#") || target.hasPrefix(".") || target.contains("[") {
            return .selector(target)
        }
        return .text(target)
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
