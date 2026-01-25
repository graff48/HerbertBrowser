import SwiftUI
import WebKit

/// SwiftUI wrapper for WKWebView
struct BrowserView: NSViewRepresentable {
    @EnvironmentObject var viewModel: BrowserViewModel

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Set the webView reference in the view model
        DispatchQueue.main.async {
            viewModel.setWebView(webView)
        }

        // Load initial URL
        if let url = URL(string: viewModel.urlString) {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // The view model handles navigation through the webView reference
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var viewModel: BrowserViewModel

        init(viewModel: BrowserViewModel) {
            self.viewModel = viewModel
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.updatePageState(
                    url: webView.url,
                    title: webView.title,
                    isLoading: true,
                    canGoBack: webView.canGoBack,
                    canGoForward: webView.canGoForward
                )
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.updatePageState(
                    url: webView.url,
                    title: webView.title,
                    isLoading: false,
                    canGoBack: webView.canGoBack,
                    canGoForward: webView.canGoForward
                )
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                viewModel.updatePageState(
                    url: webView.url,
                    title: webView.title,
                    isLoading: false,
                    canGoBack: webView.canGoBack,
                    canGoForward: webView.canGoForward
                )
                viewModel.statusMessage = "Load failed: \(error.localizedDescription)"
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                viewModel.updatePageState(
                    url: webView.url,
                    title: webView.title,
                    isLoading: false,
                    canGoBack: webView.canGoBack,
                    canGoForward: webView.canGoForward
                )
                viewModel.statusMessage = "Navigation failed: \(error.localizedDescription)"
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow all navigation
            decisionHandler(.allow)
        }
    }
}
