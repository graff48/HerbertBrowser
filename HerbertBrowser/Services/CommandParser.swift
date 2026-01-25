import Foundation

/// Rule-based parser for converting natural language instructions to BrowserActions
class CommandParser {

    /// Parse an instruction string into a BrowserAction
    func parse(_ instruction: String) -> BrowserAction {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Navigation commands
        if let action = parseNavigationCommand(trimmed, original: instruction) {
            return action
        }

        // Click commands
        if let action = parseClickCommand(trimmed, original: instruction) {
            return action
        }

        // Type commands
        if let action = parseTypeCommand(trimmed, original: instruction) {
            return action
        }

        // Scroll commands
        if let action = parseScrollCommand(trimmed) {
            return action
        }

        // Select commands
        if let action = parseSelectCommand(trimmed, original: instruction) {
            return action
        }

        // Submit commands
        if let action = parseSubmitCommand(trimmed) {
            return action
        }

        // Wait commands
        if let action = parseWaitCommand(trimmed) {
            return action
        }

        // Simple navigation
        if trimmed == "back" || trimmed == "go back" {
            return .back
        }
        if trimmed == "forward" || trimmed == "go forward" {
            return .forward
        }
        if trimmed == "refresh" || trimmed == "reload" {
            return .refresh
        }

        return .unknown(instruction: instruction)
    }

    // MARK: - Navigation Parsing

    private func parseNavigationCommand(_ input: String, original: String) -> BrowserAction? {
        // Patterns: "go to [url]", "navigate to [url]", "open [url]", "visit [url]"
        let patterns = [
            #"^(?:go to|navigate to|open|visit)\s+(.+)$"#,
            #"^(?:go|nav|open)\s+(.+)$"#
        ]

        for pattern in patterns {
            if let match = input.firstMatch(of: try! Regex(pattern)),
               let urlPart = match.output[1].substring {
                let url = normalizeURL(String(urlPart))
                return .navigate(url: url)
            }
        }

        // Direct URL input
        if input.hasPrefix("http://") || input.hasPrefix("https://") {
            return .navigate(url: input)
        }

        // Looks like a domain
        if input.contains(".") && !input.contains(" ") {
            return .navigate(url: normalizeURL(input))
        }

        return nil
    }

    private func normalizeURL(_ url: String) -> String {
        var result = url.trimmingCharacters(in: .whitespacesAndNewlines)

        if !result.hasPrefix("http://") && !result.hasPrefix("https://") {
            result = "https://" + result
        }

        return result
    }

    // MARK: - Click Parsing

    private func parseClickCommand(_ input: String, original: String) -> BrowserAction? {
        // Patterns: "click [target]", "click on [target]", "press [target]", "tap [target]"
        let patterns = [
            #"^(?:click|press|tap)\s+(?:on\s+)?(?:the\s+)?(.+)$"#,
            #"^(?:click|press|tap)\s+(.+)$"#
        ]

        for pattern in patterns {
            if let match = input.firstMatch(of: try! Regex(pattern)),
               let targetPart = match.output[1].substring {
                let target = parseElementTarget(String(targetPart), from: original)
                return .click(target: target)
            }
        }

        return nil
    }

    // MARK: - Type Parsing

    private func parseTypeCommand(_ input: String, original: String) -> BrowserAction? {
        // Patterns: "type [text] in [field]", "enter [text] in [field]", "fill [field] with [text]"

        // "type [text] in [field]" or "enter [text] in [field]"
        let typeInPattern = #"^(?:type|enter|input)\s+[\"']?(.+?)[\"']?\s+(?:in|into|in the)\s+(.+)$"#
        if let match = input.firstMatch(of: try! Regex(typeInPattern)),
           let textPart = match.output[1].substring,
           let fieldPart = match.output[2].substring {
            // Get original case text
            let text = extractOriginalText(String(textPart), from: original)
            let target = parseElementTarget(String(fieldPart), from: original)
            return .type(text: text, target: target)
        }

        // "fill [field] with [text]"
        let fillWithPattern = #"^fill\s+(?:the\s+)?(.+?)\s+with\s+[\"']?(.+?)[\"']?$"#
        if let match = input.firstMatch(of: try! Regex(fillWithPattern)),
           let fieldPart = match.output[1].substring,
           let textPart = match.output[2].substring {
            let text = extractOriginalText(String(textPart), from: original)
            let target = parseElementTarget(String(fieldPart), from: original)
            return .type(text: text, target: target)
        }

        // "type [text]" (into focused element)
        let simpleTypePattern = #"^(?:type|enter)\s+[\"']?(.+?)[\"']?$"#
        if let match = input.firstMatch(of: try! Regex(simpleTypePattern)),
           let textPart = match.output[1].substring {
            let text = extractOriginalText(String(textPart), from: original)
            return .type(text: text, target: .selector(":focus"))
        }

        return nil
    }

    // MARK: - Scroll Parsing

