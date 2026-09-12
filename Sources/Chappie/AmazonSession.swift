import AppKit
import WebKit

/// A dedicated Amazon browser whose default WebKit data store persists cookies
/// across Chappie launches. Credentials remain in Amazon's web view and are not
/// read or stored by Chappie itself.
@MainActor
final class AmazonSessionWindowController: NSObject, WKNavigationDelegate {
    static let shared = AmazonSessionWindowController()

    private var window: NSWindow?
    private var webView: WKWebView?

    func show(_ url: URL = URL(string: "https://www.amazon.co.jp/")!) {
        let webView = ensureWindow()
        if webView.url == nil || url.path != "/" {
            webView.load(URLRequest(url: url))
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func ensureWindow() -> WKWebView {
        if let webView { return webView }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "Chappie/0.3"
        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.navigationDelegate = self
        browser.allowsBackForwardNavigationGestures = true

        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1040, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "チャッピー — Amazon"
        window.contentView = browser
        window.center()
        window.isReleasedWhenClosed = false
        self.webView = browser
        self.window = window
        return browser
    }
}
