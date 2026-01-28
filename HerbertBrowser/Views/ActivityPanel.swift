import SwiftUI

/// Panel showing real-time agent activity and reasoning
struct ActivityPanel: View {
    @EnvironmentObject var viewModel: BrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.accentColor)

                Text("Activity")
                    .font(.headline)

                // Activity count badge
                if !viewModel.activities.isEmpty {
                    Text("\(viewModel.activities.count)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }

                Spacer()

                // Clear button
                if !viewModel.activities.isEmpty {
                    Button(action: { viewModel.clearActivities() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear Activities")
                }

                // Close button
                Button(action: { viewModel.showActivityPanel = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close Panel")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Activity list
            if viewModel.activities.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)

                    Text("No Activity Yet")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Enter an instruction to see real-time agent activity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(viewModel.activities) { activity in
                            ActivityRow(activity: activity)
                                .id(activity.id)
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: viewModel.activities.count) { _, _ in
                        // Auto-scroll to latest activity
                        if let lastActivity = viewModel.activities.last {
                            withAnimation {
                                proxy.scrollTo(lastActivity.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

            // Footer - shows working indicator during execution
            HStack {
                if viewModel.isExecuting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)

                    Text("Agent working...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(viewModel.activities.isEmpty ? "Ready" : "Idle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !viewModel.activities.isEmpty {
                    Text("\(viewModel.activities.filter { $0.phase == .success }.count) success, \(viewModel.activities.filter { $0.phase == .error }.count) error")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

/// Single activity row in the panel
struct ActivityRow: View {
    let activity: AgentActivity
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                // Phase icon
                Image(systemName: activity.phase.icon)
                    .font(.system(size: 12))
                    .foregroundColor(activity.phase.color)
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 2) {
                    // Message
                    Text(activity.message)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineLimit(isExpanded ? nil : 2)

                    // Timestamp
                    Text(activity.formattedTime)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Expand button if has details
                if activity.details != nil {
                    Button(action: { withAnimation { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Expandable details
            if isExpanded, let details = activity.details {
                Text(details)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                    .padding(.leading, 24)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if activity.details != nil {
                withAnimation { isExpanded.toggle() }
            }
        }
    }
}

#Preview {
    ActivityPanel()
        .environmentObject(BrowserViewModel())
        .frame(height: 400)
}
