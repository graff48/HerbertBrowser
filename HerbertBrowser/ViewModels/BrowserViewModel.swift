import Foundation
import SwiftUI
import WebKit
import Combine
import AppKit
import UniformTypeIdentifiers

/// Main view model managing browser state and actions
@MainActor
class BrowserViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var urlString: String = "https://example.com"
    @Published var currentURL: URL?
    @Published var pageTitle: String = ""
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var instruction: String = ""
    @Published var statusMessage: String = ""
    @Published var isExecuting: Bool = false
    @Published var focusURLBar: Bool = false
    @Published var focusInstructionBar: Bool = false

    // Script execution state
    @Published var isRunningScript: Bool = false
    @Published var currentScriptName: String = ""
    @Published var scriptProgress: (current: Int, total: Int) = (0, 0)
    @Published var scriptInstructions: [InstructionFileParser.Instruction] = []
    @Published var showScriptPanel: Bool = false

    // MARK: - Services

    private let commandParser = CommandParser()
    private let llmService = LLMService()
    private var pageInteractor = PageInteractor()
    private let fileParser = InstructionFileParser()

    // Script execution control
    private var scriptTask: Task<Void, Never>?
    private var isPaused: Bool = false

    // MARK: - WebView Reference

    private var webView: WKWebView?

    // MARK: - Initialization

    init() {
        // Load API key from UserDefaults if available
        if let apiKey = UserDefaults.standard.string(forKey: "claudeAPIKey") {
            llmService.setAPIKey(apiKey)
        }
    }

    // MARK: - WebView Setup

    func setWebView(_ webView: WKWebView) {
        self.webView = webView
        pageInteractor.setWebView(webView)
    }

    // MARK: - Navigation Actions

    func loadURL() {
        var urlToLoad = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add https:// if no scheme
        if !urlToLoad.hasPrefix("http://") && !urlToLoad.hasPrefix("https://") {
            urlToLoad = "https://" + urlToLoad
        }

        guard let url = URL(string: urlToLoad) else {
            statusMessage = "Invalid URL"
            return
        }

        webView?.load(URLRequest(url: url))
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    // MARK: - Page State Updates

    func updatePageState(url: URL?, title: String?, isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
        self.currentURL = url
        if let url = url {
            self.urlString = url.absoluteString
        }
        if let title = title {
            self.pageTitle = title
        }
        self.isLoading = isLoading
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }

    // MARK: - Instruction Execution

    func executeInstruction() {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isExecuting = true
        statusMessage = "Executing..."

        Task {
            await executeInstructionAsync(trimmed)
        }
    }

    private func executeInstructionAsync(_ instruction: String) async {
        do {
            // First try local parsing
            let action = commandParser.parse(instruction)

            if case .unknown = action {
                // Unknown command - try LLM if configured
                if llmService.isConfigured {
                    await executeLLMInstruction(instruction)
                } else {
                    statusMessage = "Unknown command. Try: go to [url], click [element], type [text] in [field]"
                    isExecuting = false
                }
            } else {
                // Execute locally parsed action
                let result = try await pageInteractor.execute(action)
                statusMessage = result.message
                isExecuting = false

                if result.success {
                    // Clear instruction on success
                    self.instruction = ""
                }
            }
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isExecuting = false
        }
    }

    private func executeLLMInstruction(_ instruction: String) async {
        statusMessage = "Analyzing with Claude..."

        do {
            // Get page context
            let pageContext = try? await pageInteractor.analyzePage()

            // Get actions from LLM
            let actions = try await llmService.parseInstruction(instruction, pageContext: pageContext)

            if actions.isEmpty {
                statusMessage = "Could not determine actions for instruction"
                isExecuting = false
                return
            }

            // Execute each action
            for (index, action) in actions.enumerated() {
                statusMessage = "Executing step \(index + 1)/\(actions.count): \(action.description)"

                let result = try await pageInteractor.execute(action)

                if !result.success {
                    statusMessage = "Failed at step \(index + 1): \(result.message)"
                    isExecuting = false
                    return
                }

                // Small delay between actions
                if index < actions.count - 1 {
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            }

            statusMessage = "Completed \(actions.count) action(s)"
            self.instruction = ""

        } catch let error as LLMError {
            statusMessage = error.localizedDescription
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }

        isExecuting = false
    }

    // MARK: - Settings

    func updateAPIKey(_ key: String) {
        llmService.setAPIKey(key)
        UserDefaults.standard.set(key, forKey: "claudeAPIKey")
    }

    var isLLMConfigured: Bool {
        llmService.isConfigured
    }

    // MARK: - Script/File Execution

    /// Import and load an instruction file
    func importInstructionFile(from url: URL) {
        do {
            let script = try fileParser.parse(fileURL: url)

            if script.instructions.isEmpty {
                statusMessage = "No instructions found in file"
                return
            }

            currentScriptName = script.name
            scriptInstructions = script.instructions
            scriptProgress = (0, script.instructions.count)
            showScriptPanel = true
            statusMessage = "Loaded '\(script.name)' with \(script.instructions.count) instruction(s)"

        } catch {
            statusMessage = "Failed to load file: \(error.localizedDescription)"
        }
    }

    /// Start executing the loaded script
    func runScript() {
        guard !scriptInstructions.isEmpty else {
            statusMessage = "No script loaded"
            return
        }

        guard !isRunningScript else {
            statusMessage = "Script already running"
            return
        }

        isRunningScript = true
        isPaused = false
        scriptProgress = (0, scriptInstructions.count)

        scriptTask = Task {
            await executeScript()
        }
    }

    /// Pause script execution
    func pauseScript() {
        isPaused = true
        statusMessage = "Script paused"
    }

    /// Resume script execution
    func resumeScript() {
        isPaused = false
        statusMessage = "Script resumed"
    }

    /// Stop script execution
    func stopScript() {
        scriptTask?.cancel()
        scriptTask = nil
        isRunningScript = false
        isPaused = false
        statusMessage = "Script stopped"
    }

    /// Clear the loaded script
    func clearScript() {
        stopScript()
        scriptInstructions = []
        currentScriptName = ""
        scriptProgress = (0, 0)
        showScriptPanel = false
    }

    /// Execute the script instructions sequentially
    private func executeScript() async {
        let instructions = scriptInstructions

        for (index, instruction) in instructions.enumerated() {
            // Check for cancellation
            if Task.isCancelled {
                isRunningScript = false
                return
            }

            // Wait while paused
            while isPaused && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            if Task.isCancelled {
                isRunningScript = false
                return
            }

            // Update progress
            scriptProgress = (index + 1, instructions.count)

            // Show current instruction
            if let comment = instruction.comment {
                statusMessage = "[\(index + 1)/\(instructions.count)] \(comment): \(instruction.text)"
            } else {
                statusMessage = "[\(index + 1)/\(instructions.count)] \(instruction.text)"
            }

            // Execute the instruction
            let success = await executeSingleInstruction(instruction.text)

            if !success {
                // Pause on error
                isPaused = true
                statusMessage = "Error at step \(index + 1). Script paused."
                return
            }

            // Wait after instruction if specified
            if let waitTime = instruction.waitAfter {
                statusMessage = "Waiting \(waitTime)s..."
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            } else {
                // Default delay between instructions
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            }
        }

        // Script completed
        isRunningScript = false
        statusMessage = "Script '\(currentScriptName)' completed successfully"
    }

    /// Execute a single instruction and return success status
    private func executeSingleInstruction(_ instructionText: String) async -> Bool {
        do {
            let action = commandParser.parse(instructionText)

            if case .unknown = action {
                if llmService.isConfigured {
                    // Try LLM
                    let pageContext = try? await pageInteractor.analyzePage()
                    let actions = try await llmService.parseInstruction(instructionText, pageContext: pageContext)

                    for action in actions {
                        let result = try await pageInteractor.execute(action)
                        if !result.success {
                            return false
                        }
                    }
                    return true
                } else {
                    return false
                }
            } else {
                let result = try await pageInteractor.execute(action)
                return result.success
            }
        } catch {
            return false
        }
    }

    /// Open file picker for instruction files
    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .init(filenameExtension: "md")!,
            .init(filenameExtension: "txt")!,
            .init(filenameExtension: "json")!,
            .plainText
        ]
        panel.message = "Select an instruction file"
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            importInstructionFile(from: url)
        }
    }
}
