import Foundation
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs == rhs) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTAssertNotNil<T>(_ value: T?) { precondition(value != nil) }
func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }
@main struct ChappieTests {
    static func main() {
        let tests = ChappieTests()
        tests.testWakeAndSameUtterance()
        tests.testPurchaseLimitsAndDuplicates()
        tests.testLookalikeAndInvalidRules()
        tests.testProductNameMatching()
        print("PASS: wake phrase, utterance extraction, purchase matching, limits, duplicate protection, URL validation")
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
}
