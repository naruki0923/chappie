import Foundation

/// The seven kinds on the Matsuyama city calendar, with the rules printed beside each one.
enum GarbageKind: String, CaseIterable, Equatable {
    case burnable = "可燃ごみ"
    case plastic = "プラスチック製容器包装"
    case paper = "紙類"
    case metalGlass = "金物・ガラス類"
    case petBottle = "ペットボトル"
    case landfill = "埋立ごみ"
    case mercury = "水銀ごみ"

    var deadlineHour: Int { self == .burnable ? 7 : 8 }
    var deadline: String { "午前\(deadlineHour)時" }

    var howToPutOut: String {
        switch self {
        case .burnable: return "白色半透明袋（45ℓ以下）で。白色半透明のレジ袋も使えます"
        case .plastic: return "無色透明袋（45ℓ以下）で、袋は二重にしないでください。すすいで汚れを取ってから"
        case .paper: return "十文字にひもを掛けて。新聞・紙パック・段ボール・本類雑がみの4分別。ビニール袋・米袋は使えません"
        case .metalGlass: return "無色透明袋（45ℓ以下）で。刃物や割れガラスは紙に包んで「われもの」と書く"
        case .petBottle: return "無色透明袋（45ℓ以下）で、中をすすいで。キャップとラベルはプラスチック製容器包装へ"
        case .landfill: return "無色透明袋（45ℓ以下）で。土のう袋は使えません"
        case .mercury: return "無色透明袋（45ℓ以下）で。割れているものは新聞紙などに包む。LEDは粗大ごみ"
        }
    }

    var rule: String {
        switch self {
        case .burnable: return "毎週火曜・金曜"
        case .plastic: return "毎週月曜"
        case .paper: return "隔週の木曜"
        case .metalGlass: return "隔週の木曜"
        case .petBottle: return "第1・第3水曜"
        case .landfill: return "毎月第4水曜"
        case .mercury: return "6・9・12・3月の第2水曜"
        }
    }

    /// Words a person uses for the kind or for things that go in it ("蛍光灯" → 水銀ごみ).
    /// Longer entries are matched first so "ペットボトルのキャップ" lands on プラ, not ペットボトル.
    static let aliases: [(word: String, kind: GarbageKind)] = [
        ("ペットボトルのキャップ", .plastic), ("ペットボトルのラベル", .plastic),
        ("プラスチック製容器包装", .plastic), ("プラスチック容器", .plastic), ("プラスチック", .plastic), ("プラごみ", .plastic), ("プラゴミ", .plastic),
        ("プラ容器", .plastic), ("プラの日", .plastic), ("プラは", .plastic), ("プラって", .plastic), ("プラ、", .plastic),
        ("食品トレイ", .plastic), ("トレイ", .plastic), ("発泡スチロール", .plastic), ("レジ袋", .plastic), ("ポリ袋", .plastic),
        ("ペットボトル", .petBottle), ("ペット", .petBottle),
        ("可燃ごみ", .burnable), ("可燃ゴミ", .burnable), ("可燃", .burnable), ("燃えるごみ", .burnable), ("燃えるゴミ", .burnable), ("燃やせるごみ", .burnable),
        ("生ごみ", .burnable), ("生ゴミ", .burnable), ("衣類", .burnable), ("古着", .burnable), ("布団", .burnable), ("木の枝", .burnable), ("アルミ箔", .burnable), ("ライター", .burnable),
        ("紙類", .paper), ("古紙", .paper), ("新聞", .paper), ("段ボール", .paper), ("ダンボール", .paper), ("雑誌", .paper), ("雑がみ", .paper), ("雑紙", .paper),
        ("紙パック", .paper), ("牛乳パック", .paper), ("本類", .paper), ("チラシ", .paper),
        ("金物・ガラス類", .metalGlass), ("金物ガラス", .metalGlass), ("金物", .metalGlass), ("金・ガ", .metalGlass), ("ガラス", .metalGlass),
        ("スチール缶", .metalGlass), ("アルミ缶", .metalGlass), ("空き缶", .metalGlass), ("缶", .metalGlass), ("スプレー缶", .metalGlass), ("カセットボンベ", .metalGlass),
        ("包丁", .metalGlass), ("刃物", .metalGlass), ("フライパン", .metalGlass), ("やかん", .metalGlass), ("なべ", .metalGlass), ("鍋", .metalGlass),
        ("埋立ごみ", .landfill), ("埋立ゴミ", .landfill), ("埋め立て", .landfill), ("埋立", .landfill),
        ("乾電池", .landfill), ("電池", .landfill), ("陶磁器", .landfill), ("茶碗", .landfill), ("植木鉢", .landfill), ("土なべ", .landfill), ("ブロック", .landfill), ("レンガ", .landfill),
        ("水銀ごみ", .mercury), ("水銀ゴミ", .mercury), ("水銀", .mercury), ("蛍光灯", .mercury), ("電球", .mercury), ("体温計", .mercury), ("ボタン電池", .mercury), ("ボタン型電池", .mercury)
    ]

