import Foundation
import WebKit

/// Handles JavaScript injection and DOM interaction
class PageInteractor {
    private weak var webView: WKWebView?

    init(webView: WKWebView? = nil) {
        self.webView = webView
    }

    func setWebView(_ webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - Page Analysis

    /// Analyze the current page and return all interactive elements
    func analyzePage() async throws -> PageAnalysis {
        guard let webView = webView else {
            throw InteractorError.noWebView
        }

        let script = PageAnalyzer.script
        let result = try await webView.evaluateJavaScript(script)

        guard let dict = result as? [String: Any] else {
            throw InteractorError.invalidResponse
        }

        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(PageAnalysis.self, from: data)
    }

    // MARK: - Action Execution

    /// Execute a browser action
    func execute(_ action: BrowserAction) async throws -> ActionResult {
        switch action {
        case .navigate(let url):
            return try await navigate(to: url)

        case .click(let target):
            return try await click(target: target)

        case .type(let text, let target):
            return try await type(text: text, in: target)

        case .scroll(let direction):
            return try await scroll(direction: direction)

        case .select(let option, let target):
            return try await select(option: option, in: target)

        case .submit(let formTarget):
            return try await submit(form: formTarget)

        case .back:
            return await goBack()

        case .forward:
            return await goForward()

        case .refresh:
            return await reload()

        case .wait(let seconds):
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return .success("Waited \(seconds) seconds")

        case .unknown(let instruction):
            return .failure("Unknown command: \(instruction)")
        }
    }

    // MARK: - Navigation

    private func navigate(to urlString: String) async throws -> ActionResult {
        guard let webView = webView else {
            throw InteractorError.noWebView
        }

        guard let url = URL(string: urlString) else {
            return .failure("Invalid URL: \(urlString)")
        }

        await MainActor.run {
            webView.load(URLRequest(url: url))
        }

        return .success("Navigating to \(urlString)")
    }

    private func goBack() async -> ActionResult {
        guard let webView = webView else {
            return .failure("No web view")
        }

        let canGoBack = await MainActor.run { webView.canGoBack }
        if canGoBack {
            await MainActor.run { webView.goBack() }
            return .success("Went back")
        }
        return .failure("Cannot go back")
    }

    private func goForward() async -> ActionResult {
        guard let webView = webView else {
            return .failure("No web view")
        }

        let canGoForward = await MainActor.run { webView.canGoForward }
        if canGoForward {
            await MainActor.run { webView.goForward() }
            return .success("Went forward")
        }
        return .failure("Cannot go forward")
    }

    private func reload() async -> ActionResult {
        guard let webView = webView else {
            return .failure("No web view")
        }

        await MainActor.run { webView.reload() }
        return .success("Reloading page")
    }

    // MARK: - Click

    private func click(target: ElementTarget) async throws -> ActionResult {
        let selector = try selectorForTarget(target)
        let script = """
            (function() {
                const element = \(selector);
                if (!element) {
                    return { success: false, message: 'Element not found' };
                }
                element.click();
                return { success: true, message: 'Clicked element' };
            })()
            """

        return try await executeScript(script)
    }

    // MARK: - Type

    private func type(text: String, in target: ElementTarget) async throws -> ActionResult {
        let selector = try selectorForTarget(target)
        let escapedText = text.replacingOccurrences(of: "'", with: "\\'")
        let script = """
            (function() {
                const element = \(selector);
                if (!element) {
                    return { success: false, message: 'Element not found' };
                }
                element.focus();
                element.value = '\(escapedText)';
                element.dispatchEvent(new Event('input', { bubbles: true }));
                element.dispatchEvent(new Event('change', { bubbles: true }));
                return { success: true, message: 'Typed text in element' };
            })()
            """

        return try await executeScript(script)
    }

    // MARK: - Scroll

    private func scroll(direction: ScrollDirection) async throws -> ActionResult {
        let script: String
        switch direction {
        case .up:
            script = "window.scrollBy(0, -300); ({ success: true, message: 'Scrolled up' })"
        case .down:
            script = "window.scrollBy(0, 300); ({ success: true, message: 'Scrolled down' })"
        case .top:
            script = "window.scrollTo(0, 0); ({ success: true, message: 'Scrolled to top' })"
        case .bottom:
            script = "window.scrollTo(0, document.body.scrollHeight); ({ success: true, message: 'Scrolled to bottom' })"
        case .toElement:
            return .failure("Scroll to element requires a target")
        }

        return try await executeScript(script)
    }

    // MARK: - Select

    private func select(option: String, in target: ElementTarget) async throws -> ActionResult {
        let selector = try selectorForTarget(target)
        let escapedOption = option.replacingOccurrences(of: "'", with: "\\'")
        let script = """
            (function() {
                const select = \(selector);
                if (!select || select.tagName !== 'SELECT') {
                    return { success: false, message: 'Select element not found' };
                }
                const options = Array.from(select.options);
                const option = options.find(o =>
                    o.text.toLowerCase().includes('\(escapedOption.lowercased())') ||
                    o.value.toLowerCase().includes('\(escapedOption.lowercased())')
                );
                if (!option) {
                    return { success: false, message: 'Option not found: \(escapedOption)' };
                }
                select.value = option.value;
                select.dispatchEvent(new Event('change', { bubbles: true }));
                return { success: true, message: 'Selected: ' + option.text };
            })()
            """

        return try await executeScript(script)
    }

    // MARK: - Submit

    private func submit(form formTarget: ElementTarget?) async throws -> ActionResult {
        let script: String

        if let target = formTarget {
            let selector = try selectorForTarget(target)
            script = """
                (function() {
                    let form = \(selector);
                    if (form && form.tagName !== 'FORM') {
                        form = form.closest('form');
                    }
                    if (!form) {
                        return { success: false, message: 'Form not found' };
                    }
                    form.submit();
                    return { success: true, message: 'Form submitted' };
                })()
                """
        } else {
            script = """
                (function() {
                    const form = document.querySelector('form');
                    if (!form) {
                        return { success: false, message: 'No form found on page' };
                    }
                    form.submit();
                    return { success: true, message: 'Form submitted' };
                })()
                """
        }

        return try await executeScript(script)
    }

    // MARK: - Helpers

    private func selectorForTarget(_ target: ElementTarget) throws -> String {
        switch target {
        case .text(let text):
            let escaped = text.replacingOccurrences(of: "'", with: "\\'")
            return """
                (function() {
                    const text = '\(escaped)'.toLowerCase();
                    // Try exact text match first
                    const xpath = `//*[normalize-space(text())='${text}' or normalize-space()='${text}']`;
                    let result = document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                    if (result) return result;

                    // Try contains text
                    const elements = document.querySelectorAll('a, button, input[type="submit"], [role="button"], [onclick]');
                    for (const el of elements) {
                        const elText = (el.textContent || el.value || el.getAttribute('aria-label') || '').toLowerCase();
                        if (elText.includes(text)) return el;
                    }

                    // Try partial match on all elements
                    const all = document.querySelectorAll('*');
                    for (const el of all) {
                        if (el.children.length === 0 || el.tagName === 'BUTTON' || el.tagName === 'A') {
                            const elText = (el.textContent || '').toLowerCase().trim();
                            if (elText === text || elText.includes(text)) return el;
                        }
                    }

                    return null;
                })()
                """

        case .selector(let selector):
            let escaped = selector.replacingOccurrences(of: "'", with: "\\'")
            return "document.querySelector('\(escaped)')"

        case .index(let idx):
            return "document.querySelectorAll('a, button, input, select, textarea')[\(idx)]"

        case .role(let role, let name):
            let escaped = role.replacingOccurrences(of: "'", with: "\\'")
            if let name = name {
                let escapedName = name.replacingOccurrences(of: "'", with: "\\'")
                return "document.querySelector('[role=\"\(escaped)\"][aria-label*=\"\(escapedName)\"], [role=\"\(escaped)\"]:contains(\"\(escapedName)\")')"
            }
            return "document.querySelector('[role=\"\(escaped)\"]')"

        case .placeholder(let placeholder):
            let escaped = placeholder.replacingOccurrences(of: "'", with: "\\'")
            return """
                document.querySelector('input[placeholder*=\"\(escaped)\" i], textarea[placeholder*=\"\(escaped)\" i]')
                """

        case .label(let label):
            let escaped = label.replacingOccurrences(of: "'", with: "\\'")
            return """
                (function() {
                    const text = '\(escaped)'.toLowerCase();
                    // Try label element
                    const labels = document.querySelectorAll('label');
                    for (const label of labels) {
                        if (label.textContent.toLowerCase().includes(text)) {
                            const forId = label.getAttribute('for');
                            if (forId) return document.getElementById(forId);
                            return label.querySelector('input, textarea, select');
                        }
                    }
                    // Try name attribute
                    return document.querySelector(`input[name*="${text}" i], textarea[name*="${text}" i], select[name*="${text}" i]`);
                })()
                """
        }
    }

    private func executeScript(_ script: String) async throws -> ActionResult {
        guard let webView = webView else {
            throw InteractorError.noWebView
        }

        let result = try await webView.evaluateJavaScript(script)

        if let dict = result as? [String: Any],
           let success = dict["success"] as? Bool,
           let message = dict["message"] as? String {
            return success ? .success(message) : .failure(message)
        }

        return .success()
    }
}

// MARK: - Errors

enum InteractorError: LocalizedError {
    case noWebView
    case invalidResponse
    case elementNotFound(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWebView:
            return "No web view available"
        case .invalidResponse:
            return "Invalid response from JavaScript"
        case .elementNotFound(let target):
            return "Element not found: \(target)"
        case .executionFailed(let reason):
            return "Execution failed: \(reason)"
        }
    }
}

