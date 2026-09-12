import Foundation

/// Decides which Chappie feature a request belongs to. Matching a single word
/// sent travel plans to the calendar and polite requests to the shop, so these
/// checks look at the shape of the sentence rather than one keyword.
enum Intent {
    enum Purchase { case explicit, soft, none }

    struct EventDraft: Equatable {
        var title: String
        var start: Date
        var end: Date
        var allDay: Bool
    }

    // MARK: Purchase

    private static let explicitPurchaseWords = [
        "買って", "買っといて", "買っておいて", "買いたい", "買ってきて",
        "購入して", "購入したい", "購入しといて", "購入お願い",
        "注文して", "注文したい", "注文しといて", "注文お願い",
        "頼んで", "頼んどいて", "発注して"
    ]
    private static let softPurchaseWords = ["欲しい", "ほしい", "お願い"]

    /// Explicit words always mean shopping. Soft words ("欲しい", "お願い") only
    /// count when a registered product is named, so "旅行のプランをお願い" is a question.
    static func purchaseIntent(_ text: String) -> Purchase {
        if explicitPurchaseWords.contains(where: text.contains) { return .explicit }
        if softPurchaseWords.contains(where: text.contains) { return .soft }
        return .none
    }

    static func isPurchasableListRequest(_ text: String) -> Bool {
        ["何が買える", "なにが買える", "買えるもの", "買える物", "買えるの", "登録商品", "登録した商品", "登録してある商品", "購入できる"]
            .contains(where: text.contains)
    }

    // MARK: Confirmation

    private static let negativeWords = ["やめ", "いいえ", "キャンセル", "中止", "だめ", "ダメ", "いらない", "要らない", "no", "違う", "ちがう", "待って", "まって"]
    private static let affirmativeWords = ["いいよ", "いいですよ", "はい", "お願い", "買って", "購入して", "注文して", "進めて", "確定", "ok", "okay", "オッケー", "おっけー", "うん", "どうぞ", "よろしく", "いいね", "承認", "了解", "ゴー", "go"]

    static func isNegative(_ text: String) -> Bool {
        let normalized = normalizeAnswer(text)
        return negativeWords.contains(where: normalized.contains)
    }

    /// Anything containing a refusal is treated as "no" first; money never moves on an ambiguous answer.
    static func isAffirmative(_ text: String) -> Bool {
        let normalized = normalizeAnswer(text)
        guard !normalized.isEmpty, !isNegative(text) else { return false }
        return affirmativeWords.contains(where: normalized.contains)
    }