    /// The kind named in the text, plus the item word when it was a thing rather than the
    /// kind itself ("蛍光灯" → (.mercury, "蛍光灯"); "水銀ごみ" → (.mercury, nil)).
    static func named(in text: String) -> (kind: GarbageKind, item: String?)? {
        guard let match = aliases.sorted(by: { $0.word.count > $1.word.count }).first(where: { text.contains($0.word) }) else { return nil }
        let isKindName = match.word.hasPrefix(match.kind.rawValue.prefix(2)) || match.word == "ペット" || match.word == "金・ガ" || match.word == "埋め立て"
        return (match.kind, isKindName ? nil : match.word)
    }
}

/// One district's collection days, copied from the printed calendar. Only the printed year
/// is known, so questions outside the range say so instead of guessing from the weekly rule.
struct GarbageCalendar {
    let area: String
    let coverageStart: Date   // inclusive
    let coverageEnd: Date     // exclusive
    private let collections: [String: GarbageKind]   // "2026-04-01" → kind
    private let suspended: Set<String>               // days marked 休止 / 収集なし

    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Each month is "day+code" pairs as they read on the calendar: 可 プ 紙 金 ペ 埋 水, and 休 for a suspended day.
    init(area: String, start: String, end: String, months: [String: String]) {
        self.area = area
        coverageStart = Self.keyFormatter.date(from: start)!
        coverageEnd = Self.keyFormatter.date(from: end)!
        var collections: [String: GarbageKind] = [:]
        var suspended: Set<String> = []
        let codes: [Character: GarbageKind] = ["可": .burnable, "プ": .plastic, "紙": .paper, "金": .metalGlass, "ペ": .petBottle, "埋": .landfill, "水": .mercury]
        for (month, entries) in months {
            for entry in entries.split(separator: " ") {
                let day = Int(entry.filter(\.isNumber))!
                let key = "\(month)-" + String(format: "%02d", day)
                let code = entry.last!
                if code == "休" { suspended.insert(key); continue }
                collections[key] = codes[code]!
            }
        }
        self.collections = collections
        self.suspended = suspended
    }

    static func key(_ date: Date) -> String { keyFormatter.string(from: date) }

    func covers(_ date: Date) -> Bool { date >= coverageStart && date < coverageEnd }
    func kind(on date: Date) -> GarbageKind? { collections[Self.key(date)] }
    func isSuspended(_ date: Date) -> Bool { suspended.contains(Self.key(date)) }