// MARK: - Page Analyzer JavaScript

struct PageAnalyzer {
    static let script = """
        (function() {
            function getSelector(element) {
                if (element.id) return '#' + element.id;
                if (element === document.body) return 'body';

                let path = [];
                while (element && element.nodeType === Node.ELEMENT_NODE) {
                    let selector = element.tagName.toLowerCase();
                    if (element.id) {
                        selector = '#' + element.id;
                        path.unshift(selector);
                        break;
                    }
                    let sibling = element;
                    let nth = 1;
                    while (sibling = sibling.previousElementSibling) {
                        if (sibling.tagName === element.tagName) nth++;
                    }
                    if (nth > 1) selector += ':nth-of-type(' + nth + ')';
                    path.unshift(selector);
                    element = element.parentElement;
                }
                return path.join(' > ');
            }

            function isVisible(element) {
                const style = window.getComputedStyle(element);
                const rect = element.getBoundingClientRect();
                return style.display !== 'none' &&
                       style.visibility !== 'hidden' &&
                       style.opacity !== '0' &&
                       rect.width > 0 &&
                       rect.height > 0;
            }

            function isInteractive(element) {
                const tag = element.tagName.toLowerCase();
                const interactiveTags = ['a', 'button', 'input', 'select', 'textarea'];
                if (interactiveTags.includes(tag)) return true;
                if (element.getAttribute('role') === 'button') return true;
                if (element.getAttribute('onclick')) return true;
                if (element.getAttribute('tabindex') >= 0) return true;
                return false;
            }

            const interactiveSelectors = 'a, button, input, select, textarea, [role="button"], [onclick], [tabindex]';
            const elements = Array.from(document.querySelectorAll(interactiveSelectors)).map((el, idx) => {
                const rect = el.getBoundingClientRect();
                return {
                    id: 'el-' + idx,
                    tagName: el.tagName.toLowerCase(),
                    text: (el.textContent || '').trim().substring(0, 100),
                    placeholder: el.getAttribute('placeholder'),
                    ariaLabel: el.getAttribute('aria-label'),
                    role: el.getAttribute('role'),
                    href: el.getAttribute('href'),
                    type: el.getAttribute('type'),
                    name: el.getAttribute('name'),
                    className: el.className,
                    selector: getSelector(el),
                    isVisible: isVisible(el),
                    isInteractive: isInteractive(el),
                    rect: {
                        x: rect.x,
                        y: rect.y,
                        width: rect.width,
                        height: rect.height
                    }
                };
            });

            const forms = Array.from(document.querySelectorAll('form')).map((form, idx) => ({
                id: 'form-' + idx,
                name: form.getAttribute('name'),
                action: form.getAttribute('action'),
                method: form.getAttribute('method'),
                selector: getSelector(form),
                fieldCount: form.querySelectorAll('input, textarea, select').length
            }));

            return {
                url: window.location.href,
                title: document.title,
                elements: elements,
                forms: forms
            };
        })()
        """
}
