import AppKit
import WebKit

struct AmazonQuote {
    let title: String
    let asin: String
    let quantity: Int
    let unitPriceYen: Int
    let shippingYen: Int
    var totalYen: Int { unitPriceYen * quantity + shippingYen }
}

struct AmazonPurchaseResult {
    let title: String
    let totalYen: Int
    let delivery: String
    let orderNumber: String
}

/// A dedicated Amazon browser whose default WebKit data store persists cookies
/// across Chappie launches. Credentials remain in Amazon's web view and are not
/// read or stored by Chappie itself.
@MainActor
final class AmazonSessionWindowController: NSObject, WKNavigationDelegate {
    static let shared = AmazonSessionWindowController()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var pendingQuote: (quantity: Int, attempts: Int, completion: (Result<AmazonQuote, Error>) -> Void)?
    private var pendingCheckout: Checkout?

    private struct Checkout {
        enum Phase { case product, checkout, submitted }
        let expectedASIN: String?
        let expectedName: String
        let quantity: Int
        let approvedTotalYen: Int
        var phase: Phase
        var attempts: Int
        let completion: (Result<AmazonPurchaseResult, Error>) -> Void
    }

    enum SessionError: LocalizedError {
        case notLoggedIn, unavailable, subscriptionOnly, unreadable, totalChanged(Int), checkoutUnavailable, confirmationUnknown
        var errorDescription: String? {
            switch self {
            case .notLoggedIn: return "Amazonへのログインが必要です。"
            case .unavailable: return "商品が在庫切れか、通常購入できません。"
            case .subscriptionOnly: return "定期購入しか選べないため停止しました。"
            case .unreadable: return "商品名・価格・配送料を確認できませんでした。"
            case .totalChanged(let total): return "注文直前の合計が¥\(total.formatted())に変わったため停止しました。"
            case .checkoutUnavailable: return "Amazonの注文確認画面を操作できませんでした。"
            case .confirmationUnknown: return "注文結果を確認できませんでした。Amazonの注文履歴を確認してください。"
            }
        }
    }

