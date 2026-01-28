import SwiftUI

/// Instruction input bar for natural language commands
struct InstructionBar: View {
    @EnvironmentObject var viewModel: BrowserViewModel
    @FocusState private var isInstructionFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                // LLM status indicator
                Circle()
                    .fill(viewModel.isLLMConfigured ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .help(viewModel.isLLMConfigured ?
                          "Claude API configured - advanced commands available" :
                          "Claude API not configured - basic commands only")

                // Instruction field
                HStack {
                    Image(systemName: "text.cursor")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))

                    TextField("Enter instruction (e.g., 'click Login', 'go to google.com')", text: $viewModel.instruction)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isInstructionFieldFocused)
                        .disabled(viewModel.isExecuting)
                        .onSubmit {
                            viewModel.executeInstruction()
                        }

                    if viewModel.isExecuting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isInstructionFieldFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                )

                // Execute button
                Button(action: { viewModel.executeInstruction() }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.instruction.isEmpty || viewModel.isExecuting)
                .help("Execute Instruction (Return)")

                // Activity panel toggle
                Button(action: { viewModel.showActivityPanel.toggle() }) {
                    Image(systemName: viewModel.showActivityPanel ? "brain.head.profile.fill" : "brain.head.profile")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .help(viewModel.showActivityPanel ? "Hide Activity Panel" : "Show Activity Panel")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Status bar
            if !viewModel.statusMessage.isEmpty {
                HStack {
                    Text(viewModel.statusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Button(action: { viewModel.statusMessage = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: viewModel.focusInstructionBar) { _, newValue in
            if newValue {
                isInstructionFieldFocused = true
                viewModel.focusInstructionBar = false
            }
        }
    }
}

#Preview {
    InstructionBar()
        .environmentObject(BrowserViewModel())
        .frame(width: 800)
}