    private func parseScrollCommand(_ input: String) -> BrowserAction? {
        if input.contains("scroll") || input.contains("go to top") || input.contains("go to bottom") {
            if input.contains("up") || input.contains("top") {
                if input.contains("to top") || input.contains("to the top") {
                    return .scroll(direction: .top)
                }
                return .scroll(direction: .up)
            }
            if input.contains("down") || input.contains("bottom") {
                if input.contains("to bottom") || input.contains("to the bottom") {
                    return .scroll(direction: .bottom)
                }
                return .scroll(direction: .down)
            }
            return .scroll(direction: .down) // Default to down
        }
        return nil
    }

    // MARK: - Select Parsing

    private func parseSelectCommand(_ input: String, original: String) -> BrowserAction? {
        // Patterns: "select [option] in [dropdown]", "choose [option] from [dropdown]"
        let patterns = [
            #"^(?:select|choose|pick)\s+[\"']?(.+?)[\"']?\s+(?:in|from|in the)\s+(.+)$"#
        ]

        for pattern in patterns {
            if let match = input.firstMatch(of: try! Regex(pattern)),
               let optionPart = match.output[1].substring,
               let dropdownPart = match.output[2].substring {
                let option = extractOriginalText(String(optionPart), from: original)
                let target = parseElementTarget(String(dropdownPart), from: original)
                return .select(option: option, target: target)
            }
        }

        return nil
    }

    // MARK: - Submit Parsing

    private func parseSubmitCommand(_ input: String) -> BrowserAction? {
        if input == "submit" || input == "submit form" || input == "submit the form" {
            return .submit(formTarget: nil)
        }

        let pattern = #"^submit\s+(?:the\s+)?(.+?)(?:\s+form)?$"#
        if let match = input.firstMatch(of: try! Regex(pattern)),
           let formPart = match.output[1].substring {
            return .submit(formTarget: .text(String(formPart)))
        }

        return nil
    }

    // MARK: - Wait Parsing

    private func parseWaitCommand(_ input: String) -> BrowserAction? {
        let pattern = #"^wait\s+(\d+(?:\.\d+)?)\s*(?:seconds?|secs?|s)?$"#
        if let match = input.firstMatch(of: try! Regex(pattern)),
           let secondsPart = match.output[1].substring,
           let seconds = Double(String(secondsPart)) {
            return .wait(seconds: min(seconds, 30)) // Cap at 30 seconds
        }
        return nil
    }

    // MARK: - Helpers

    private func parseElementTarget(_ target: String, from original: String) -> ElementTarget {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)

        // CSS selector (starts with . # or contains special selector chars)
        if trimmed.hasPrefix("#") || trimmed.hasPrefix(".") ||
           trimmed.contains("[") || trimmed.contains(">") {
            return .selector(trimmed)
        }

        // Placeholder pattern: "field with placeholder [text]"
        let placeholderPattern = #"(?:field\s+with\s+)?placeholder\s+[\"']?(.+?)[\"']?$"#
        if let match = trimmed.firstMatch(of: try! Regex(placeholderPattern)),
           let placeholder = match.output[1].substring {
            return .placeholder(String(placeholder))
        }

        // Label pattern: "[text] field", "field labeled [text]"
        let labelPattern = #"(?:field\s+)?(?:labeled|labelled)\s+[\"']?(.+?)[\"']?$"#
        if let match = trimmed.firstMatch(of: try! Regex(labelPattern)),
           let label = match.output[1].substring {
            return .label(String(label))
        }

        // Common field names
        let fieldNames = ["email", "password", "username", "name", "search", "phone", "address"]
        for field in fieldNames {
            if trimmed == field || trimmed == "\(field) field" || trimmed == "the \(field) field" {
                return .label(field)
            }
        }

        // Remove common words and use as text search
        var cleanTarget = trimmed
            .replacingOccurrences(of: "the ", with: "")
            .replacingOccurrences(of: "button", with: "")
            .replacingOccurrences(of: "link", with: "")
            .replacingOccurrences(of: "field", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Get original case from instruction
        if let range = original.lowercased().range(of: cleanTarget) {
            let originalRange = Range(uncheckedBounds: (
                original.index(original.startIndex, offsetBy: original.distance(from: original.startIndex, to: range.lowerBound)),
                original.index(original.startIndex, offsetBy: original.distance(from: original.startIndex, to: range.upperBound))
            ))
            cleanTarget = String(original[originalRange])
        }

        return .text(cleanTarget.isEmpty ? trimmed : cleanTarget)
    }

    private func extractOriginalText(_ lowercased: String, from original: String) -> String {
        let searchText = lowercased.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = original.lowercased().range(of: searchText) {
            let originalRange = Range(uncheckedBounds: (
                original.index(original.startIndex, offsetBy: original.distance(from: original.startIndex, to: range.lowerBound)),
                original.index(original.startIndex, offsetBy: original.distance(from: original.startIndex, to: range.upperBound))
            ))
            return String(original[originalRange])
        }
        return lowercased
    }
}
