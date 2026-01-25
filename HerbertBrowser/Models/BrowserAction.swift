import Foundation

/// Represents an action to be performed on the browser or page
enum BrowserAction: Equatable {
    case navigate(url: String)
    case click(target: ElementTarget)
    case type(text: String, target: ElementTarget)
    case scroll(direction: ScrollDirection)
    case select(option: String, target: ElementTarget)
    case submit(formTarget: ElementTarget?)
    case back
    case forward
    case refresh
    case wait(seconds: Double)
    case unknown(instruction: String)

    var description: String {
        switch self {
        case .navigate(let url):
            return "Navigate to \(url)"
        case .click(let target):
            return "Click \(target.description)"
        case .type(let text, let target):
            return "Type '\(text)' in \(target.description)"
        case .scroll(let direction):
            return "Scroll \(direction.rawValue)"
        case .select(let option, let target):
            return "Select '\(option)' in \(target.description)"
        case .submit(let formTarget):
            if let target = formTarget {
                return "Submit form \(target.description)"
            }
            return "Submit form"
        case .back:
            return "Go back"
        case .forward:
            return "Go forward"
        case .refresh:
            return "Refresh page"
        case .wait(let seconds):
            return "Wait \(seconds) seconds"
        case .unknown(let instruction):
            return "Unknown: \(instruction)"
        }
    }
}

/// Target for element selection
enum ElementTarget: Equatable {
    case text(String)           // Find by visible text
    case selector(String)       // CSS selector
    case index(Int)            // Index in list of matching elements
    case role(String, name: String?) // ARIA role with optional name
    case placeholder(String)    // Input placeholder text
    case label(String)         // Associated label text

    var description: String {
        switch self {
        case .text(let text):
            return "'\(text)'"
        case .selector(let selector):
            return "selector '\(selector)'"
        case .index(let idx):
            return "element at index \(idx)"
        case .role(let role, let name):
            if let name = name {
                return "\(role) named '\(name)'"
            }
            return "\(role)"
        case .placeholder(let placeholder):
            return "field with placeholder '\(placeholder)'"
        case .label(let label):
            return "field labeled '\(label)'"
        }
    }
}

/// Scroll direction
enum ScrollDirection: String, Equatable {
    case up
    case down
    case top
    case bottom
    case toElement
}

/// Result of executing an action
struct ActionResult {
    let success: Bool
    let message: String
    let data: [String: Any]?

    static func success(_ message: String = "Action completed", data: [String: Any]? = nil) -> ActionResult {
        ActionResult(success: true, message: message, data: data)
    }

    static func failure(_ message: String) -> ActionResult {
        ActionResult(success: false, message: message, data: nil)
    }
}