    func show(_ url: URL = URL(string: "https://www.amazon.co.jp/")!) {
        let webView = ensureWindow()
        if webView.url == nil || url.path != "/" {
            webView.load(URLRequest(url: url))
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func quote(_ url: URL, quantity: Int, completion: @escaping (Result<AmazonQuote, Error>) -> Void) {
        pendingQuote = (quantity, 0, completion)
        show(url)
        scheduleQuoteRead()
    }

    private func scheduleQuoteRead(after delay: Double = 1.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.readQuote() }
    }

    private func readQuote() {
        guard let webView, var pending = pendingQuote else { return }
        pending.attempts += 1
        pendingQuote = pending
        let script = #"""
        (() => {
          const clean = value => (value || '').replace(/\s+/g, ' ').trim();
          const account = clean(document.querySelector('#nav-link-accountList-nav-line-1')?.textContent || document.querySelector('#nav-link-accountList')?.textContent);
          const title = clean(document.querySelector('#productTitle')?.textContent);
          const asin = document.querySelector('#ASIN')?.value || document.querySelector('[data-asin]')?.getAttribute('data-asin') || '';
          const availability = clean(document.querySelector('#availability')?.textContent);
          const pageText = clean(document.body?.innerText);
          const hasBuyNow = [...document.querySelectorAll('input, button, [role="button"]')].some(element =>
            /今すぐ買う|buy now/i.test(clean(element.value || element.innerText || element.getAttribute('aria-label'))) ||
            /buy-now/i.test(`${element.id || ''} ${element.name || ''}`)
          );
          const candidates = [...document.querySelectorAll('#apex_desktop button, #apex_desktop [role="button"], #buybox button, #buybox [role="button"], #buybox_feature_div')];
          let box = candidates.find(element => /1回限りの購入/.test(clean(element.innerText)));
          if (!box) box = document.querySelector('#buybox, #apex_desktop');
          const boxText = clean(box?.innerText);
          let priceText = clean(box?.querySelector('.a-price .a-offscreen')?.textContent || box?.querySelector('#price_inside_buybox')?.textContent);
          if (!priceText) priceText = clean(document.querySelector('#corePrice_feature_div .a-price .a-offscreen')?.textContent || document.querySelector('.a-price .a-offscreen')?.textContent);
          const priceMatch = priceText.match(/[￥¥]\s*([0-9,]+)/) || boxText.match(/[￥¥]\s*([0-9,]+)/);
          let shipping = 0;
          const delivery = clean(document.querySelector('#mir-layout-DELIVERY_BLOCK-slot-PRIMARY_DELIVERY_MESSAGE_LARGE')?.textContent || document.querySelector('#deliveryBlockMessage')?.textContent || boxText);
          if (!/無料配送|配送料無料/.test(delivery)) {
            const shippingMatch = delivery.match(/(?:配送料|送料)[^￥¥]{0,20}[￥¥]\s*([0-9,]+)/);
            if (shippingMatch) shipping = Number(shippingMatch[1].replace(/,/g, ''));
          }
          return {
            account,
            title,
            asin,
            availability,
            hasOneTime: (/1回限りの購入/.test(pageText) || hasBuyNow) ? 1 : 0,
            price: priceMatch ? Number(priceMatch[1].replace(/,/g, '')) : 0,
            shipping
          };
        })()
        """#
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            Task { @MainActor in
                guard let self, let current = self.pendingQuote else { return }
                guard let row = value as? [String: Any],
                      let title = row["title"] as? String,
                      let asin = row["asin"] as? String,
                      let priceNumber = row["price"] as? NSNumber else {
                    if current.attempts < 8 { self.scheduleQuoteRead(after: 0.75) }
                    else { self.finishQuote(.failure(SessionError.unreadable)) }
                    return
                }
                let account = row["account"] as? String ?? ""
                let availability = row["availability"] as? String ?? ""
                let price = priceNumber.intValue
                let shipping = (row["shipping"] as? NSNumber)?.intValue ?? 0
                if account.contains("ログイン") { self.finishQuote(.failure(SessionError.notLoggedIn)); return }
                if availability.contains("在庫切れ") || availability.contains("現在お取り扱い") { self.finishQuote(.failure(SessionError.unavailable)); return }
                guard !title.isEmpty, !asin.isEmpty, price > 0 else {
                    if current.attempts < 8 { self.scheduleQuoteRead(after: 0.75) }
                    else { self.finishQuote(.failure(SessionError.unreadable)) }
                    return
                }
                self.finishQuote(.success(AmazonQuote(title: title, asin: asin, quantity: current.quantity, unitPriceYen: price, shippingYen: shipping)))
            }
        }
    }

    private func finishQuote(_ result: Result<AmazonQuote, Error>) {
        guard let completion = pendingQuote?.completion else { return }
        pendingQuote = nil
        completion(result)
    }

    /// Starts checkout only after Chappie has quoted the price and the user has
    /// explicitly answered yes. The final total is read again before placing the order.
    func purchase(_ url: URL, expectedName: String, quantity: Int, approvedTotalYen: Int,
                  completion: @escaping (Result<AmazonPurchaseResult, Error>) -> Void) {
        let asin = url.pathComponents.drop(while: { $0 != "dp" }).dropFirst().first
        pendingQuote = nil
        pendingCheckout = Checkout(expectedASIN: asin, expectedName: expectedName,
                                   quantity: quantity, approvedTotalYen: approvedTotalYen,
                                   phase: .product, attempts: 0, completion: completion)
        show(url)
        scheduleCheckout(after: 0.8)
    }

    private func scheduleCheckout(after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.advanceCheckout() }
    }

    private func advanceCheckout() {
        guard let webView, var checkout = pendingCheckout else { return }
        checkout.attempts += 1
        pendingCheckout = checkout
        switch checkout.phase {
        case .product: prepareProduct(in: webView, checkout: checkout)
        case .checkout: inspectCheckout(in: webView, checkout: checkout)
        case .submitted: inspectConfirmation(in: webView, checkout: checkout)
        }
    }

    private func prepareProduct(in webView: WKWebView, checkout: Checkout) {
        let script = #"""
        (() => {
          const clean = value => (value || '').replace(/\s+/g, ' ').trim();
          const title = clean(document.querySelector('#productTitle')?.textContent);
          const asin = document.querySelector('#ASIN')?.value || document.querySelector('[data-asin]')?.getAttribute('data-asin') || '';
          const account = clean(document.querySelector('#nav-link-accountList-nav-line-1')?.textContent || document.querySelector('#nav-link-accountList')?.textContent);
          const availability = clean(document.querySelector('#availability')?.textContent);
          const controls = [...document.querySelectorAll('input, button, [role="button"]')];
          const buy = document.querySelector('#buy-now-button, input[name="submit.buy-now"]') || controls.find(e =>
            /今すぐ買う|buy now/i.test(clean(e.value || e.innerText || e.getAttribute('aria-label'))) || /buy-now/i.test(`${e.id || ''} ${e.name || ''}`));
          const oneTimeText = /1回限りの購入/.test(clean(document.body?.innerText));
          const oneTime = [...document.querySelectorAll('input[type="radio"], [role="radio"]')].find(e => {
            const container = e.closest('label, div.a-box, div.a-section, li') || e.parentElement;
            return /1回限りの購入/.test(clean(container?.innerText));
          });
          if (oneTime && !(oneTime.checked || oneTime.getAttribute('aria-checked') === 'true')) oneTime.click();
          const quantity = document.querySelector('#quantity');
          if (quantity && quantity.value !== '\#(checkout.quantity)') {
            quantity.value = '\#(checkout.quantity)';
            quantity.dispatchEvent(new Event('change', {bubbles: true}));
          }
          if (!buy) return {status: 'wait', title, asin, account, availability};
          if (!oneTimeText && !buy) return {status: 'subscription', title, asin, account, availability};
          buy.click();
          return {status: 'clicked', title, asin, account, availability};
        })()
        """#
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            Task { @MainActor in
                guard let self, var current = self.pendingCheckout, current.phase == .product else { return }
                guard let row = value as? [String: Any] else {
                    // A successful buy-now click can cancel the JavaScript callback
                    // while WebKit starts the checkout navigation.
                    if webView.url?.path.contains("/checkout/") == true {
                        current.phase = .checkout; current.attempts = 0; self.pendingCheckout = current
                        self.scheduleCheckout(after: 0.5)
                    } else { self.retryCheckout(or: .unreadable) }
                    return
                }
                let account = row["account"] as? String ?? ""
                let availability = row["availability"] as? String ?? ""
                let asin = row["asin"] as? String ?? ""
                let title = row["title"] as? String ?? ""
                let status = row["status"] as? String ?? "wait"
                if account.contains("ログイン") { self.finishCheckout(.failure(SessionError.notLoggedIn)); return }
                if availability.contains("在庫切れ") || availability.contains("現在お取り扱い") { self.finishCheckout(.failure(SessionError.unavailable)); return }
                if status == "subscription" { self.finishCheckout(.failure(SessionError.subscriptionOnly)); return }
                guard !title.isEmpty, !asin.isEmpty else {
                    if webView.url?.path.contains("/checkout/") == true {
                        current.phase = .checkout; current.attempts = 0; self.pendingCheckout = current
                        self.scheduleCheckout(after: 0.5)
                    } else { self.retryCheckout(or: .unreadable) }
                    return
                }
                if let expected = current.expectedASIN, asin.caseInsensitiveCompare(expected) != .orderedSame {
                    self.finishCheckout(.failure(SessionError.unavailable)); return
                }
                if status == "clicked" {
                    current.phase = .checkout; current.attempts = 0; self.pendingCheckout = current
                    self.scheduleCheckout(after: 1.0)
                } else { self.retryCheckout(or: .checkoutUnavailable) }
            }
        }
    }

    private func inspectCheckout(in webView: WKWebView, checkout: Checkout) {
        let script = #"""
        (() => {
          const clean = value => (value || '').replace(/\s+/g, ' ').trim();
          const text = clean(document.body?.innerText);
          const url = location.href;
          const totalSelectors = ['#subtotals-marketplace-table .grand-total-price', '.grand-total-price', '#order-summary-grand-total', '[data-testid="order-summary-total"]'];
          let totalText = '';
          for (const selector of totalSelectors) { const value = clean(document.querySelector(selector)?.textContent); if (/[￥¥]/.test(value)) { totalText = value; break; } }
          if (!totalText) totalText = text.match(/(?:注文合計|ご請求額|合計)[^￥¥]{0,40}[￥¥]\s*[0-9,]+/)?.[0] || '';
          const totalMatch = totalText.match(/[￥¥]\s*([0-9,]+)/);
          const controls = [...document.querySelectorAll('input, button, [role="button"]')];
          const place = document.querySelector('input[name="placeYourOrder1"], #submitOrderButtonId input, #placeYourOrder input') || controls.find(e =>
            /注文を確定|注文を確定する|place your order/i.test(clean(e.value || e.innerText || e.getAttribute('aria-label'))) || /place.*order/i.test(`${e.id || ''} ${e.name || ''}`));
          return {
            url, text: text.slice(0, 12000), total: totalMatch ? Number(totalMatch[1].replace(/,/g, '')) : 0,
            hasPlace: place ? 1 : 0, auth: /\/ap\/signin|captcha|auth-challenge/i.test(url) ? 1 : 0,
            subscription: /定期おトク便で注文|定期購入として注文/.test(text) ? 1 : 0
          };
        })()
        """#
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            Task { @MainActor in
                guard let self, var current = self.pendingCheckout, current.phase == .checkout else { return }
                guard let row = value as? [String: Any] else { self.retryCheckout(or: .checkoutUnavailable); return }
                if ((row["auth"] as? NSNumber)?.intValue ?? 0) == 1 { self.finishCheckout(.failure(SessionError.notLoggedIn)); return }
                if ((row["subscription"] as? NSNumber)?.intValue ?? 0) == 1 { self.finishCheckout(.failure(SessionError.subscriptionOnly)); return }
                let total = (row["total"] as? NSNumber)?.intValue ?? 0
                let hasPlace = ((row["hasPlace"] as? NSNumber)?.intValue ?? 0) == 1
                guard total > 0, hasPlace else { self.retryCheckout(or: .checkoutUnavailable); return }
                guard total <= current.approvedTotalYen else { self.finishCheckout(.failure(SessionError.totalChanged(total))); return }
                let click = #"""
                (() => {
                  const clean = value => (value || '').replace(/\s+/g, ' ').trim();
                  const controls = [...document.querySelectorAll('input, button, [role="button"]')];
                  const place = document.querySelector('input[name="placeYourOrder1"], #submitOrderButtonId input, #placeYourOrder input') || controls.find(e =>
                    /注文を確定|注文を確定する|place your order/i.test(clean(e.value || e.innerText || e.getAttribute('aria-label'))) || /place.*order/i.test(`${e.id || ''} ${e.name || ''}`));
                  if (!place || place.disabled || place.getAttribute('aria-disabled') === 'true') return 0;
                  place.click(); return 1;
                })()
                """#
                webView.evaluateJavaScript(click) { [weak self] clicked, _ in
                    Task { @MainActor in
                        guard let self, var latest = self.pendingCheckout, latest.phase == .checkout else { return }
                        guard (clicked as? NSNumber)?.intValue == 1 else { self.retryCheckout(or: .checkoutUnavailable); return }
                        latest.phase = .submitted; latest.attempts = 0; self.pendingCheckout = latest
                        self.scheduleCheckout(after: 1.2)
                    }
                }
            }
        }
    }

    private func inspectConfirmation(in webView: WKWebView, checkout: Checkout) {
        let script = #"""
        (() => {
          const clean = value => (value || '').replace(/\s+/g, ' ').trim();
          const text = clean(document.body?.innerText);
          const order = text.match(/\b\d{3}-\d{7}-\d{7}\b/)?.[0] || '';
          const delivery = text.match(/(?:明日|今日)[、,]?\s*\d{1,2}月\d{1,2}日/)?.[0] ||
                           text.match(/\d{4}年\d{1,2}月\d{1,2}日/)?.[0] || '';
          return {ok: /ご注文ありがとうございます|注文が確定|thank you.*order/i.test(text) ? 1 : 0, order, delivery};
        })()
        """#
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            Task { @MainActor in
                guard let self, let current = self.pendingCheckout, current.phase == .submitted else { return }
                guard let row = value as? [String: Any], ((row["ok"] as? NSNumber)?.intValue ?? 0) == 1 else {
                    self.retryCheckout(or: .confirmationUnknown); return
                }
                self.finishCheckout(.success(AmazonPurchaseResult(
                    title: current.expectedName, totalYen: current.approvedTotalYen,
                    delivery: row["delivery"] as? String ?? "", orderNumber: row["order"] as? String ?? "")))
            }
        }
    }

    private func retryCheckout(or error: SessionError) {
        guard let current = pendingCheckout else { return }
        if current.attempts < 15 { scheduleCheckout(after: 0.8) }
        else { finishCheckout(.failure(error)) }
    }

    private func finishCheckout(_ result: Result<AmazonPurchaseResult, Error>) {
        guard let completion = pendingCheckout?.completion else { return }
        pendingCheckout = nil
        completion(result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if pendingQuote != nil { scheduleQuoteRead(after: 0.4) }
        if pendingCheckout != nil { scheduleCheckout(after: 0.4) }
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
