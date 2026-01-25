import SwiftUI

/// Panel showing loaded script instructions and execution controls
struct ScriptPanel: View {
    @EnvironmentObject var viewModel: BrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.accentColor)

                Text(viewModel.currentScriptName.isEmpty ? "No Script Loaded" : viewModel.currentScriptName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                // Progress indicator
                if viewModel.isRunningScript {
                    Text("\(viewModel.scriptProgress.current)/\(viewModel.scriptProgress.total)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                // Close button
                Button(action: { viewModel.showScriptPanel = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Instruction list
            if viewModel.scriptInstructions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)

                    Text("Drop an instruction file here")
                        .foregroundColor(.secondary)

                    Text("or use File > Open Instruction File (⌘O)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(Array(viewModel.scriptInstructions.enumerated()), id: \.offset) { index, instruction in
                            InstructionRow(
                                instruction: instruction,
                                index: index,
                                isCurrentStep: viewModel.isRunningScript && viewModel.scriptProgress.current == index + 1,
                                isCompleted: viewModel.scriptProgress.current > index + 1
                            )
                            .id(index)
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: viewModel.scriptProgress.current) { _, newValue in
                        if newValue > 0 {
                            withAnimation {
                                proxy.scrollTo(newValue - 1, anchor: .center)
                            }
                        }
                    }
                }
            }

            Divider()

            // Control buttons
            HStack(spacing: 12) {
                if viewModel.isRunningScript {
                    // Running state controls
                    Button(action: { viewModel.stopScript() }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    if viewModel.scriptProgress.current < viewModel.scriptProgress.total {
                        Button(action: {
                            // Toggle pause/resume handled by checking isPaused internally
                            // For now, we expose both buttons
                        }) {
                            Label("Pause", systemImage: "pause.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    // Idle state controls
                    Button(action: { viewModel.showOpenPanel() }) {
                        Label("Open", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    if !viewModel.scriptInstructions.isEmpty {
                        Button(action: { viewModel.runScript() }) {
                            Label("Run", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: { viewModel.clearScript() }) {
                            Label("Clear", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer()

                // Progress bar
                if !viewModel.scriptInstructions.isEmpty {
                    ProgressView(
                        value: Double(viewModel.scriptProgress.current),
                        total: Double(max(viewModel.scriptProgress.total, 1))
                    )
                    .frame(width: 100)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

/// Single instruction row in the script panel
struct InstructionRow: View {
    let instruction: InstructionFileParser.Instruction
    let index: Int
    let isCurrentStep: Bool
    let isCompleted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 24, height: 24)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else if isCurrentStep {
                    ProgressView()
                        .scaleEffect(0.5)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(instruction.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(isCurrentStep ? .primary : .secondary)
                    .lineLimit(2)

                if let comment = instruction.comment {
                    Text(comment)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }

                if let wait = instruction.waitAfter {
                    Text("wait \(String(format: "%.1f", wait))s")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .background(isCurrentStep ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }

    private var backgroundColor: Color {
        if isCompleted {
            return .green
        } else if isCurrentStep {
            return .accentColor
        } else {
            return Color(NSColor.controlBackgroundColor)
        }
    }
}

#Preview {
    ScriptPanel()
        .environmentObject(BrowserViewModel())
        .frame(height: 400)
}