    private static func normalizeAnswer(_ text: String) -> String {
        text.lowercased().unicodeScalars.filter { !CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines).union(.symbols).contains($0) }
            .map(String.init).joined()
    }

    // MARK: Calendar

    private static let calendarWords = ["予定", "カレンダー", "スケジュール"]
    private static let dateWords = ["今日", "きょう", "明日", "あした", "明後日", "あさって", "今週", "来週", "週末", "今月", "来月", "月曜", "火曜", "水曜", "木曜", "金曜", "土曜", "日曜"]
    private static let planningWords = ["立てて", "立てたい", "考えて", "提案", "おすすめ", "お勧め", "オススメ", "プラン", "組んで", "作って", "決めて", "調べて", "検討", "案を", "案が", "案は", "案出", "アイデア"]
    private static let additionWords = ["入れて", "入れといて", "入れておいて", "追加して", "追加しといて", "登録して", "登録しといて", "作成して", "セットして", "押さえて", "おさえて", "ブロックして"]
    private static let eventWords = ["会議", "打ち合わせ", "打合せ", "ミーティング", "アポ", "面談", "会食", "飲み会", "ランチ", "ディナー", "歯医者", "病院", "出張", "旅行", "リマインド", "締め切り", "締切"]

    /// "明日15時に会議を入れて" — a date plus an addition verb. Checked before lookups.
    static func isCalendarAddition(_ text: String) -> Bool {
        guard additionWords.contains(where: text.contains) else { return false }
        return calendarWords.contains(where: text.contains) || eventWords.contains(where: text.contains)
            || dateWords.contains(where: text.contains)
    }

    /// Reading the calendar needs a schedule word without a planning verb, so
    /// "旅行の予定を立てて" goes to research while "今日の予定" and "明日空いてる？" are lookups.
    static func isCalendarLookup(_ text: String) -> Bool {
        if planningWords.contains(where: text.contains) { return false }
        if text.contains("空いてる") || text.contains("空いている") || text.contains("空き時間") { return true }
        return calendarWords.contains(where: text.contains)
    }

    /// Which day range a lookup covers, as an offset from today and a length in days.
    static func lookupRange(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date, label: String) {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        if text.contains("明後日") || text.contains("あさって") { return (day(2), day(3), "明後日") }
        if text.contains("明日") || text.contains("あした") { return (day(1), day(2), "明日") }
        if text.contains("来週") {
            let weekday = calendar.component(.weekday, from: today) // Sunday = 1
            let daysUntilNextMonday = ((9 - weekday) % 7 == 0) ? 7 : (9 - weekday) % 7
            return (day(daysUntilNextMonday), day(daysUntilNextMonday + 7), "来週")
        }
        if text.contains("今週") || text.contains("週末") { return (today, day(7), "今週") }
        if text.contains("今月") || text.contains("来月") {
            let base = text.contains("来月") ? calendar.date(byAdding: .month, value: 1, to: today)! : today
            let components = calendar.dateComponents([.year, .month], from: base)
            let first = calendar.date(from: components)!
            let start = text.contains("来月") ? first : today
            return (start, calendar.date(byAdding: .month, value: 1, to: first)!, text.contains("来月") ? "来月" : "今月")
        }
        return (today, day(1), "今日")
    }

    static func isTravelEvent(_ title: String) -> Bool {
        ["旅行", "出張", "トリップ", "旅", "遠征", "帰省", "travel", "trip"].contains(where: title.lowercased().contains)
    }

    /// Builds an event from natural Japanese ("来週の火曜10時に歯医者を入れて") using
    /// the system date detector, so nothing leaves the Mac. Returns nil without a date.
    static func eventDraft(from text: String, now: Date = Date(), calendar: Calendar = .current) -> EventDraft? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let nsText = text as NSString
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length)).filter { $0.date != nil }
        guard let first = matches.first, let start = first.date else { return nil }

        let matchedText = matches.map { nsText.substring(with: $0.range) }.joined(separator: " ")
        let hasTime = matchedText.range(of: #"時|:|：|午前|午後|朝|昼|夜|夕方|正午"#, options: .regularExpression) != nil
        let allDay = !hasTime

        var end: Date
        if first.duration > 0 {
            end = start.addingTimeInterval(first.duration)
        } else if matches.count > 1, let second = matches[1].date, second > start,
                  (text.contains("から") || text.contains("〜") || text.contains("~") || text.contains("-")) {
            end = second
        } else if allDay {
            end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start))!
        } else {
            end = start.addingTimeInterval(3600)
        }

        var title = text
        for match in matches.sorted(by: { $0.range.location > $1.range.location }) {
            title = (title as NSString).replacingCharacters(in: match.range, with: " ")
        }
        let noise = ["予定を入れて", "予定を追加して", "予定を登録して", "予定に入れて", "予定に追加して",
                     "カレンダーに入れて", "カレンダーに追加して", "カレンダーに登録して", "スケジュールに入れて",
                     "を入れといて", "を入れておいて", "を入れて", "を追加して", "を登録して", "を作成して", "をセットして", "を押さえて", "をおさえて", "をブロックして",
                     "入れといて", "入れておいて", "入れて", "追加して", "登録して", "作成して", "セットして", "押さえて", "おさえて", "ブロックして",
                     "予定", "カレンダー", "スケジュール", "ください", "お願い", "って", "ね"]
        for word in noise { title = title.replacingOccurrences(of: word, with: " ") }
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        title = title.replacingOccurrences(of: #"^(の|に|から|で|は|と|を|へ|まで)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*(の|に|から|で|は|と|を|へ|まで)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if title.isEmpty { title = "予定" }
        return EventDraft(title: title, start: allDay ? calendar.startOfDay(for: start) : start, end: end, allDay: allDay)
    }

    // MARK: Files

    /// Returns the name to look for, or nil when the sentence is not a file search.
    /// The empty string means "search requested, but no name yet".
    static func fileSearchTerm(_ text: String) -> String? {
        let searchWords = ["探して", "探し", "検索", "どこ", "見せて", "開いて", "見つけて"]
        var term: String
        if text.hasPrefix("ファイル") {
            term = String(text.dropFirst("ファイル".count))
        } else if text.hasPrefix("探して") {
            term = String(text.dropFirst("探して".count))
        } else if text.contains("ファイル"), searchWords.contains(where: text.contains) {
            term = text.replacingOccurrences(of: "ファイル", with: " ")
        } else {
            return nil
        }
        for word in searchWords + ["という", "の", "を", "って", "ください", "お願い"] {
            term = term.replacingOccurrences(of: word, with: " ")
        }
        return term.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    // MARK: Sales / settings

    static func isSalesQuestion(_ text: String) -> Bool {
        ["売上", "売り上げ", "受注", "注文状況", "注文数", "注文件数", "注文履歴", "今日の注文", "本日の注文"].contains(where: text.contains)
    }

    /// The wake word has already been removed, so only questions about the app itself match.
    static func isSettingsQuestion(_ text: String) -> Bool {
        ["設定を教えて", "今の設定", "現在の設定", "設定は", "設定って", "購入のやつ", "音声オン", "音声オフ", "自動起動", "ログイン時に起動", "noteの登録", "連携状況",
         "何ができる", "なにができる", "できること", "使い方", "ヘルプ", "このアプリ", "自己紹介", "誰", "だれ"].contains(where: text.contains)
    }
}
