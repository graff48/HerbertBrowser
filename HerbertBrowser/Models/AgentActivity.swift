import Foundation
import SwiftUI

/// Represents an activity phase during agent execution
enum ActivityPhase: String, CaseIterable {
    case capturing
    case analyzing
    case thinking
    case planning
    case executing
    case waiting
    case success
    case error

    var icon: String {
        switch self {
        case .capturing: return "camera.fill"
        case .analyzing: return "eye.fill"
        case .thinking: return "brain"
        case .planning: return "list.bullet.clipboard"
        case .executing: return "play.circle.fill"
        case .waiting: return "clock.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .capturing: return .blue
        case .analyzing: return .purple
        case .thinking: return .orange
        case .planning: return .cyan
        case .executing: return .indigo
        case .waiting: return .gray
        case .success: return .green
        case .error: return .red
        }
    }

    var displayName: String {
        switch self {
        case .capturing: return "Capturing"
        case .analyzing: return "Analyzing"
        case .thinking: return "Thinking"
        case .planning: return "Planning"
        case .executing: return "Executing"
        case .waiting: return "Waiting"
        case .success: return "Success"
        case .error: return "Error"
        }
    }
}

/// Represents a single activity entry from the agent
struct AgentActivity: Identifiable {
    let id: UUID
    let timestamp: Date
    let phase: ActivityPhase
    let message: String
    let details: String?

    init(id: UUID = UUID(), timestamp: Date = Date(), phase: ActivityPhase, message: String, details: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.phase = phase
        self.message = message
        self.details = details
    }

    /// Formatted timestamp for display
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}
