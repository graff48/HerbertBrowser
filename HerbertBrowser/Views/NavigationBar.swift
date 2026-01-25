import SwiftUI

/// Navigation bar with URL field and back/forward/refresh buttons
struct NavigationBar: View {
    @EnvironmentObject var viewModel: BrowserViewModel
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Back button
            Button(action: { viewModel.goBack() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.canGoBack)
            .help("Go Back (⌘[)")

            // Forward button
            Button(action: { viewModel.goForward() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.canGoForward)
            .help("Go Forward (⌘])")

            // Refresh/Stop button
            Button(action: { viewModel.reload() }) {
                if viewModel.isLoading {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.borderless)
            .help(viewModel.isLoading ? "Stop Loading" : "Reload (⌘R)")

            // URL field
            HStack {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .opacity(viewModel.urlString.hasPrefix("https://") ? 1 : 0)
                }

                TextField("Enter URL", text: $viewModel.urlString)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isURLFieldFocused)
                    .onSubmit {
                        viewModel.loadURL()
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isURLFieldFocused ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: viewModel.focusURLBar) { _, newValue in
            if newValue {
                isURLFieldFocused = true
                viewModel.focusURLBar = false
            }
        }
    }
}

#Preview {
    NavigationBar()
        .environmentObject(BrowserViewModel())
        .frame(width: 800)
}
