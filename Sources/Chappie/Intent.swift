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
    private static let planningWords = ["立てて", "立てたい", "考えて", "提案", "おすすめ", "お勧め", "オススメ", "プラン", "組んで", "作って", "決めて", "検討", "案を", "案が", "案は", "案出", "アイデア"]
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

    // MARK: Calendar edits

    struct EventTarget: Equatable {
        var hint: String            // words that should appear in the event title
        var windowStart: Date
        var windowEnd: Date
        var hour: Int?              // "明日10時の会議" narrows to events starting at that hour
    }

    enum NewStart: Equatable {
        case absolute(Date)         // "明後日の19時に"
        case timeOnly(hour: Int, minute: Int)   // "16時に" — same day as the event
        case dayOnly(Date)          // "金曜に" — same time, new day
        case shift(TimeInterval)    // "30分後ろに"
    }

    enum CalendarEdit: Equatable {
        case move(EventTarget, NewStart)
        case delete(EventTarget)
        case freeSlots(start: Date, end: Date, label: String, minutes: Int)
    }

    private static let moveWords = ["ずらして", "ずらしといて", "変更して", "変えて", "移して", "移動して", "動かして", "後ろ倒し", "前倒し", "リスケ", "延期して", "早めて", "遅らせて"]
    private static let deleteWords = ["消して", "削除して", "キャンセルして", "取り消して", "なくして", "取りやめ", "中止にして"]

    /// "明日の会議を16時にずらして" / "今日の打ち合わせをキャンセルして" / "来週で1時間空いてるところ".
    /// Everything is parsed on the Mac; the Assistant then applies it to Apple Calendar.
    static func calendarEdit(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> CalendarEdit? {
        if text.contains("空いてる") || text.contains("空いている") || text.contains("空き時間") {
            let range = lookupRange(text, now: now, calendar: calendar)
            var minutes = 60
            if let match = text.range(of: #"(\d+)\s*(時間|分)"#, options: .regularExpression) {
                let amount = Int(text[match].filter(\.isNumber)) ?? 1
                minutes = text[match].contains("時間") ? amount * 60 : amount
            }
            return .freeSlots(start: range.start, end: range.end, label: range.label, minutes: minutes)
        }
        let isMove = moveWords.contains(where: text.contains)
        let isDelete = deleteWords.contains(where: text.contains)
        guard isMove || isDelete else { return nil }
        guard calendarWords.contains(where: text.contains) || eventWords.contains(where: text.contains) || dateWords.contains(where: text.contains) else { return nil }

        // Left of the first "を" names the event; the rest says where it goes.
        let parts = text.components(separatedBy: "を")
        let left = parts.first ?? text
        let right = parts.count > 1 ? parts.dropFirst().joined(separator: "を") : ""

        let window: (start: Date, end: Date, label: String)
        if dateWords.contains(where: left.contains) {
            window = lookupRange(left, now: now, calendar: calendar)
        } else {
            let today = calendar.startOfDay(for: now)
            window = (today, calendar.date(byAdding: .day, value: 30, to: today)!, "今後30日")
        }
        var hour: Int?
        if let match = left.range(of: #"(\d{1,2})\s*時"#, options: .regularExpression) {
            hour = Int(left[match].filter(\.isNumber))
            if left.contains("午後"), let value = hour, value < 12 { hour = value + 12 }
        }
        var hint = left
        for word in dateWords + calendarWords + ["午前", "午後", "から", "の予定", "の件", "その", "この", "あの"] { hint = hint.replacingOccurrences(of: word, with: " ") }
        hint = hint.replacingOccurrences(of: #"\d{1,2}\s*時(\d{1,2}分|半)?"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[、。,.:：「」()（）]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(の|に|は|と)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*(の|に|は|と)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let target = EventTarget(hint: hint, windowStart: window.start, windowEnd: window.end, hour: hour)
        if isDelete && !isMove { return .delete(target) }

        if let match = right.range(of: #"(\d+)\s*(時間|分)\s*(後ろ|遅く|あと|後に|前|早く|早めて|遅らせて)"#, options: .regularExpression) {
            let matched = String(right[match])
            let amount = Double(Int(matched.filter(\.isNumber)) ?? 0)
            let seconds = matched.contains("時間") ? amount * 3600 : amount * 60
            let backwards = matched.contains("前") || matched.contains("早")
            return .move(target, .shift(backwards ? -seconds : seconds))
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let nsRight = right as NSString
        guard let match = detector.matches(in: right, range: NSRange(location: 0, length: nsRight.length)).first(where: { $0.date != nil }),
              let date = match.date else { return nil }
        let matchedText = nsRight.substring(with: match.range)
        let hasTime = matchedText.range(of: #"時|:|：|午前|午後|正午"#, options: .regularExpression) != nil
        let hasDay = dateWords.contains(where: matchedText.contains) || matchedText.range(of: #"\d+\s*(月|/|日)"#, options: .regularExpression) != nil
        if hasTime && hasDay { return .move(target, .absolute(date)) }
        if hasTime {
            let components = calendar.dateComponents([.hour, .minute], from: date)
            return .move(target, .timeOnly(hour: components.hour ?? 0, minute: components.minute ?? 0))
        }
        return .move(target, .dayOnly(calendar.startOfDay(for: date)))
    }

    /// Title match used by move/delete. Either side containing the other counts, as does any 2-character run of the hint.
    static func eventMatches(title: String, hint: String) -> Bool {
        let cleanTitle = title.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
        let cleanHint = hint.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
        guard !cleanHint.isEmpty else { return true }
        if cleanTitle.contains(cleanHint) || cleanHint.contains(cleanTitle) { return true }
        let chars = Array(cleanHint)
        guard chars.count >= 2 else { return false }
        return (0..<(chars.count - 1)).contains { cleanTitle.contains(String(chars[$0...$0 + 1])) }
    }

    // MARK: Reminders

    struct ReminderDraft: Equatable {
        var title: String
        var due: Date
    }

    private static let reminderWords = ["リマインド", "リマインダー", "思い出させて", "知らせて", "通知して", "アラーム", "忘れないように", "覚えといて", "覚えておいて", "声かけて", "声をかけて", "呼んで"]

    static func isReminderListRequest(_ text: String) -> Bool {
        guard text.contains("リマインド") || text.contains("リマインダー") else { return false }
        return ["一覧", "何がある", "なにがある", "何が入って", "確認", "見せて", "教えて", "ある？", "ある?"].contains(where: text.contains)
    }

    /// "リマインドを消して" / "リマインダーの時間を変えて": the reminder itself is the object of a
    /// delete/move verb. "ホテルをキャンセルしてってリマインドして" is still a new reminder.
    static func isReminderEdit(_ text: String) -> Bool {
        text.range(of: #"リマイン(ド|ダー)(は|を|の)?[^、。]{0,6}?(消して|削除して|キャンセルして|取り消して|なくして|やめて|変えて|変更して|ずらして|移して)"#, options: .regularExpression) != nil
    }

    /// "段ボール捨てるってリマインダー入れといて" with no time at all: still a reminder
    /// request, so the Assistant asks when instead of sending it to the AI.
    static func isReminderAddition(_ text: String) -> Bool {
        guard text.contains("リマインド") || text.contains("リマインダー"), !isReminderEdit(text) else { return false }
        return (additionWords + ["して", "しといて", "しておいて", "設定", "セット", "お願い"]).contains(where: text.contains)
    }

    /// "30分後に電話するのを教えて" / "金曜に振込をリマインドして". Relative times are
    /// resolved here; absolute ones use the system detector. Dates without a time default to 9:00.
    static func reminderDraft(from text: String, now: Date = Date(), calendar: Calendar = .current) -> ReminderDraft? {
        let hasReminderWord = reminderWords.contains(where: text.contains)
        // "明日のリマインドを消して" asks to remove one; never turn it into a new reminder.
        guard !isReminderEdit(text) else { return nil }
        var due: Date?
        var consumed: [Range<String.Index>] = []
        var relative = false

        // "あと10分" / "30分後" / "1時間したら". A bare "23日" is a date, not a count, so it falls through.
        if let match = text.range(of: #"あと\s*\d+\s*(分|時間|日)|\d+\s*(分|時間|日)\s*(後|で|したら|経ったら|たったら)"#, options: .regularExpression),
           let amount = Int(text[match].filter(\.isNumber)), amount > 0 {
            let matched = String(text[match])
            let unit: Calendar.Component = matched.contains("分") ? .minute : matched.contains("時間") ? .hour : .day
            due = calendar.date(byAdding: unit, value: amount, to: now)
            consumed.append(match)
            relative = true
        } else if hasReminderWord || text.contains("になったら") {
            guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
            let nsText = text as NSString
            if let match = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length)).first(where: { $0.date != nil }),
               var date = match.date, let range = Range(match.range, in: text) {
                let matchedText = nsText.substring(with: match.range)
                let hasTime = matchedText.range(of: #"時|:|：|午前|午後|朝|昼|夜|夕方|正午"#, options: .regularExpression) != nil
                let hasDay = dateWords.contains(where: matchedText.contains) || matchedText.range(of: #"\d+\s*(月|/|日)"#, options: .regularExpression) != nil
                if !hasDay, let (day, dayRange) = dayOfMonth(in: text, now: now, calendar: calendar) {
                    // "23日に9時に": the detector only saw the time, so the day comes from the bare number.
                    // When the two matches overlap, dayOfMonth has already read that time itself.
                    if dayRange.overlaps(range) || !hasTime {
                        date = day
                    } else {
                        let time = calendar.dateComponents([.hour, .minute], from: date)
                        date = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day) ?? day
                    }
                    consumed.append(dayRange)
                } else if !hasTime {
                    date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
                }
                due = date
                consumed.append(range)
            } else if let (date, range) = dayOfMonth(in: text, now: now, calendar: calendar) {
                due = date
                consumed.append(range)
            }
        }
        // "1時間後に休憩" is a reminder even without a verb; an absolute time still needs one.
        guard let due, relative || hasReminderWord || text.contains("になったら") else { return nil }

        // Merge overlapping matches ("23日に9時" and "9時に") before editing, so every index still refers to `text`.
        var merged: [Range<String.Index>] = []
        for range in consumed.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, last.overlaps(range) || last.upperBound == range.lowerBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        var title = text
        for range in merged.reversed() { title.replaceSubrange(range, with: " ") }
        let noise = ["になったら", "リマインドして", "リマインドしといて", "リマインド", "リマインダーして", "リマインダーしといて", "リマインダー", "思い出させて", "知らせて", "通知して", "アラームをかけて", "アラーム",
                     "忘れないように", "覚えといて", "覚えておいて", "声かけて", "声をかけて", "呼んで", "教えて",
                     "入れといて", "入れておいて", "入れて", "追加して", "登録して", "設定して", "セットして", "かけて",
                     "するのを", "することを", "するように", "するの", "ように", "のを", "ことを", "っていう", "という", "って", "ください", "お願い", "ね", "よ"]
        for word in noise.sorted(by: { $0.count > $1.count }) { title = title.replacingOccurrences(of: word, with: " ") }
        title = title.replacingOccurrences(of: #"[、。,.:：「」()（）]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Particles can stack once the words between them are gone ("ゴミ出しを に"), so strip repeatedly.
        title = title.replacingOccurrences(of: #"^((を|は|で|に|と|の|も|が)\s*)+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(\s*(を|は|で|に|と|の|も|が))+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { title = "リマインド" }
        return ReminderDraft(title: title, due: due)
    }

    /// "23日に" / "23日の9時半に" without a month, which the system detector ignores: the
    /// next such day (this month, or next month once it has passed). Time defaults to 9:00.
    private static func dayOfMonth(in text: String, now: Date, calendar: Calendar) -> (Date, Range<String.Index>)? {
        guard let match = text.range(of: #"(?<![\d月/])(\d{1,2})日(?!後|間|目|分|以)(の|に|\s)*((午前|午後|朝|夜)?\s*(\d{1,2})\s*時(?!間)\s*((\d{1,2})\s*分|半)?)?"#, options: .regularExpression) else { return nil }
        // Typed text may use full-width digits ("２３日"); Int only reads ASCII, and the range must stay on `text`.
        let matched = String(text[match]).applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? String(text[match])
        let parsed = matched.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }.map { Int($0) }
        guard parsed.allSatisfy({ $0 != nil }), let day = parsed.first ?? nil, (1...31).contains(day) else { return nil }
        let numbers = parsed.compactMap { $0 }
        var hour = 9, minute = 0
        if matched.contains("時"), numbers.count > 1 {
            hour = numbers[1]
            if (matched.contains("午後") || matched.contains("夜")), hour < 12 { hour += 12 }
            minute = matched.contains("半") ? 30 : (numbers.count > 2 ? numbers[2] : 0)
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        // Today still counts as "the 23rd"; a time already passed is reported by addReminder.
        let today = calendar.startOfDay(for: now)
        var month = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
        for _ in 0..<2 {
            guard let first = month else { break }
            var components = calendar.dateComponents([.year, .month], from: first)
            components.day = day; components.hour = hour; components.minute = minute
            if let date = calendar.date(from: components), calendar.component(.day, from: date) == day, date >= today { return (date, match) }
            month = calendar.date(byAdding: .month, value: 1, to: first)
        }
        return nil
    }

    // MARK: Product registration

    struct RegistrationDraft: Equatable {
        var name: String
        var url: URL
        var quantity: Int
        var maxTotalYen: Int
    }

    struct RuleChange: Equatable {
        var quantity: Int?
        var maxTotalYen: Int?
    }

    private static let registrationWords = ["登録して", "登録しといて", "登録しておいて", "登録お願い", "覚えて", "覚えといて", "覚えておいて", "追加して", "追加しといて", "買えるようにして", "登録"]
    private static let removalWords = ["登録から外して", "登録から消して", "登録を外して", "登録を消して", "登録解除", "登録から削除", "削除して", "消して", "外して", "買えなくして"]

    /// "このURLをシャンプーとして登録して https://…" → name, url, and optional "2個" / "上限3000円".
    /// Only typed requests carry a URL, so voice never reaches this path by accident.
    static func registrationRequest(_ text: String) -> RegistrationDraft? {
        guard let urlRange = text.range(of: #"https?://[^\s　、。「」]+"#, options: .regularExpression),
              let url = URL(string: String(text[urlRange])) else { return nil }
        var rest = text.replacingCharacters(in: urlRange, with: " ")
        guard registrationWords.contains(where: rest.contains) else { return nil }

        var quantity = 1
        if let match = rest.range(of: #"(\d+)\s*(個|本|袋|箱|セット|つ)"#, options: .regularExpression) {
            quantity = Int(rest[match].filter(\.isNumber)) ?? 1
            rest.replaceSubrange(match, with: " ")
        }
        var limit = 0
        if let match = rest.range(of: #"(上限|最大|予算)?\s*(\d[\d,]*)\s*円\s*(まで|以内|以下)?"#, options: .regularExpression) {
            limit = Int(rest[match].filter(\.isNumber)) ?? 0
            rest.replaceSubrange(match, with: " ")
        }

        let noise = registrationWords + ["この商品", "このURL", "このリンク", "この", "これ", "商品", "URL", "リンク", "として", "という名前で", "の名前で", "呼び名", "名前は", "名前", "上限", "ください", "お願い", "っていう", "って", "ね", "よ"]
        var name = rest
        for word in noise.sorted(by: { $0.count > $1.count }) { name = name.replacingOccurrences(of: word, with: " ") }
        name = name.replacingOccurrences(of: #"[、。,.:：「」()（）]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: #"^(を|は|で|に|と|の|も)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*(を|は|で|に|と|の|も)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return RegistrationDraft(name: name, url: url, quantity: quantity, maxTotalYen: limit)
    }

    static func isRemovalRequest(_ text: String) -> Bool {
        removalWords.contains(where: text.contains)
    }

    /// "シャンプーは2個にして" / "上限を2000円にして" / "上限なしにして". Nil when nothing changes.
    static func ruleChange(_ text: String) -> RuleChange? {
        guard ["にして", "に変えて", "に変更", "に設定", "にしといて", "に増やして", "に減らして"].contains(where: text.contains) else { return nil }
        var change = RuleChange()
        if let match = text.range(of: #"(\d+)\s*(個|本|袋|箱|セット|つ)"#, options: .regularExpression) {
            change.quantity = Int(text[match].filter(\.isNumber))
        }
        if text.contains("上限なし") || text.contains("上限無し") || text.contains("都度確認") {
            change.maxTotalYen = 0
        } else if let match = text.range(of: #"(\d[\d,]*)\s*円"#, options: .regularExpression) {
            change.maxTotalYen = Int(text[match].filter(\.isNumber))
        }
        return change.quantity == nil && change.maxTotalYen == nil ? nil : change
    }

    // MARK: Booking

    private static let bookingWords = ["予約して", "予約したい", "予約お願い", "予約を", "予約ページ", "予約サイト", "取って", "取っといて", "手配して", "押さえといて", "抑えて", "予約"]
    private static let travelNouns = ["新幹線", "特急", "電車", "飛行機", "航空券", "フライト", "便", "ホテル", "宿", "旅館", "民宿", "レストラン", "お店", "店", "居酒屋", "会食", "ランチ", "ディナー", "食事", "席", "旅行", "出張", "その案", "この案", "そのプラン", "このプラン", "それで"]

    /// "20日の東京→新大阪の新幹線を取って" / "その案で予約して". The details come from the
    /// conversation via the child Claude; this only decides that a booking is wanted.
    static func isBookingRequest(_ text: String) -> Bool {
        guard bookingWords.contains(where: text.contains) else { return false }
        // "予約" alone also appears in "予約の確認" and "予約リスト"; require something bookable.
        return travelNouns.contains(where: text.contains) || text.contains("予約して") || text.contains("予約したい") || text.contains("手配して")
    }

    // MARK: Mail

    enum MailRequest: Equatable { case summary, draft }

    private static let mailWords = ["メール", "めーる", "ジーメール", "gmail", "受信箱", "受信トレイ", "未読", "inbox"]
    private static let strongDraftWords = ["下書き", "返信して", "返信を", "返事して", "返事を書", "メールして", "メールを書", "メールで伝え", "メールで連絡", "メールで送"]
    private static let softDraftWords = ["書いて", "送って", "連絡して", "伝えて", "お礼", "断って", "お断り", "催促", "依頼して", "返信"]

    /// "未読メールを要約して" → summary; "田中さんに遅れると下書きして" → draft. Sending is never an option.
    static func mailRequest(_ text: String) -> MailRequest? {
        let lowered = text.lowercased()
        if strongDraftWords.contains(where: lowered.contains) { return .draft }
        guard mailWords.contains(where: lowered.contains) else { return nil }
        return softDraftWords.contains(where: lowered.contains) ? .draft : .summary
    }

    // MARK: Garbage

    enum GarbageQuestion: Equatable {
        /// "今日は何のゴミ？" / "来週のゴミ" — what is collected in [start, end). `kind` is set when
        /// a kind was also named ("明日は可燃？"), so the answer can add that kind's next day.
        case days(start: Date, end: Date, label: String, kind: GarbageKind?)
        /// "ペットボトルはいつ？" / "蛍光灯は何ゴミ？" — the next collection of one kind; `item` is the
        /// thing that was named when it was not the kind itself, so the answer can say what it is.
        case next(GarbageKind, item: String?)
        /// "粗大ごみはいつ？" — not a collection day; it is by appointment.
        case bulky
        /// "不燃ごみは？" — this district has no such category; the answer explains the split.
        case nonBurnable
        /// "充電式電池はいつ？" — never a collection day; it goes to a recycle box.
        case rechargeableBattery
    }

    private static let garbageWords = ["ごみ", "ゴミ", "収集日", "回収日"]
    private static let garbageDayWords = ["いつ", "何曜", "なんよう", "の日", "出せる", "出せます", "出す", "出して", "出し", "回収", "収集", "捨て"]
    private static let strongGarbageKindWords = ["可燃", "燃えるごみ", "燃えるゴミ", "燃えないごみ", "燃えないゴミ", "不燃", "粗大", "ペットボトル", "プラスチック", "プラの日", "プラごみ", "プラゴミ", "紙類", "古紙", "段ボール", "ダンボール",
                                                 "金物", "埋立", "埋め立て", "水銀", "蛍光灯", "電球", "電池", "モバイルバッテリー", "空き缶", "スプレー缶", "カセットボンベ", "発泡スチロール"]
    private static let bulkyWords = ["粗大"]
    private static let nonBurnableWords = ["不燃", "燃えない", "燃やせない", "燃せない"]
    private static let rechargeableWords = ["充電式", "充電池", "モバイルバッテリー", "リチウムイオン"]
    private static let weekdayNames: [(String, Int)] = [("日曜", 1), ("月曜", 2), ("火曜", 3), ("水曜", 4), ("木曜", 5), ("金曜", 6), ("土曜", 7)]

    /// A garbage word, or a kind name with a "when" word, marks the question. Shopping
    /// ("ゴミ袋買って", "ゴミ袋欲しい"), deliveries ("缶ビールいつ届く") and calendar edits
    /// ("明日8時にゴミ出しを入れて", "ゴミ出しの予定を消して") keep their own routes.
    static func garbageQuestion(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> GarbageQuestion? {
        switch purchaseIntent(text) {
        case .explicit: return nil
        case .soft: if ["袋", "箱", "ネット", "バケツ"].contains(where: text.contains) { return nil }
        case .none: break
        }
        // "電池いつ届く？" is about a parcel even without an order word.
        guard !isOrderStatusQuestion(text), !["届く", "届いた", "届き", "配達", "配送", "到着", "発送", "出荷"].contains(where: text.contains) else { return nil }
        guard !(additionWords + moveWords + deleteWords).contains(where: text.contains) else { return nil }
        let hasGarbageWord = garbageWords.contains(where: text.contains)
        let hasKindWord = strongGarbageKindWords.contains(where: text.contains) && garbageDayWords.contains(where: text.contains)
        guard hasGarbageWord || hasKindWord else { return nil }
        if bulkyWords.contains(where: text.contains) { return .bulky }
        if nonBurnableWords.contains(where: text.contains) { return .nonBurnable }
        if rechargeableWords.contains(where: text.contains) { return .rechargeableBattery }
        let named = GarbageKind.named(in: text)
        let kind = named?.kind

        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        var range: (start: Date, end: Date, label: String)?
        if text.contains("明後日") || text.contains("あさって") || text.contains("明日") || text.contains("あした") || text.contains("今日") || text.contains("きょう") || text.contains("本日") {
            range = lookupRange(text, now: now, calendar: calendar)
        } else if let weekday = weekdayNames.first(where: { text.contains($0.0) }) {
            // "来週の火曜" is next week's; otherwise the coming one, today included.
            var candidate = today
            if text.contains("来週") { candidate = lookupRange("来週", now: now, calendar: calendar).start }
            while calendar.component(.weekday, from: candidate) != weekday.1 { candidate = calendar.date(byAdding: .day, value: 1, to: candidate)! }
            range = (candidate, calendar.date(byAdding: .day, value: 1, to: candidate)!, "\(weekday.0)日")
        } else if text.contains("今週") || text.contains("来週") || text.contains("週末") || text.contains("今月") || text.contains("来月") {
            range = lookupRange(text, now: now, calendar: calendar)
        } else if ["年末年始", "年末", "年始", "正月", "お正月"].contains(where: text.contains) {
            // The fiscal-year calendar runs April–March, so "年末年始" is the coming (or just passed) one.
            let month = calendar.component(.month, from: today)
            let year = calendar.component(.year, from: today) - (month < 4 ? 1 : 0)
            let start = calendar.date(from: DateComponents(year: year, month: 12, day: 28))!
            range = (start, calendar.date(byAdding: .day, value: 12, to: start)!, "年末年始")
        } else if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
                  let match = detector.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).first(where: { $0.date != nil }),
                  let date = match.date {
            // An explicit date needs no label; the answer prints the date itself.
            let start = calendar.startOfDay(for: date)
            range = (start, calendar.date(byAdding: .day, value: 1, to: start)!, "")
        }

        if let range { return .days(start: range.start, end: range.end, label: range.label, kind: kind) }
        if let named { return .next(named.kind, item: named.item) }
        return .days(start: today, end: day(7), label: "今日から1週間", kind: nil)
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

    // MARK: Memory

    enum SaveRequest: Equatable {
        /// "今のを保存して" / "保存して": the conversation just before this request.
        case lastExchange
        /// "コーヒーはブラック派ってメモして": the user's own words.
        case memo(String)
    }

    private static let saveVerbs = [
        "保存しておいて", "保存しといて", "保存して", "記録しておいて", "記録しといて", "記録して",
        "メモしておいて", "メモしといて", "メモっといて", "メモって", "メモして", "ノートに残して", "ノートに書いて",
        "記憶しておいて", "記憶しといて", "記憶して", "残しておいて", "残しといて", "覚えておいて", "覚えといて"
    ]

    /// Saving happens only when asked. "覚えといて" saves the last exchange but never a quoted
    /// memo, because "歯医者って覚えといて" is a reminder that still needs a time.
    static func saveRequest(_ text: String) -> SaveRequest? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[。．.！!？?\s]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(ください|くれる|くれ|お願いします|お願い|ね|よ)$"#, with: "", options: .regularExpression)
        guard let verb = saveVerbs.first(where: { body.hasSuffix($0) }) else { return nil }
        body = String(body.dropLast(verb.count)).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "、,")))
        if body.range(of: #"^((今|いま|さっき|今日|きょう)の?|この|その|それ|これ)?(話|会話|内容|答え|回答|やりとり|やり取り|案|提案|件)?(を|も|は)?$"#, options: .regularExpression) != nil {
            return .lastExchange
        }
        guard !verb.hasPrefix("覚え") else { return nil }
        var content: String?
        if let quote = body.range(of: #"\s*(って|と)$"#, options: .regularExpression) {
            content = String(body[..<quote.lowerBound])
        } else if verb.hasPrefix("メモ") || verb.hasPrefix("記録"), body.hasSuffix("を"),
                  !["この", "その", "あの"].contains(where: body.hasPrefix) {
            content = String(body.dropLast())
        }
        guard let memo = content?.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "、,「」『』"))), !memo.isEmpty else { return nil }
        return .memo(memo)
    }

    /// Words that point back at something the user said. Bare "前に" / "私の" / "メモ" are left out:
    /// "出発の前に" or "私のPCが遅い" are web questions and should keep page fetching.
    private static let memoryWords = [
        "前に話", "前に決め", "前に言", "前に相談", "前に考え", "前にメモ", "前に保存", "この前", "このまえ", "こないだ", "前回",
        "たっけ", "だっけ", "決めた", "決めてた", "話した", "話してた", "言ってた", "相談した", "考えてた", "覚えてる", "覚えている",
        "記憶に", "記憶から", "メモした", "メモしてた", "メモってた", "保存した", "記録した", "好み"
    ]

    /// "京都の宿、前にどうするって決めたっけ？" points at the user's saved notes. Only these questions
    /// read the memory folder, and they get no page fetching, so a web page cannot carry the notes away.
    static func isMemoryQuestion(_ text: String) -> Bool {
        memoryWords.contains(where: text.contains)
    }

    // MARK: Sales / settings

    static func isSalesQuestion(_ text: String) -> Bool {
        ["売上", "売り上げ", "受注", "注文数", "注文件数"].contains(where: text.contains)
    }

    /// "今日買ったものはいつ届く？" / "注文状況" / "シャンプーはいつ来る？" — the user's own purchases.
    static func isOrderStatusQuestion(_ text: String) -> Bool {
        let deliveryWords = ["届く", "届いた", "届き", "配達", "配送", "到着", "いつ来る", "いつくる", "発送", "出荷"]
        let orderWords = ["注文状況", "注文履歴", "注文したもの", "注文した物", "注文の記録", "買ったもの", "買った物", "買ったやつ", "購入したもの", "購入した物", "購入履歴", "購入の記録", "注文してるもの", "頼んだもの", "頼んだやつ"]
        if orderWords.contains(where: text.contains) { return true }
        guard deliveryWords.contains(where: text.contains) else { return false }
        return ["注文", "買った", "購入", "頼んだ", "荷物", "商品", "amazon", "アマゾン"].contains(where: text.lowercased().contains)
    }

    /// The wake word has already been removed, so only questions about the app itself match.
    static func isSettingsQuestion(_ text: String) -> Bool {
        ["設定を教えて", "今の設定", "現在の設定", "設定は", "設定って", "購入のやつ", "音声オン", "音声オフ", "自動起動", "ログイン時に起動", "noteの登録", "連携状況",
         "何ができる", "なにができる", "できること", "使い方", "ヘルプ", "このアプリ", "自己紹介", "誰", "だれ"].contains(where: text.contains)
    }
}
