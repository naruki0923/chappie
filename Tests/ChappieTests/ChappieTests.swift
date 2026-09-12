import Foundation
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs == rhs) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTAssertNotNil<T>(_ value: T?) { precondition(value != nil) }
func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }
@main struct ChappieTests {
    @MainActor static func main() {
        let tests = ChappieTests()
        tests.testWakeAndSameUtterance()
        tests.testPurchaseLimitsAndDuplicates()
        tests.testLookalikeAndInvalidRules()
        tests.testProductNameMatching()
        tests.testPurchaseIntent()
        tests.testConfirmationAnswers()
        tests.testCalendarRouting()
        tests.testEventDraft()
        tests.testFileAndOtherRouting()
        tests.testSavePreservesRuleID()
        tests.testRegistrationByChat()
        tests.testRuleChangeAndRemoval()
        tests.testRemoveRule()
        tests.testReminderDrafts()
        print("PASS: wake phrase, utterance extraction, purchase matching, limits, duplicate protection, URL validation, intent routing, confirmation answers, event drafts, chat registration, reminders")
    }
    func testWakeAndSameUtterance() {
        XCTAssertEqual(WakePhrase.command(in: "ねえチャッピー、今日の予定"), "今日の予定")
        XCTAssertEqual(WakePhrase.command(in: "ちゃっぴー"), "")
        XCTAssertEqual(WakePhrase.command(in: "チャピー 今日の予定"), "今日の予定")
        XCTAssertEqual(WakePhrase.command(in: "ねえチャピ、シャンプー買って"), "シャンプー買って")
        XCTAssertEqual(WakePhrase.command(in: "Chappie hello"), "hello")
        XCTAssertNil(WakePhrase.command(in: "今日の予定"))
    }
    func testPurchaseLimitsAndDuplicates() {
        let rule = PurchaseRule(name: "シャンプー", url: URL(string: "https://www.amazon.co.jp/dp/EXAMPLE")!, quantity: 1, maxTotalYen: 2000)
        XCTAssertNil(rule.validationError)
        XCTAssertTrue(rule.canCheckout(actualTotalYen: 2000, actualQuantity: 1, subscription: false, lastPurchased: nil))
        XCTAssertFalse(rule.canCheckout(actualTotalYen: 2001, actualQuantity: 1, subscription: false, lastPurchased: nil))
        XCTAssertFalse(rule.canCheckout(actualTotalYen: 1000, actualQuantity: 2, subscription: false, lastPurchased: nil))
        XCTAssertFalse(rule.canCheckout(actualTotalYen: 1000, actualQuantity: 1, subscription: true, lastPurchased: nil))
        XCTAssertFalse(rule.canCheckout(actualTotalYen: 1000, actualQuantity: 1, subscription: false, lastPurchased: Date()))
    }
    func testLookalikeAndInvalidRules() {
        for link in ["http://amazon.co.jp/x", "https://amazon.co.jp.evil.example/x", "https://evilamazon.co.jp/x", "https://user:password@amazon.co.jp/x"] {
            XCTAssertNotNil(PurchaseRule(name: "商品", url: URL(string: link)!, quantity: 1, maxTotalYen: 100).validationError)
        }
        XCTAssertNotNil(PurchaseRule(name: "", url: URL(string: "https://amazon.co.jp")!, quantity: 0, maxTotalYen: 0).validationError)
    }
    func testProductNameMatching() {
        XCTAssertTrue(ProductNameMatcher.matches(command: "ディフューザー買って", productName: "ディヒューザー"))
        XCTAssertTrue(ProductNameMatcher.matches(command: "ディフューザーを購入して", productName: "ディフューザー"))
        XCTAssertTrue(ProductNameMatcher.matches(command: "しゃんぷ注文して", productName: "シャンプー"))
        XCTAssertTrue(ProductNameMatcher.matches(command: "ヘアーオイルお願い", productName: "ヘアオイル"))
        XCTAssertFalse(ProductNameMatcher.matches(command: "シャンプー買って", productName: "ディフューザー"))
    }
    func testPurchaseIntent() {
        XCTAssertEqual(Intent.purchaseIntent("シャンプー買って"), .explicit)
        XCTAssertEqual(Intent.purchaseIntent("購入したい。AmazonかTikTok Shopで、商品：シャンプー"), .explicit)
        XCTAssertEqual(Intent.purchaseIntent("柔軟剤を注文しといて"), .explicit)
        XCTAssertEqual(Intent.purchaseIntent("旅行のプランをお願い"), .soft)
        XCTAssertEqual(Intent.purchaseIntent("新しいマウスが欲しい"), .soft)
        XCTAssertEqual(Intent.purchaseIntent("来月の旅行の予定を考えて"), .none)
        XCTAssertTrue(Intent.isPurchasableListRequest("何が買える？"))
        XCTAssertTrue(Intent.isPurchasableListRequest("登録商品を教えて"))
    }
    func testConfirmationAnswers() {
        for yes in ["いいよ", "いいよ。", "はい、いいよ", "うん", "オッケー", "OK", "お願いします", "それで進めて", "はい"] {
            XCTAssertTrue(Intent.isAffirmative(yes))
            XCTAssertFalse(Intent.isNegative(yes))
        }
        for no in ["やめて", "いいえ", "キャンセル", "やめといて", "いや、やめて", "いらない", "ちょっと待って", "だめ"] {
            XCTAssertTrue(Intent.isNegative(no))
            XCTAssertFalse(Intent.isAffirmative(no))
        }
        XCTAssertFalse(Intent.isAffirmative("今日の予定"))
        XCTAssertFalse(Intent.isNegative("今日の予定"))
        XCTAssertFalse(Intent.isAffirmative(""))
    }
    func testCalendarRouting() {
        for lookup in ["今日の予定", "明日の予定を教えて", "今週の予定は？", "カレンダー見せて", "来週空いてる？", "予定を調べて", "Appleカレンダーと連携できてる？"] {
            XCTAssertTrue(Intent.isCalendarLookup(lookup))
            XCTAssertFalse(Intent.isCalendarAddition(lookup))
        }
        for planning in ["来月の旅行の予定を考えて", "旅行の予定を立てて", "週末の予定のおすすめは？", "出張のプランを提案して"] {
            XCTAssertFalse(Intent.isCalendarLookup(planning))
            XCTAssertFalse(Intent.isCalendarAddition(planning))
        }
        for addition in ["明日15時に会議を入れて", "来週の火曜日10時に歯医者の予定を追加して", "9月20日 14:00 打ち合わせを登録して", "金曜の夜に会食を入れといて"] {
            XCTAssertTrue(Intent.isCalendarAddition(addition))
        }
        XCTAssertFalse(Intent.isCalendarAddition("シャンプー買って"))
        XCTAssertTrue(Intent.isTravelEvent("沖縄旅行"))
        XCTAssertTrue(Intent.isTravelEvent("大阪出張"))
        XCTAssertFalse(Intent.isTravelEvent("定例会議"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 10))!
        let today = Intent.lookupRange("今日の予定", now: saturday, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: today.start), 12)
        XCTAssertEqual(calendar.component(.day, from: today.end), 13)
        let tomorrow = Intent.lookupRange("明日の予定", now: saturday, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: tomorrow.start), 13)
        let nextWeek = Intent.lookupRange("来週の予定", now: saturday, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: nextWeek.start), 14)
        XCTAssertEqual(calendar.component(.weekday, from: nextWeek.start), 2)
        XCTAssertEqual(calendar.component(.day, from: nextWeek.end), 21)
        let week = Intent.lookupRange("今週の予定", now: saturday, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: week.end), 19)
    }
    func testEventDraft() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let meeting = Intent.eventDraft(from: "明日15時に会議を入れて", now: now, calendar: calendar)
        XCTAssertNotNil(meeting)
        XCTAssertEqual(meeting?.title, "会議")
        XCTAssertEqual(meeting.map { calendar.component(.hour, from: $0.start) }, 15)
        XCTAssertEqual(meeting.map { $0.end.timeIntervalSince($0.start) }, 3600)
        XCTAssertEqual(meeting?.allDay, false)
        XCTAssertEqual(meeting.map { calendar.isDate($0.start, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now)!) }, true)

        let dentist = Intent.eventDraft(from: "来週の火曜日10時に歯医者の予定を追加して", now: now, calendar: calendar)
        XCTAssertEqual(dentist?.title, "歯医者")
        XCTAssertEqual(dentist.map { calendar.component(.hour, from: $0.start) }, 10)

        let dinner = Intent.eventDraft(from: "10/3 19時 田中さんと会食を登録して", now: now, calendar: calendar)
        XCTAssertEqual(dinner?.title, "田中さんと会食")
        XCTAssertEqual(dinner.map { calendar.component(.month, from: $0.start) }, 10)
        XCTAssertEqual(dinner.map { calendar.component(.day, from: $0.start) }, 3)

        let trip = Intent.eventDraft(from: "9月20日に沖縄旅行を入れて", now: now, calendar: calendar)
        XCTAssertEqual(trip?.title, "沖縄旅行")
        XCTAssertEqual(trip?.allDay, true)
        XCTAssertEqual(trip.map { $0.end.timeIntervalSince($0.start) }, 86400)

        XCTAssertNil(Intent.eventDraft(from: "会議を入れて", now: now, calendar: calendar))
    }
    func testFileAndOtherRouting() {
        XCTAssertEqual(Intent.fileSearchTerm("ファイル 請求書"), "請求書")
        XCTAssertEqual(Intent.fileSearchTerm("請求書のファイルを探して"), "請求書")
        XCTAssertEqual(Intent.fileSearchTerm("ファイル"), "")
        XCTAssertNil(Intent.fileSearchTerm("旅行のファイルを作って"))
        XCTAssertNil(Intent.fileSearchTerm("今日の予定"))
        XCTAssertTrue(Intent.isSalesQuestion("今日の売上は？"))
        XCTAssertFalse(Intent.isSalesQuestion("レストランの注文方法を教えて"))
        XCTAssertTrue(Intent.isSettingsQuestion("今の設定を教えて"))
        XCTAssertTrue(Intent.isSettingsQuestion("何ができる？"))
        XCTAssertFalse(Intent.isSettingsQuestion("旅行の案を出して"))
        XCTAssertEqual(WakePhrase.command(in: "チャッピー、旅行の案を出して"), "旅行の案を出して")
    }
    @MainActor func testSavePreservesRuleID() {
        let store = Connections(defaults: UserDefaults(suiteName: "local.chappie.tests.\(UUID().uuidString)")!)
        let first = PurchaseRule(name: "シャンプー", url: URL(string: "https://www.amazon.co.jp/dp/EXAMPLE")!, quantity: 1, maxTotalYen: 0)
        XCTAssertNil(store.save(first))
        let replacement = PurchaseRule(name: "シャンプー", url: URL(string: "https://www.amazon.co.jp/dp/EXAMPLE2")!, quantity: 2, maxTotalYen: 3000)
        XCTAssertNil(store.save(replacement))
        XCTAssertEqual(store.products.count, 1)
        XCTAssertEqual(store.products[0].id, first.id)
        XCTAssertEqual(store.products[0].quantity, 2)
    }
    func testRegistrationByChat() {
        let link = "https://www.amazon.co.jp/dp/B0FS22VBRJ?ref=ppx_yo2ov_dt_b_fed_asin_title&th=1"
        let basic = Intent.registrationRequest("このURLをシャンプーとして登録して \(link)")
        XCTAssertEqual(basic?.name, "シャンプー")
        XCTAssertEqual(basic?.url.absoluteString, link)
        XCTAssertEqual(basic?.quantity, 1)
        XCTAssertEqual(basic?.maxTotalYen, 0)

        let detailed = Intent.registrationRequest("\(link) これを洗濯洗剤で登録、2個、上限3,000円まで")
        XCTAssertEqual(detailed?.name, "洗濯洗剤")
        XCTAssertEqual(detailed?.quantity, 2)
        XCTAssertEqual(detailed?.maxTotalYen, 3000)

        let remembered = Intent.registrationRequest(WakePhrase.command(in: "チャッピー、\(link) はトリートメントって覚えて")!)
        XCTAssertEqual(remembered?.name, "トリートメント")

        XCTAssertEqual(Intent.registrationRequest("\(link) 登録して")?.name, "")
        XCTAssertNil(Intent.registrationRequest("シャンプーを登録して"))
        XCTAssertNil(Intent.registrationRequest("\(link) この商品の価格を調べて"))
        XCTAssertNil(Intent.registrationRequest("明日15時に会議を登録して"))
    }
    func testRuleChangeAndRemoval() {
        XCTAssertEqual(Intent.ruleChange("シャンプーは2個にして"), Intent.RuleChange(quantity: 2, maxTotalYen: nil))
        XCTAssertEqual(Intent.ruleChange("シャンプーの上限を2,000円にして"), Intent.RuleChange(quantity: nil, maxTotalYen: 2000))
        XCTAssertEqual(Intent.ruleChange("柔軟剤は上限なしにして"), Intent.RuleChange(quantity: nil, maxTotalYen: 0))
        XCTAssertNil(Intent.ruleChange("シャンプー買って"))
        XCTAssertNil(Intent.ruleChange("明日15時にして"))
        XCTAssertTrue(Intent.isRemovalRequest("ウイスキーは登録から外して"))
        XCTAssertTrue(Intent.isRemovalRequest("ウイスキー削除して"))
        XCTAssertFalse(Intent.isRemovalRequest("ウイスキー買って"))
        XCTAssertTrue(ProductNameMatcher.matches(command: "ウイスキーは登録から外して", productName: "ウイスキー"))
    }
    @MainActor func testRemoveRule() {
        let store = Connections(defaults: UserDefaults(suiteName: "local.chappie.tests.\(UUID().uuidString)")!)
        let rule = PurchaseRule(name: "シャンプー", url: URL(string: "https://www.amazon.co.jp/dp/EXAMPLE")!, quantity: 1, maxTotalYen: 0)
        XCTAssertNil(store.save(rule))
        store.remove(rule)
        XCTAssertEqual(store.products.count, 0)
    }
    func testReminderDrafts() {
        let now = Date()
        let calendar = Calendar.current
        let call = Intent.reminderDraft(from: "30分後に電話するのを教えて", now: now, calendar: calendar)
        XCTAssertEqual(call?.title, "電話")
        XCTAssertEqual(call.map { Int($0.due.timeIntervalSince(now).rounded()) }, 1800)

        let soon = Intent.reminderDraft(from: "あと10分で会議って教えて", now: now, calendar: calendar)
        XCTAssertEqual(soon?.title, "会議")
        XCTAssertEqual(soon.map { Int($0.due.timeIntervalSince(now).rounded()) }, 600)

        let rest = Intent.reminderDraft(from: "1時間後に休憩", now: now, calendar: calendar)
        XCTAssertEqual(rest?.title, "休憩")

        let transfer = Intent.reminderDraft(from: "金曜に振込をリマインドして", now: now, calendar: calendar)
        XCTAssertEqual(transfer?.title, "振込")
        XCTAssertEqual(transfer.map { calendar.component(.weekday, from: $0.due) }, 6)
        XCTAssertEqual(transfer.map { calendar.component(.hour, from: $0.due) }, 9)

        let leave = Intent.reminderDraft(from: "18時になったら帰る準備を知らせて", now: now, calendar: calendar)
        XCTAssertEqual(leave?.title, "帰る準備")
        XCTAssertEqual(leave.map { calendar.component(.hour, from: $0.due) }, 18)

        let medicine = Intent.reminderDraft(from: "明日の朝、薬を飲むのを思い出させて", now: now, calendar: calendar)
        XCTAssertEqual(medicine?.title, "薬を飲む")

        XCTAssertNil(Intent.reminderDraft(from: "今日の予定を教えて", now: now, calendar: calendar))
        XCTAssertNil(Intent.reminderDraft(from: "明日15時に会議を入れて", now: now, calendar: calendar))
        XCTAssertNil(Intent.reminderDraft(from: "シャンプー買って", now: now, calendar: calendar))
        XCTAssertTrue(Intent.isReminderListRequest("リマインドの一覧を見せて"))
        XCTAssertFalse(Intent.isReminderListRequest("30分後にリマインドして"))
    }
}
