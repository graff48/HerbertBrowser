import SwiftUI
import AppKit

/// App delegate for handling file open events
class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: BrowserViewModel?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                DispatchQueue.main.async {
                    self.viewModel?.importInstructionFile(from: url)
                }
                break // Only handle first file
            }
        }
    }
}

@main
struct HerbertBrowserApp: App {
    @StateObject private var viewModel = BrowserViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onOpenURL { url in
                    // Handle file URLs opened via drag or open command
                    if url.isFileURL {
                        viewModel.importInstructionFile(from: url)
                    }
                }
                .onAppear {
                    // Check for command line arguments
                    appDelegate.viewModel = viewModel
                    checkCommandLineArgs()
                }
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    // Future: implement tabs
                }
                .keyboardShortcut("t", modifiers: .command)

                Divider()

                Button("Open Instruction File...") {
                    viewModel.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("Script") {
                Button("Open Instruction File...") {
                    viewModel.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("Run Script") {
                    viewModel.runScript()
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(viewModel.scriptInstructions.isEmpty || viewModel.isRunningScript)

                Button("Pause Script") {
                    viewModel.pauseScript()
                }
                .disabled(!viewModel.isRunningScript)

                Button("Resume Script") {
                    viewModel.resumeScript()
                }
                .disabled(!viewModel.isRunningScript)

                Button("Stop Script") {
                    viewModel.stopScript()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!viewModel.isRunningScript)

                Divider()

                Button("Clear Script") {
                    viewModel.clearScript()
                }
                .disabled(viewModel.scriptInstructions.isEmpty)

                Divider()

                Button(viewModel.showScriptPanel ? "Hide Script Panel" : "Show Script Panel") {
                    viewModel.showScriptPanel.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            CommandMenu("Browser") {
                Button("Go Back") {
                    viewModel.goBack()
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Go Forward") {
                    viewModel.goForward()
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("Reload") {
                    viewModel.reload()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Focus URL Bar") {
                    viewModel.focusURLBar = true
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Focus Instruction Bar") {
                    viewModel.focusInstructionBar = true
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(viewModel)
        }
    }
}

extension HerbertBrowserApp {
    func checkCommandLineArgs() {
        let args = CommandLine.arguments
        // Skip first argument (executable path)
        for arg in args.dropFirst() {
            // Check if it's a file path
            if arg.hasPrefix("/") || arg.hasPrefix("~") {
                let path = NSString(string: arg).expandingTildeInPath
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: path) {
                    // Delay slightly to ensure the app is fully initialized
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.viewModel.importInstructionFile(from: url)
                    }
                    break
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var viewModel: BrowserViewModel
    @AppStorage("claudeAPIKey") private var apiKey: String = ""

    var body: some View {
        Form {
            Section("LLM Integration") {
                SecureField("Claude API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Text("Enter your Claude API key to enable advanced natural language commands. Without an API key, only basic rule-based commands are available.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 450, height: 150)
        .onChange(of: apiKey) { _, newValue in
            viewModel.updateAPIKey(newValue)
        }
    }
}
