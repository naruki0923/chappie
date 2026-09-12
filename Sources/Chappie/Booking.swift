import AppKit
import WebKit

/// What Chappie extracted from the conversation for a booking. Built by the child
/// Claude as JSON, then turned into a pre-filled search page; the user does the rest.
struct BookingPlan: Codable, Equatable {
    enum Kind: String, Codable { case train, flight, hotel, restaurant, unknown }
    var kind: Kind = .unknown
    var origin: String?        // train / flight
    var destination: String?   // train / flight
    var area: String?          // hotel / restaurant
    var keyword: String?       // restaurant genre or hotel wish ("焼肉", "温泉")
    var date: String?          // YYYY-MM-DD
    var time: String?          // HH:mm
    var checkin: String?       // YYYY-MM-DD
    var checkout: String?      // YYYY-MM-DD
    var guests: Int?
    var missing: [String] = [] // what still has to be asked

    /// Search page with the conditions in the URL, or nil when something essential is missing.
    var searchURL: URL? {
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value }
        switch kind {
        case .train:
            guard let origin, let destination, let date, let parts = Self.dateParts(date) else { return nil }
            var query = "from=\(encode(origin))&to=\(encode(destination))&y=\(parts.year)&m=\(parts.month)&d=\(parts.day)&type=1&ticket=ic&expkind=1&ws=3&s=0"
            if let time, let hhmm = Self.timeParts(time) { query += "&hh=\(hhmm.hour)&m1=\(hhmm.minute / 10)&m2=\(hhmm.minute % 10)" }
            return URL(string: "https://transit.yahoo.co.jp/search/result?\(query)")
        case .flight:
            guard let origin, let destination, let date else { return nil }
            return URL(string: "https://www.google.com/travel/flights?hl=ja&q=\(encode("\(date) \(origin)から\(destination)への航空券"))")
        case .hotel:
            guard let area, let checkin, let checkout else { return nil }
            let wish = keyword.map { " \($0)" } ?? ""
            return URL(string: "https://www.booking.com/searchresults.ja.html?ss=\(encode(area + wish))&checkin=\(checkin)&checkout=\(checkout)&group_adults=\(guests ?? 2)&no_rooms=1&group_children=0&lang=ja")
        case .restaurant:
            guard let area else { return nil }
            let words = [area, keyword].compactMap { $0 }.joined(separator: " ")
            var query = "sw=\(encode(words))"
            if let date, let parts = Self.dateParts(date) { query += "&svd=\(parts.year)\(parts.month)\(parts.day)" }
            if let time, let hhmm = Self.timeParts(time) { query += "&svt=\(hhmm.hour)\(String(format: "%02d", hhmm.minute))" }
            if let guests { query += "&svps=\(guests)" }
            return URL(string: "https://tabelog.com/rstLst/?\(query)")
        case .unknown:
            return nil
        }
    }

    var summary: String {
        var parts: [String] = []
        switch kind {
        case .train: parts.append("新幹線・電車：\(origin ?? "?")→\(destination ?? "?")")
        case .flight: parts.append("飛行機：\(origin ?? "?")→\(destination ?? "?")")
        case .hotel: parts.append("宿：\(area ?? "?")\(keyword.map { "（\($0)）" } ?? "")")
        case .restaurant: parts.append("お店：\(area ?? "?")\(keyword.map { " \($0)" } ?? "")")
        case .unknown: parts.append("予約")
        }
        if let date { parts.append(Self.japaneseDate(date) + (time.map { " \($0)" } ?? "")) }
        if let checkin, let checkout { parts.append("\(Self.japaneseDate(checkin))〜\(Self.japaneseDate(checkout))") }
        if let guests { parts.append("\(guests)人") }
        return parts.joined(separator: "、")
    }

    var siteName: String {
        switch kind {
        case .train: return "Yahoo!乗換案内"
        case .flight: return "Googleフライト"
        case .hotel: return "Booking.com"
        case .restaurant: return "食べログ"
        case .unknown: return "予約サイト"
        }
    }

    var handoffNote: String {
        switch kind {
        case .train: return "候補の列車を選んだら、スマートEXかえきねっとで席を押さえてください。"
        case .flight: return "便を選んだら航空会社のページで購入に進めます。支払いはご自身で。"
        case .hotel: return "宿を選んで予約画面へ進んでください。支払い・確定はご自身で押してください。"
        case .restaurant: return "お店を選んで予約画面へ進んでください。予約確定はご自身で押してください。"
        case .unknown: return ""
        }
    }

    private static func dateParts(_ value: String) -> (year: String, month: String, day: String)? {
        let parts = value.split(separator: "-").map(String.init)
        guard parts.count == 3, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        return (parts[0], String(format: "%02d", Int(parts[1])!), String(format: "%02d", Int(parts[2])!))
    }

    private static func timeParts(_ value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":").map(String.init)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return (hour, minute)
    }

    private static func japaneseDate(_ value: String) -> String {
        guard let parts = dateParts(value) else { return value }
        return "\(Int(parts.month)!)月\(Int(parts.day)!)日"
    }

    /// The child Claude sometimes wraps JSON in prose or a code fence; keep the first object.
    static func parse(_ text: String) -> BookingPlan? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        let json = String(text[start...end])
        return try? JSONDecoder().decode(BookingPlan.self, from: Data(json.utf8))
    }
}

/// A second dedicated browser, separate from the Amazon one, where booking searches open.
/// Logins persist in the default WebKit store; Chappie never fills payment or presses confirm.
@MainActor
final class BookingWindowController {
    static let shared = BookingWindowController()
    private var window: NSWindow?
    private var webView: WKWebView?

    func show(_ url: URL) {
        let browser = ensureWindow()
        browser.load(URLRequest(url: url))
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func ensureWindow() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "Chappie/0.9"
        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.allowsBackForwardNavigationGestures = true
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "チャッピー — 予約"
        window.contentView = browser
        window.center()
        window.isReleasedWhenClosed = false
        self.webView = browser
        self.window = window
        return browser
    }
}
