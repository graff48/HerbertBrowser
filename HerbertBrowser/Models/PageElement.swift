import Foundation

/// Represents a DOM element on the page
struct PageElement: Identifiable, Codable, Equatable {
    let id: String
    let tagName: String
    let text: String?
    let placeholder: String?
    let ariaLabel: String?
    let role: String?
    let href: String?
    let type: String?
    let name: String?
    let className: String?
    let selector: String
    let isVisible: Bool
    let isInteractive: Bool
    let rect: ElementRect

    var displayText: String {
        text ?? placeholder ?? ariaLabel ?? name ?? tagName
    }

    var elementType: ElementType {
        switch tagName.lowercased() {
        case "a":
            return .link
        case "button":
            return .button
        case "input":
            switch type?.lowercased() {
            case "submit":
                return .submitButton
            case "button":
                return .button
            case "checkbox":
                return .checkbox
            case "radio":
                return .radio
            case "text", "email", "password", "search", "tel", "url", "number":
                return .textInput
            default:
                return .textInput
            }
        case "textarea":
            return .textArea
        case "select":
            return .select
        case "img":
            return .image
        case "form":
            return .form
        default:
            if role == "button" || className?.contains("btn") == true {
                return .button
            }
            return .other
        }
    }
}

/// Rectangle representing element position and size
struct ElementRect: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var center: (x: Double, y: Double) {
        (x + width / 2, y + height / 2)
    }
}

/// Type classification for elements
enum ElementType: String, Codable {
    case link
    case button
    case submitButton
    case textInput
    case textArea
    case checkbox
    case radio
    case select
    case image
    case form
    case other
}

/// Page analysis result from JavaScript
struct PageAnalysis: Codable {
    let url: String
    let title: String
    let elements: [PageElement]
    let forms: [FormInfo]

    var interactiveElements: [PageElement] {
        elements.filter { $0.isInteractive && $0.isVisible }
    }

    var links: [PageElement] {
        elements.filter { $0.elementType == .link && $0.isVisible }
    }

    var buttons: [PageElement] {
        elements.filter {
            ($0.elementType == .button || $0.elementType == .submitButton) && $0.isVisible
        }
    }

    var inputs: [PageElement] {
        elements.filter {
            ($0.elementType == .textInput || $0.elementType == .textArea) && $0.isVisible
        }
    }
}

/// Form information
struct FormInfo: Codable, Equatable {
    let id: String
    let name: String?
    let action: String?
    let method: String?
    let selector: String
    let fieldCount: Int
}
