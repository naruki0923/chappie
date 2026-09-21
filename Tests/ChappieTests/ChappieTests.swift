import Foundation
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, line: UInt = #line) { precondition(lhs == rhs, "line \(line): \(lhs) != \(rhs)") }
func XCTAssertNil<T>(_ value: T?, line: UInt = #line) { precondition(value == nil, "line \(line): expected nil, got \(value!)") }
func XCTAssertNotNil<T>(_ value: T?, line: UInt = #line) { precondition(value != nil, "line \(line): expected a value") }
func XCTAssertTrue(_ value: Bool, line: UInt = #line) { precondition(value, "line \(line): expected true") }
func XCTAssertFalse(_ value: Bool, line: UInt = #line) { precondition(!value, "line \(line): expected false") }
@main struct ChappieTests {
    @MainActor static func main() {
        let tests = ChappieTests()
        tests.testWakeAndSameUtterance()
        tests.testVoiceRenewalDelay()
        tests.testVoiceLogExcerpt()
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
        tests.testCalendarEdits()
        tests.testMailRequests()
        tests.testBooking()
        tests.testOrderStatus()
        tests.testGarbageCalendar()
        tests.testGarbageQuestions()
        print("PASS: wake phrase, recognition backoff, utterance extraction, purchase matching, limits, duplicate protection, URL validation, intent routing, confirmation answers, event drafts, chat registration, reminders, calendar edits, mail, booking, order status, garbage calendar")
    }
    func testVoiceLogExcerpt() {
        XCTAssertEqual(VoiceLog.excerpt("チャッピー"), "チャッピー")
        let long = String(repeating: "あ", count: 50)
        XCTAssertEqual(VoiceLog.excerpt(long), String(repeating: "あ", count: 40) + "…")
    }
    func testVoiceRenewalDelay() {
        // A task that errors right after starting is retried slowly; a normal final result or a late error is renewed at once.
        XCTAssertEqual(Voice.renewalDelay(afterError: true, elapsed: 0.2), 2_000_000_000)
        XCTAssertEqual(Voice.renewalDelay(afterError: true, elapsed: 5), 100_000_000)
        XCTAssertEqual(Voice.renewalDelay(afterError: false, elapsed: 0.2), 100_000_000)
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
    func testCalendarEdits() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 10))!

        guard case .move(let target, let newStart)? = Intent.calendarEdit("明日の会議を16時にずらして", now: saturday, calendar: calendar) else { preconditionFailure("move expected") }
        XCTAssertEqual(target.hint, "会議")
        XCTAssertEqual(calendar.component(.day, from: target.windowStart), 13)
        XCTAssertEqual(newStart, .timeOnly(hour: 16, minute: 0))

        guard case .move(let shifted, .shift(let seconds))? = Intent.calendarEdit("会議を30分後ろにずらして", now: saturday, calendar: calendar) else { preconditionFailure("shift expected") }
        XCTAssertEqual(shifted.hint, "会議")
        XCTAssertEqual(seconds, 1800)
        guard case .move(_, .shift(let earlier))? = Intent.calendarEdit("会議を1時間前にずらして", now: saturday, calendar: calendar) else { preconditionFailure("shift expected") }
        XCTAssertEqual(earlier, -3600)

        guard case .move(let dinner, .absolute(let when))? = Intent.calendarEdit("田中さんとの会食を明後日の19時に移して", now: saturday, calendar: calendar) else { preconditionFailure("absolute expected") }
        XCTAssertEqual(dinner.hint, "田中さんとの会食")
        // NSDataDetector resolves "明後日" against the real clock, not the test's fixed date.
        let dayAfterTomorrow = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        XCTAssertTrue(Calendar.current.isDate(when, inSameDayAs: dayAfterTomorrow))
        XCTAssertEqual(Calendar.current.component(.hour, from: when), 19)

        guard case .move(_, .dayOnly(let day))? = Intent.calendarEdit("定例を金曜に移して", now: saturday, calendar: calendar) else { preconditionFailure("dayOnly expected") }
        XCTAssertEqual(calendar.component(.weekday, from: day), 6)

        guard case .delete(let cancel)? = Intent.calendarEdit("今日の打ち合わせをキャンセルして", now: saturday, calendar: calendar) else { preconditionFailure("delete expected") }
        XCTAssertEqual(cancel.hint, "打ち合わせ")
        XCTAssertEqual(calendar.component(.day, from: cancel.windowStart), 12)
        guard case .delete(let tenOClock)? = Intent.calendarEdit("明日10時の会議を消して", now: saturday, calendar: calendar) else { preconditionFailure("delete expected") }
        XCTAssertEqual(tenOClock.hour, 10)

        guard case .freeSlots(let start, _, let label, let minutes)? = Intent.calendarEdit("来週で1時間空いてるところ", now: saturday, calendar: calendar) else { preconditionFailure("free slots expected") }
        XCTAssertEqual(label, "来週")
        XCTAssertEqual(minutes, 60)
        XCTAssertEqual(calendar.component(.day, from: start), 14)
        guard case .freeSlots(_, _, _, let defaultMinutes)? = Intent.calendarEdit("明日の空き時間", now: saturday, calendar: calendar) else { preconditionFailure("free slots expected") }
        XCTAssertEqual(defaultMinutes, 60)

        XCTAssertNil(Intent.calendarEdit("ウイスキーは登録から外して", now: saturday, calendar: calendar))
        XCTAssertNil(Intent.calendarEdit("今日の予定", now: saturday, calendar: calendar))
        XCTAssertNil(Intent.calendarEdit("明日15時に会議を入れて", now: saturday, calendar: calendar))
        XCTAssertTrue(Intent.eventMatches(title: "田中さん 会食", hint: "田中さんとの会食"))
        XCTAssertTrue(Intent.eventMatches(title: "週次定例MTG", hint: "定例"))
        XCTAssertFalse(Intent.eventMatches(title: "歯医者", hint: "会議"))
    }
    func testMailRequests() {
        XCTAssertEqual(Intent.mailRequest("未読メールを要約して"), .summary)
        XCTAssertEqual(Intent.mailRequest("Gmailに何か来てる？"), .summary)
        XCTAssertEqual(Intent.mailRequest("ジーメール確認して"), .summary)
        XCTAssertEqual(Intent.mailRequest("田中さんに10分遅れると連絡を下書きして"), .draft)
        XCTAssertEqual(Intent.mailRequest("佐藤さんのメールに返信して、来週なら大丈夫と伝えて"), .draft)
        XCTAssertEqual(Intent.mailRequest("山田さんにお礼のメールを書いて"), .draft)
        XCTAssertNil(Intent.mailRequest("今日の予定"))
        XCTAssertNil(Intent.mailRequest("シャンプー買って"))
        XCTAssertNil(Intent.mailRequest("田中さんに電話するのを30分後に教えて"))
    }
    func testBooking() {
        for text in ["20日の東京から新大阪の新幹線を取って", "その案で予約して", "沖縄のホテルを20日から22日で2人予約して", "渋谷で金曜19時に4人の店を予約したい", "飛行機を手配して"] {
            XCTAssertTrue(Intent.isBookingRequest(text))
        }
        for text in ["予約の確認", "シャンプー買って", "明日15時に会議を入れて", "旅行のプランを考えて"] {
            XCTAssertFalse(Intent.isBookingRequest(text))
        }
        let train = BookingPlan.parse("""
        {"kind":"train","origin":"東京","destination":"新大阪","area":null,"keyword":null,"date":"2026-09-20","time":"09:00","checkin":null,"checkout":null,"guests":null,"missing":[]}
        """)
        XCTAssertEqual(train?.kind, .train)
        XCTAssertEqual(train?.searchURL?.host, "transit.yahoo.co.jp")
        XCTAssertTrue(train?.searchURL?.query?.contains("y=2026&m=09&d=20") == true)
        XCTAssertTrue(train?.searchURL?.query?.contains("hh=9&m1=0&m2=0") == true)
        XCTAssertEqual(train?.summary, "新幹線・電車：東京→新大阪、9月20日 09:00")

        let hotel = BookingPlan.parse("結果です。```json\n{\"kind\":\"hotel\",\"area\":\"沖縄\",\"keyword\":\"海沿い\",\"checkin\":\"2026-09-20\",\"checkout\":\"2026-09-22\",\"guests\":2,\"missing\":[]}\n```")
        XCTAssertEqual(hotel?.kind, .hotel)
        XCTAssertEqual(hotel?.searchURL?.host, "www.booking.com")
        XCTAssertTrue(hotel?.searchURL?.query?.contains("checkin=2026-09-20&checkout=2026-09-22&group_adults=2") == true)

        let restaurant = BookingPlan.parse("{\"kind\":\"restaurant\",\"area\":\"渋谷\",\"keyword\":\"焼肉\",\"date\":\"2026-09-18\",\"time\":\"19:00\",\"guests\":4,\"missing\":[]}")
        XCTAssertEqual(restaurant?.searchURL?.host, "tabelog.com")
        XCTAssertTrue(restaurant?.searchURL?.query?.contains("svd=20260918&svt=1900&svps=4") == true)

        let incomplete = BookingPlan.parse("{\"kind\":\"hotel\",\"area\":\"沖縄\",\"missing\":[\"チェックイン日\",\"チェックアウト日\"]}")
        XCTAssertNil(incomplete?.searchURL)
        XCTAssertEqual(incomplete?.missing.count, 2)
        XCTAssertNil(BookingPlan.parse("分かりません"))
    }
    func testOrderStatus() {
        for text in ["今日買ったものはいつ届く？", "注文状況を教えて", "シャンプーの荷物いつ来る？", "Amazonで頼んだやつ届いた？", "購入履歴を見せて"] {
            XCTAssertTrue(Intent.isOrderStatusQuestion(text))
            XCTAssertFalse(Intent.isSalesQuestion(text))
        }
        for text in ["今日の売上は？", "受注は何件？", "今日の予定", "シャンプー買って", "明日届くように会議を入れて"] {
            XCTAssertFalse(Intent.isOrderStatusQuestion(text))
        }
        let card = """
        注文日
        2026年9月12日
        合計
        ￥1,210
        お届け先
        山田
        注文番号 249-1234567-7654321
        注文内容を表示 領収書等
        9月15日 月曜日にお届け予定
        シャンプー 詰め替え 400ml
        再度購入
        """
        let order = AmazonOrder.parse(text: card, items: ["シャンプー 詰め替え 400ml"])
        XCTAssertEqual(order?.orderedOn, "2026年9月12日")
        XCTAssertEqual(order?.totalYen, 1210)
        XCTAssertEqual(order?.orderNumber, "249-1234567-7654321")
        XCTAssertEqual(order?.status, "9月15日 月曜日にお届け予定")
        XCTAssertEqual(order?.items, ["シャンプー 詰め替え 400ml"])
        XCTAssertEqual(AmazonOrder.parse(text: "配達済み 9月10日", items: [])?.orderedOn, nil)
        let delivered = AmazonOrder.parse(text: "注文日\n2026年8月18日\n合計\n￥1,339\n注文番号 249-0000000-0000000\n9月3日にお届け済み\n炭酸水 ×24本\n自動配達済み： 2ヶ月ごと", items: ["炭酸水 ×24本"])
        XCTAssertEqual(delivered?.status, "9月3日にお届け済み")
        let cancelled = AmazonOrder.parse(text: "注文日\n2026年9月12日\n注文番号 249-0000000-0000001\nキャンセル済み\n注文はキャンセルされました。 この注文の請求は行われていません。\nシャンプー", items: ["シャンプー"])
        XCTAssertEqual(cancelled?.status, "キャンセル済み")
        XCTAssertEqual(cancelled?.totalYen, 0)
    }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }
    func testGarbageCalendar() {
        let sheet = GarbageCalendar.shimizu2026
        // Spot checks against the printed 清水地区 calendar.
        XCTAssertEqual(sheet.kind(on: date("2026-09-21 09:00")), .plastic)
        XCTAssertEqual(sheet.kind(on: date("2026-09-22 00:00")), .burnable)
        XCTAssertEqual(sheet.kind(on: date("2026-09-23 00:00")), .landfill)
        XCTAssertEqual(sheet.kind(on: date("2026-09-24 00:00")), .paper)
        XCTAssertEqual(sheet.kind(on: date("2026-09-09 00:00")), .mercury)
        XCTAssertEqual(sheet.kind(on: date("2026-10-01 00:00")), .metalGlass)
        XCTAssertEqual(sheet.kind(on: date("2026-10-21 00:00")), .petBottle)
        XCTAssertEqual(sheet.kind(on: date("2026-12-31 00:00")), .paper)
        XCTAssertNil(sheet.kind(on: date("2026-09-20 00:00")))       // Sunday
        XCTAssertNil(sheet.kind(on: date("2026-10-07 00:00")))       // 収集なし
        XCTAssertTrue(sheet.isSuspended(date("2026-10-07 00:00")))
        XCTAssertTrue(sheet.isSuspended(date("2027-01-01 00:00")))
        XCTAssertTrue(sheet.isSuspended(date("2027-01-03 00:00")))
        XCTAssertFalse(sheet.isSuspended(date("2026-09-21 00:00")))
        XCTAssertTrue(sheet.covers(date("2026-04-01 00:00")))
        XCTAssertTrue(sheet.covers(date("2027-03-31 23:00")))
        XCTAssertFalse(sheet.covers(date("2027-04-01 00:00")))
        XCTAssertFalse(sheet.covers(date("2026-03-31 00:00")))
        // Every printed weekday carries one mark, and the weekly rules hold.
        var day = sheet.coverageStart
        var counts: [GarbageKind: Int] = [:]
        while day < sheet.coverageEnd {
            let weekday = Calendar.current.component(.weekday, from: day)
            if let kind = sheet.kind(on: day) {
                counts[kind, default: 0] += 1
                switch kind {
                case .burnable: XCTAssertTrue(weekday == 3 || weekday == 6)
                case .plastic: XCTAssertEqual(weekday, 2)
                case .paper, .metalGlass: XCTAssertEqual(weekday, 5)
                case .petBottle, .landfill, .mercury: XCTAssertEqual(weekday, 4)
                }
            } else {
                // Only weekends, suspended days, and Wednesdays without a monthly pickup are blank.
                XCTAssertTrue(weekday == 1 || weekday == 7 || weekday == 4 || sheet.isSuspended(day))
            }
            day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        }
        XCTAssertEqual(counts[.plastic], 52)
        XCTAssertEqual(counts[.mercury], 4)
        XCTAssertEqual(counts[.landfill], 12)
        XCTAssertEqual(counts[.petBottle], 23)   // 24 minus the 10/7 suspension
        XCTAssertEqual((counts[.paper] ?? 0) + (counts[.metalGlass] ?? 0), 52)
        var thursday = date("2026-04-02 00:00")
        while thursday < sheet.coverageEnd {
            let following = Calendar.current.date(byAdding: .day, value: 7, to: thursday)!
            if following < sheet.coverageEnd { XCTAssertTrue(sheet.kind(on: thursday) != sheet.kind(on: following)) }
            thursday = following
        }
        // The next PET day after 10/6 skips the suspended 10/7.
        let pet = sheet.nextDates(of: .petBottle, from: date("2026-10-06 12:00"))
        XCTAssertEqual(pet.map { GarbageCalendar.key($0) }, ["2026-10-21", "2026-11-04"])
        XCTAssertEqual(sheet.nextDates(of: .mercury, from: date("2026-09-21 12:00")).map { GarbageCalendar.key($0) }, ["2026-12-09", "2027-03-10"])
        XCTAssertEqual(sheet.nextDates(of: .burnable, from: date("2027-03-30 12:00")).map { GarbageCalendar.key($0) }, ["2027-03-30"])
    }
    func testGarbageQuestions() {
        let now = date("2026-09-21 10:00")   // Monday, プラ day
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func d(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }
        XCTAssertEqual(Intent.garbageQuestion("今日は何のゴミの日？", now: now), .days(start: today, end: d(1), label: "今日", kind: nil))
        XCTAssertEqual(Intent.garbageQuestion("明日のごみは？", now: now), .days(start: d(1), end: d(2), label: "明日", kind: nil))
        XCTAssertEqual(Intent.garbageQuestion("明日は可燃ごみ？", now: now), .days(start: d(1), end: d(2), label: "明日", kind: .burnable))
        XCTAssertEqual(Intent.garbageQuestion("今週のゴミ収集", now: now), .days(start: today, end: d(7), label: "今週", kind: nil))
        XCTAssertEqual(Intent.garbageQuestion("水曜のゴミは何？", now: now), .days(start: d(2), end: d(3), label: "水曜日", kind: nil))
        XCTAssertEqual(Intent.garbageQuestion("来週の火曜はゴミ何？", now: now), .days(start: d(8), end: d(9), label: "火曜日", kind: nil))
        XCTAssertEqual(Intent.garbageQuestion("10月7日のゴミは？", now: now), .days(start: date("2026-10-07 00:00"), end: date("2026-10-08 00:00"), label: "", kind: nil))
        XCTAssertEqual(Intent.garbageQuestion("ペットボトルはいつ？", now: now), .next(.petBottle, item: nil))
        XCTAssertEqual(Intent.garbageQuestion("次の紙類のゴミの日は？", now: now), .next(.paper, item: nil))
        XCTAssertEqual(Intent.garbageQuestion("蛍光灯は何ゴミ？", now: now), .next(.mercury, item: "蛍光灯"))
        XCTAssertEqual(Intent.garbageQuestion("乾電池はいつ出せる？", now: now), .next(.landfill, item: "乾電池"))
        XCTAssertEqual(Intent.garbageQuestion("ペットボトルのキャップはどのゴミ？", now: now), .next(.plastic, item: "ペットボトルのキャップ"))
        XCTAssertEqual(Intent.garbageQuestion("可燃ごみは次いつ？", now: now), .next(.burnable, item: nil))
        XCTAssertEqual(Intent.garbageQuestion("プラスチックのゴミの日", now: now), .next(.plastic, item: nil))
        XCTAssertEqual(Intent.garbageQuestion("段ボールはいつ出す？", now: now), .next(.paper, item: "段ボール"))
        XCTAssertEqual(Intent.garbageQuestion("プラの日は？", now: now), .next(.plastic, item: nil))
        XCTAssertEqual(Intent.garbageQuestion("電池はどう捨てる？", now: now), .next(.landfill, item: "電池"))
        XCTAssertEqual(Intent.garbageQuestion("ボタン電池はいつ？", now: now), .next(.mercury, item: "ボタン電池"))
        XCTAssertEqual(Intent.garbageQuestion("充電式電池はいつ？", now: now), .rechargeableBattery)
        XCTAssertEqual(Intent.garbageQuestion("モバイルバッテリーの捨て方", now: now), .rechargeableBattery)
        XCTAssertTrue(GarbageCalendar.shimizu2026.answer(.rechargeableBattery, now: now).contains("リサイクルBOX"))
        XCTAssertEqual(Intent.garbageQuestion("粗大ゴミはいつ？", now: now), .bulky)
        XCTAssertEqual(Intent.garbageQuestion("粗大ごみの出し方", now: now), .bulky)
        XCTAssertEqual(Intent.garbageQuestion("不燃ごみは？", now: now), .nonBurnable)
        XCTAssertEqual(Intent.garbageQuestion("燃えないゴミはいつ？", now: now), .nonBurnable)
        XCTAssertEqual(Intent.garbageQuestion("空き缶はいつ出せる？", now: now), .next(.metalGlass, item: "空き缶"))
        XCTAssertEqual(Intent.garbageQuestion("年末年始のゴミ", now: now), .days(start: date("2026-12-28 00:00"), end: date("2027-01-09 00:00"), label: "年末年始", kind: nil))
        XCTAssertEqual(Intent.garbageQuestion("お正月のごみ収集", now: date("2027-01-02 10:00")), .days(start: date("2026-12-28 00:00"), end: date("2027-01-09 00:00"), label: "年末年始", kind: nil))
        XCTAssertEqual(Intent.garbageQuestion("来月のゴミ", now: now), .days(start: date("2026-10-01 00:00"), end: date("2026-11-01 00:00"), label: "来月", kind: nil))
        XCTAssertEqual(Intent.garbageQuestion("ゴミの日教えて", now: now), .days(start: today, end: d(7), label: "今日から1週間", kind: nil))
        XCTAssertEqual(Intent.garbageQuestion("ゴミの日教えてお願い", now: now), .days(start: today, end: d(7), label: "今日から1週間", kind: nil))
        XCTAssertTrue(Intent.isCalendarAddition("明日8時にゴミ出しを入れて"))
        for text in ["今日の予定", "旅行のプランを考えて", "ゴミ箱を買って", "ゴミ袋注文して", "ゴミ袋欲しい", "ゴミ箱お願い", "缶ビールいつ届く？", "電池いつ届く？", "ペットボトルの水は配送された？", "ペットの餌", "シャンプー買って", "明日15時に会議を入れて",
                     "明日8時にゴミ出しを入れて", "ゴミの日を予定に入れて", "ゴミ出しの予定を消して", "ゴミ出しを金曜にずらして"] {
            XCTAssertNil(Intent.garbageQuestion(text, now: now))
        }
        // Garbage questions must win over the calendar lookup that "予定" would trigger.
        XCTAssertNotNil(Intent.garbageQuestion("明日のゴミの予定", now: now))

        let sheet = GarbageCalendar.shimizu2026
        let todayAnswer = sheet.answer(.days(start: today, end: d(1), label: "今日", kind: nil), now: now)
        XCTAssertTrue(todayAnswer.contains("今日（9/21(月)）はプラスチック製容器包装の日です。午前8時までに"))
        let sunday = sheet.answer(.days(start: d(6), end: d(7), label: "日曜日", kind: nil), now: now)
        XCTAssertTrue(sunday.contains("ごみの収集はありません"))
        XCTAssertTrue(sunday.contains("次の収集は9/28(月)のプラスチック製容器包装です。"))
        let suspended = sheet.answer(.days(start: date("2026-10-07 00:00"), end: date("2026-10-08 00:00"), label: "", kind: nil), now: now)
        XCTAssertTrue(suspended.hasPrefix("10/7(水)はごみ収集はありません（休止）。"))
        let notThatDay = sheet.answer(.days(start: d(1), end: d(2), label: "明日", kind: .petBottle), now: now)
        XCTAssertTrue(notThatDay.contains("明日（9/22(火)）は可燃ごみの日です。午前7時までに"))
        XCTAssertTrue(notThatDay.contains("次のペットボトルは10/21(水)、30日後です。その次は11/4(水)。"))
        let next = sheet.answer(.next(.mercury, item: "蛍光灯"), now: now)
        XCTAssertTrue(next.hasPrefix("蛍光灯は水銀ごみです。\n"))
        XCTAssertTrue(next.contains("次の水銀ごみは12/9(水)、79日後です。その次は2027/3/10(水)。"))
        XCTAssertTrue(next.contains("6・9・12・3月の第2水曜、午前8時までに。"))
        let week = sheet.answer(.days(start: today, end: d(7), label: "今週", kind: nil), now: now)
        XCTAssertTrue(week.contains("9/21(月)  プラスチック製容器包装（午前8時まで）"))
        XCTAssertTrue(week.contains("9/23(水)  埋立ごみ（午前8時まで）"))
        XCTAssertTrue(week.contains("9/25(金)  可燃ごみ（午前7時まで）"))
        XCTAssertTrue(sheet.answer(.days(start: date("2027-04-05 00:00"), end: date("2027-04-06 00:00"), label: "", kind: nil), now: now).contains("2026年4月〜2027年3月分だけ"))
        // After 8:00 on a プラ day the deadline has passed; before it, nothing is added.
        let late = sheet.answer(.days(start: today, end: d(1), label: "今日", kind: nil), now: date("2026-09-21 09:30"))
        XCTAssertTrue(late.contains("今日の午前8時はもう過ぎています。次のプラスチック製容器包装は9/28(月)、7日後です。"))
        let early = sheet.answer(.days(start: today, end: d(1), label: "今日", kind: nil), now: date("2026-09-21 06:30"))
        XCTAssertFalse(early.contains("過ぎています"))
        // Year end: the three suspended days are listed, and the range spills into 2027 with the year spoken.
        let yearEnd = sheet.answer(.days(start: date("2026-12-28 00:00"), end: date("2027-01-09 00:00"), label: "年末年始", kind: nil), now: now)
        XCTAssertTrue(yearEnd.contains("12/31(木)  紙類（午前8時まで）"))
        XCTAssertTrue(yearEnd.contains("2027/1/1(金)  収集なし（休止）"))
        XCTAssertTrue(yearEnd.contains("2027/1/3(日)  収集なし（休止）"))
        XCTAssertTrue(yearEnd.contains("2027/1/4(月)  プラスチック製容器包装（午前8時まで）"))
        // A range past March 2027 is cut at the calendar's end and says so.
        let march = sheet.answer(.days(start: date("2027-03-29 00:00"), end: date("2027-04-05 00:00"), label: "今週", kind: nil), now: date("2027-03-29 10:00"))
        XCTAssertTrue(march.contains("3/30(火)  可燃ごみ（午前7時まで）"))
        XCTAssertTrue(march.contains("2027年4月以降はカレンダーがありません。"))
        XCTAssertFalse(march.contains("4/2"))
        XCTAssertTrue(sheet.answer(.bulky, now: date("2027-04-10 10:00")).contains("2026年4月〜2027年3月分だけ"))
        let bulky = sheet.answer(.bulky, now: now)
        XCTAssertTrue(bulky.contains("事前申込み"))
        XCTAssertTrue(bulky.contains("申込期間（区分C）：4/1〜4/14、6/3〜6/16、7/29〜8/11、9/30〜10/13、11/25〜12/8、2/3〜2/16"))
        XCTAssertTrue(bulky.contains("申込期間（区分D）：4/15〜4/28、6/17〜6/30、8/19〜9/1、10/14〜10/27、12/9〜12/22、2/17〜3/2"))
        let battery = sheet.answer(.next(.landfill, item: "電池"), now: now)
        XCTAssertTrue(battery.hasPrefix("電池は埋立ごみです。\nボタン型電池は水銀ごみ、充電式電池は市の施設のリサイクルBOXへ。\n次の埋立ごみは9/23(水)、明後日です。"))
        XCTAssertFalse(sheet.answer(.next(.mercury, item: "ボタン電池"), now: now).contains("リサイクルBOX"))
        let nonBurnable = sheet.answer(.nonBurnable, now: now)
        XCTAssertTrue(nonBurnable.contains("「不燃ごみ」の区分はありません"))
        XCTAssertTrue(nonBurnable.contains("次の金物・ガラス類は10/1(木)、10日後です。"))
        XCTAssertTrue(nonBurnable.contains("次の埋立ごみは9/23(水)、明後日です。"))
        XCTAssertTrue(nonBurnable.contains("次の水銀ごみは12/9(水)、79日後です。"))
    }
}