    /// Next collection of a kind on or after `date`, plus the one after it, within the printed year.
    func nextDates(of kind: GarbageKind, from date: Date, count: Int = 2, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: date)
        while day < coverageEnd, result.count < count {
            if self.kind(on: day) == kind { result.append(day) }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    /// Every day in [start, end) with what is collected, so a week can be read out in order.
    func days(from start: Date, to end: Date, calendar: Calendar = .current) -> [(date: Date, kind: GarbageKind?, suspended: Bool)] {
        var result: [(Date, GarbageKind?, Bool)] = []
        var day = calendar.startOfDay(for: start)
        while day < end {
            result.append((day, kind(on: day), isSuspended(day)))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    /// 粗大ごみ申込期間（収集期間ではない）。区分Dは萱町6丁目、衣山1丁目、平和通5丁目、木屋町1・2丁目、吉藤2丁目、Cはそれ以外。
    static let bulkyApplicationPeriods: [(area: String, periods: [String])] = [
        ("C", ["4/1〜4/14", "6/3〜6/16", "7/29〜8/11", "9/30〜10/13", "11/25〜12/8", "2/3〜2/16"]),
        ("D", ["4/15〜4/28", "6/17〜6/30", "8/19〜9/1", "10/14〜10/27", "12/9〜12/22", "2/17〜3/2"])
    ]
    static let bulkyAreaD = "萱町6丁目、衣山1丁目、平和通5丁目、木屋町1丁目と2丁目、吉藤2丁目"

    /// 松山市 清水地区「2026年度 ごみカレンダー」(2026年4月〜2027年3月)。
    /// 10月7日と年始（1/1〜1/3）は収集なし。
    static let shimizu2026 = GarbageCalendar(area: "松山市 清水地区", start: "2026-04-01", end: "2027-04-01", months: [
        "2026-04": "1ペ 2金 3可 6プ 7可 9紙 10可 13プ 14可 15ペ 16金 17可 20プ 21可 22埋 23紙 24可 27プ 28可 30金",
        "2026-05": "1可 4プ 5可 6ペ 7紙 8可 11プ 12可 14金 15可 18プ 19可 20ペ 21紙 22可 25プ 26可 27埋 28金 29可",
        "2026-06": "1プ 2可 3ペ 4紙 5可 8プ 9可 10水 11金 12可 15プ 16可 17ペ 18紙 19可 22プ 23可 24埋 25金 26可 29プ 30可",
        "2026-07": "1ペ 2紙 3可 6プ 7可 9金 10可 13プ 14可 15ペ 16紙 17可 20プ 21可 22埋 23金 24可 27プ 28可 30紙 31可",
        "2026-08": "3プ 4可 5ペ 6金 7可 10プ 11可 13紙 14可 17プ 18可 19ペ 20金 21可 24プ 25可 26埋 27紙 28可 31プ",
        "2026-09": "1可 2ペ 3金 4可 7プ 8可 9水 10紙 11可 14プ 15可 16ペ 17金 18可 21プ 22可 23埋 24紙 25可 28プ 29可",
        "2026-10": "1金 2可 5プ 6可 7休 8紙 9可 12プ 13可 15金 16可 19プ 20可 21ペ 22紙 23可 26プ 27可 28埋 29金 30可",
        "2026-11": "2プ 3可 4ペ 5紙 6可 9プ 10可 12金 13可 16プ 17可 18ペ 19紙 20可 23プ 24可 25埋 26金 27可 30プ",
        "2026-12": "1可 2ペ 3紙 4可 7プ 8可 9水 10金 11可 14プ 15可 16ペ 17紙 18可 21プ 22可 23埋 24金 25可 28プ 29可 31紙",
        "2027-01": "1休 2休 3休 4プ 5可 6ペ 7金 8可 11プ 12可 14紙 15可 18プ 19可 20ペ 21金 22可 25プ 26可 27埋 28紙 29可",
        "2027-02": "1プ 2可 3ペ 4金 5可 8プ 9可 11紙 12可 15プ 16可 17ペ 18金 19可 22プ 23可 24埋 25紙 26可",
        "2027-03": "1プ 2可 3ペ 4金 5可 8プ 9可 10水 11紙 12可 15プ 16可 17ペ 18金 19可 22プ 23可 24埋 25紙 26可 29プ 30可"
    ])
}

extension GarbageCalendar {
    /// Phrases the answer for reading aloud. Dates are compared to `now` so tests can pin the day.
    func answer(_ question: Intent.GarbageQuestion, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let dayFormatter = DateFormatter(); dayFormatter.locale = Locale(identifier: "ja_JP"); dayFormatter.dateFormat = "M/d(E)"
        let yearFormatter = DateFormatter(); yearFormatter.locale = Locale(identifier: "ja_JP"); yearFormatter.dateFormat = "yyyy/M/d(E)"
        let today = calendar.startOfDay(for: now)
        // "3/10(水)" is enough within the year; across New Year the year is said too.
        func name(_ date: Date) -> String {
            calendar.component(.year, from: date) == calendar.component(.year, from: today) ? dayFormatter.string(from: date) : yearFormatter.string(from: date)
        }
        func relative(_ date: Date) -> String {
            let days = calendar.dateComponents([.day], from: today, to: date).day ?? 0
            switch days {
            case 0: return "今日"
            case 1: return "明日"
            case 2: return "明後日"
            default: return "\(days)日後"
            }
        }
        func outOfRange() -> String {
            "手元のごみカレンダー（\(area)・2026年度）は2026年4月〜2027年3月分だけなので、その日は分かりません。"
        }
        func nextLine(_ kind: GarbageKind, from date: Date) -> String {
            let dates = nextDates(of: kind, from: date, calendar: calendar)
            guard let first = dates.first else { return "\(kind.rawValue)の次の収集日は、2027年3月までのカレンダーには載っていません。" }
            var line = "次の\(kind.rawValue)は\(name(first))、\(relative(first))です。"
            if dates.count > 1 { line += "その次は\(name(dates[1]))。" }
            return line
        }

        switch question {
        case .bulky:
            guard covers(today) else { return outOfRange() }
            var lines = ["粗大ごみは集積場所には出せません。戸別収集（年6回）で、専用のハガキかインターネットでの事前申込みが必要です。収集日は午前8時までに。"]
            for entry in Self.bulkyApplicationPeriods {
                lines.append("申込期間（区分\(entry.area)）：" + entry.periods.joined(separator: "、"))
            }
            lines.append("区分Dは\(Self.bulkyAreaD)、それ以外は区分Cです。申込期間は収集期間ではありません。詳しくは「粗大ごみ収集申込みガイド」を見てください。家電4品目やスプリングマットレスは市では収集しません。")
            return lines.joined(separator: "\n")

        case .rechargeableBattery:
            return "充電式電池（小型充電式電池・モバイルバッテリーなど）は集積場所には出せません。市役所本館1階、各支所、総合コミュニティセンター、りっくる（まつやまRe・再来館）、清掃課のリサイクルBOXへ持ち込んでください（無料）。事業活動に伴うものは対象外です。"

        case .nonBurnable:
            guard covers(today) else { return outOfRange() }
            var lines = ["\(area)に「不燃ごみ」の区分はありません。金物・ガラス類、埋立ごみ（乾電池・陶磁器・植木鉢など）、水銀ごみ（蛍光灯・電球・体温計）に分かれます。"]
            for kind in [GarbageKind.metalGlass, .landfill, .mercury] { lines.append(nextLine(kind, from: today)) }
            return lines.joined(separator: "\n")

        case .next(let kind, let item):
            guard covers(today) else { return outOfRange() }
            var lines = [nextLine(kind, from: today), "\(kind.rule)、\(kind.deadline)までに。\(kind.howToPutOut)。"]
            if let item {
                lines.insert("\(item)は\(kind.rawValue)です。", at: 0)
                // "電池" covers three routes on the sheet; name the other two.
                if item.hasSuffix("電池"), kind == .landfill { lines.insert("ボタン型電池は水銀ごみ、充電式電池は市の施設のリサイクルBOXへ。", at: 1) }
            }
            return lines.joined(separator: "\n")

        case .days(let start, let end, let label, let kind):
            guard covers(start) else { return outOfRange() }
            let rows = days(from: start, to: min(end, coverageEnd), calendar: calendar)
            var lines: [String] = []
            if rows.count == 1, let day = rows.first {
                let when = label.isEmpty ? name(day.date) : "\(label)（\(name(day.date))）"
                if day.suspended {
                    lines.append("\(when)はごみ収集はありません（休止）。")
                } else if let collected = day.kind {
                    lines.append("\(when)は\(collected.rawValue)の日です。\(collected.deadline)までに、\(collected.howToPutOut)。")
                    // Asked after the truck has been: say so, and when that kind comes round again.
                    if day.date == today, calendar.component(.hour, from: now) >= collected.deadlineHour {
                        let later = nextDates(of: collected, from: calendar.date(byAdding: .day, value: 1, to: today)!, count: 1, calendar: calendar)
                        var note = "今日の\(collected.deadline)はもう過ぎています。"
                        if let later = later.first { note += "次の\(collected.rawValue)は\(name(later))、\(relative(later))です。" }
                        lines.append(note)
                    }
                } else {
                    lines.append("\(when)はごみの収集はありません。")
                }
                // Tell them what comes next so "今日は？" on a quiet day is still useful.
                let upcoming = days(from: calendar.date(byAdding: .day, value: 1, to: day.date)!, to: coverageEnd, calendar: calendar)
                    .first { $0.kind != nil }
                if day.kind == nil, let upcoming, let upcomingKind = upcoming.kind {
                    lines.append("次の収集は\(name(upcoming.date))の\(upcomingKind.rawValue)です。")
                }
            } else {
                lines.append("\(label.isEmpty ? name(start) + "から" : label)のごみ収集です。")
                for day in rows {
                    let name = name(day.date)
                    if day.suspended { lines.append("\(name)  収集なし（休止）") }
                    else if let collected = day.kind { lines.append("\(name)  \(collected.rawValue)（\(collected.deadline)まで）") }
                }
                if end > coverageEnd { lines.append("2027年4月以降はカレンダーがありません。") }
            }
            if let kind, !rows.contains(where: { $0.kind == kind }) {
                lines.append(nextLine(kind, from: today))
            }
            return lines.joined(separator: "\n")
        }
    }
}
