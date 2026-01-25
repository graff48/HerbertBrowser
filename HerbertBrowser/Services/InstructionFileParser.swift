import Foundation

/// Parser for extracting instructions from various file formats
class InstructionFileParser {

    /// Supported file types
    enum FileType: String, CaseIterable {
        case markdown = "md"
        case text = "txt"
        case json = "json"

        static var allExtensions: [String] {
            allCases.map { $0.rawValue }
        }
    }

    /// Parsed instruction script
    struct InstructionScript {
        let name: String
        let instructions: [Instruction]
        let metadata: [String: String]
    }

    /// Single instruction with optional metadata
    struct Instruction {
        let text: String
        let comment: String?
        let waitAfter: Double?

        init(text: String, comment: String? = nil, waitAfter: Double? = nil) {
            self.text = text
            self.comment = comment
            self.waitAfter = waitAfter
        }
    }

    /// Parse a file at the given URL
    func parse(fileURL: URL) throws -> InstructionScript {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension.lowercased()

        switch fileExtension {
        case "md", "markdown":
            return try parseMarkdown(content, name: fileName)
        case "txt":
            return try parseText(content, name: fileName)
        case "json":
            return try parseJSON(content, name: fileName)
        default:
            // Try to parse as text
            return try parseText(content, name: fileName)
        }
    }

    // MARK: - Markdown Parsing

    private func parseMarkdown(_ content: String, name: String) throws -> InstructionScript {
        var instructions: [Instruction] = []
        var metadata: [String: String] = [:]
        var scriptName = name

        let lines = content.components(separatedBy: .newlines)
        var inCodeBlock = false
        var codeBlockLanguage: String?
        var pendingComment: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check for code block boundaries
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    inCodeBlock = false
                    codeBlockLanguage = nil
                } else {
                    inCodeBlock = true
                    codeBlockLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            // Skip content inside code blocks (unless it's an instruction block)
            if inCodeBlock && codeBlockLanguage != "instructions" && codeBlockLanguage != "herbert" {
                continue
            }

            // Parse YAML-style frontmatter metadata
            if trimmed.hasPrefix("---") {
                continue
            }

            // Extract title from H1
            if trimmed.hasPrefix("# ") && scriptName == name {
                scriptName = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                continue
            }

            // Skip other headers and empty lines
            if trimmed.hasPrefix("#") || trimmed.isEmpty {
                continue
            }

            // Comments (lines starting with //, >, or HTML comments)
            if trimmed.hasPrefix("//") {
                pendingComment = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if trimmed.hasPrefix(">") && !trimmed.hasPrefix(">>") {
                // Blockquote as comment
                pendingComment = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                continue
            }

            // Parse list items as instructions
            if let instruction = parseListItem(trimmed) {
                var inst = instruction
                if let comment = pendingComment {
                    inst = Instruction(text: instruction.text, comment: comment, waitAfter: instruction.waitAfter)
                    pendingComment = nil
                }
                instructions.append(inst)
                continue
            }

            // Parse metadata (key: value format)
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty && !value.isEmpty && key.count < 30 {
                    metadata[key] = value
                }
            }
        }

        return InstructionScript(name: scriptName, instructions: instructions, metadata: metadata)
    }

    private func parseListItem(_ line: String) -> Instruction? {
        var text = line

        // Remove list markers: -, *, numbered (1., 2., etc.)
        if text.hasPrefix("- ") {
            text = String(text.dropFirst(2))
        } else if text.hasPrefix("* ") {
            text = String(text.dropFirst(2))
        } else if let match = text.firstMatch(of: /^\d+\.\s+/) {
            text = String(text[match.range.upperBound...])
        } else {
            // Not a list item
            return nil
        }

        text = text.trimmingCharacters(in: .whitespaces)

        // Skip empty items or items that look like sub-headers
        if text.isEmpty || text.hasPrefix("[") && text.hasSuffix("]") {
            return nil
        }

        // Check for wait annotation: `wait 2s` or `(wait: 2)`
        var waitAfter: Double?
        if let waitMatch = text.firstMatch(of: /\s*\(wait:\s*(\d+(?:\.\d+)?)\s*s?\)\s*$/) {
            if let seconds = Double(waitMatch.output.1) {
                waitAfter = seconds
            }
            text = String(text[..<waitMatch.range.lowerBound])
        } else if let waitMatch = text.firstMatch(of: /\s*[Ww][Aa][Ii][Tt]\s+(\d+(?:\.\d+)?)\s*s?\s*$/) {
            if let seconds = Double(waitMatch.output.1) {
                waitAfter = seconds
            }
            text = String(text[..<waitMatch.range.lowerBound])
        }

        text = text.trimmingCharacters(in: .whitespaces)

        // Remove surrounding backticks if present
        if text.hasPrefix("`") && text.hasSuffix("`") {
            text = String(text.dropFirst().dropLast())
        }

        guard !text.isEmpty else { return nil }

        return Instruction(text: text, waitAfter: waitAfter)
    }

    // MARK: - Plain Text Parsing

    private func parseText(_ content: String, name: String) throws -> InstructionScript {
        var instructions: [Instruction] = []
        var pendingComment: String?

        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmed.isEmpty {
                pendingComment = nil
                continue
            }

            // Comments
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") {
                let commentText = trimmed.hasPrefix("#") ?
                    String(trimmed.dropFirst()) : String(trimmed.dropFirst(2))
                pendingComment = commentText.trimmingCharacters(in: .whitespaces)
                continue
            }

            // Each non-empty, non-comment line is an instruction
            let instruction = Instruction(text: trimmed, comment: pendingComment)
            instructions.append(instruction)
            pendingComment = nil
        }

        return InstructionScript(name: name, instructions: instructions, metadata: [:])
    }

    // MARK: - JSON Parsing

    private func parseJSON(_ content: String, name: String) throws -> InstructionScript {
        guard let data = content.data(using: .utf8) else {
            throw ParserError.invalidContent
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParserError.invalidJSON
        }

        let scriptName = json["name"] as? String ?? name
        var metadata: [String: String] = [:]

        if let meta = json["metadata"] as? [String: String] {
            metadata = meta
        }

        var instructions: [Instruction] = []

        if let instructionList = json["instructions"] as? [[String: Any]] {
            for item in instructionList {
                guard let text = item["instruction"] as? String ?? item["text"] as? String else {
                    continue
                }
                let comment = item["comment"] as? String
                let waitAfter = item["wait"] as? Double ?? item["waitAfter"] as? Double
                instructions.append(Instruction(text: text, comment: comment, waitAfter: waitAfter))
            }
        } else if let instructionList = json["instructions"] as? [String] {
            instructions = instructionList.map { Instruction(text: $0) }
        }

        return InstructionScript(name: scriptName, instructions: instructions, metadata: metadata)
    }
}

// MARK: - Errors

enum ParserError: LocalizedError {
    case invalidContent
    case invalidJSON
    case noInstructions

    var errorDescription: String? {
        switch self {
        case .invalidContent:
            return "Could not read file content"
        case .invalidJSON:
            return "Invalid JSON format"
        case .noInstructions:
            return "No instructions found in file"
        }
    }
}
