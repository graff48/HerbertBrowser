import SwiftUI
import UniformTypeIdentifiers

/// Main content view combining all browser components
struct ContentView: View {
    @EnvironmentObject var viewModel: BrowserViewModel
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            // Main browser content
            VStack(spacing: 0) {
                // Navigation bar at top
                NavigationBar()

                Divider()

                // Web content
                BrowserView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Instruction bar at bottom
                InstructionBar()
            }

            // Script panel (sidebar)
            if viewModel.showScriptPanel {
                Divider()
                ScriptPanel()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .overlay(
            // Drop indicator overlay
            Group {
                if isDropTargeted {
                    ZStack {
                        Color.accentColor.opacity(0.1)
                        VStack(spacing: 12) {
                            Image(systemName: "doc.badge.arrow.up")
                                .font(.system(size: 48))
                                .foregroundColor(.accentColor)
                            Text("Drop instruction file to load")
                                .font(.headline)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .ignoresSafeArea()
                }
            }
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard error == nil,
                  let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            // Check if it's a supported file type
            let supportedExtensions = ["md", "markdown", "txt", "json"]
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                DispatchQueue.main.async {
                    viewModel.statusMessage = "Unsupported file type. Use .md, .txt, or .json"
                }
                return
            }

            DispatchQueue.main.async {
                viewModel.importInstructionFile(from: url)
            }
        }

        return true
    }
}

#Preview {
    ContentView()
        .environmentObject(BrowserViewModel())
}
