import Foundation

enum ProductNameMatcher {
    static func matches(command: String, productName: String) -> Bool {
        score(command: command, productName: productName) != nil
    }

    static func bestMatch(command: String, products: [PurchaseRule]) -> PurchaseRule? {
        products.compactMap { rule in
            score(command: command, productName: rule.name).map { (rule, $0) }
        }.min { $0.1 < $1.1 }?.0
    }

    private static func score(command: String, productName: String) -> Int? {
        let fullCommand = normalize(command)
        let name = normalize(productName)
        if fullCommand.contains(name) { return 0 }

        let spokenName = purchaseWords.reduce(fullCommand) { value, word in
            value.replacingOccurrences(of: word, with: "")
        }
        guard name.count >= 3, !spokenName.isEmpty else { return nil }
        let distance = editDistance(spokenName, name)
        let allowed = name.count >= 6 ? 2 : 1
        return distance <= allowed ? distance + 1 : nil
    }

    private static func normalize(_ value: String) -> String {
        (value.applyingTransform(.hiraganaToKatakana, reverse: false) ?? value).lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "ー", with: "")
            // Keep the existing CSV typo compatible with the usual pronunciation.
            .replacingOccurrences(of: "ディヒューザー", with: "ディフューザー")
    }

    private static let purchaseWords = [
        "購入してください", "購入して", "購入", "注文してください", "注文して", "注文",
        "買ってください", "買って", "買いたい", "頼んで", "お願い", "ください", "欲しい",
        "ホシイ", "一個", "1個", "ヒトツ", "一ツ", "ヲ"
    ].map { normalize($0) }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        var previous = Array(0...b.count)
        for (i, left) in a.enumerated() {
            var current = [i + 1]
            for (j, right) in b.enumerated() {
                current.append(min(current[j] + 1,
                                   previous[j + 1] + 1,
                                   previous[j] + (left == right ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }
}

/// A product link never grants authority by itself. The limits are explicit user settings.
struct PurchaseRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var url: URL
    var quantity: Int
    var maxTotalYen: Int
    var minimumIntervalHours: Int = 24
    var allowsSubscription = false
    var manualCheckoutOnly: Bool?

    var usesLivePriceConfirmation: Bool { maxTotalYen == 0 }
    var requiresManualCheckout: Bool { manualCheckoutOnly == true }

    var validationError: String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "商品名を入力してください" }
        let host = url.host?.lowercased() ?? ""
        guard url.scheme == "https", url.user == nil, url.password == nil,
              ["amazon.co.jp", "amzn.asia", "tiktok.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return "Amazon JapanまたはTikTokのHTTPS商品URLを入力してください" }
        guard quantity > 0, maxTotalYen >= 0, minimumIntervalHours > 0 else { return "数量と購入間隔は1以上、上限は0以上にしてください" }
        return nil
    }
    func canCheckout(actualTotalYen: Int, actualQuantity: Int, subscription: Bool, lastPurchased: Date?, now: Date = Date()) -> Bool {
        let withinLimit = usesLivePriceConfirmation || actualTotalYen <= maxTotalYen
        guard validationError == nil, actualTotalYen > 0, withinLimit, actualQuantity == quantity, !subscription || allowsSubscription else { return false }
        if let lastPurchased, now.timeIntervalSince(lastPurchased) < Double(minimumIntervalHours) * 3600 { return false }
        return true
    }
}

@MainActor
final class Connections: ObservableObject {
    @Published var products: [PurchaseRule] = []
    @Published var noteURL = "" { didSet { defaults.set(noteURL, forKey: "noteSource") } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        noteURL = defaults.string(forKey: "noteSource") ?? ""
        if let data = defaults.data(forKey: "purchaseRules"),
           var rules = try? JSONDecoder().decode([PurchaseRule].self, from: data) {
            var migrated = false
            for index in rules.indices where rules[index].name == "ディヒューザー" {
                rules[index].name = "ディフューザー"
                migrated = true
            }
            products = rules
            if migrated, let updated = try? JSONEncoder().encode(rules) {
                defaults.set(updated, forKey: "purchaseRules")
            }
        }
    }
    func save(_ rule: PurchaseRule) -> String? {
        if let error = rule.validationError { return error }
        if let index = products.firstIndex(where: { $0.name == rule.name }) {
            // Keep the original id so the last-purchase record survives a CSV re-import.
            var updated = rule
            updated.id = products[index].id
            products[index] = updated
        } else { products.append(rule) }
        if let data = try? JSONEncoder().encode(products) { defaults.set(data, forKey: "purchaseRules") }
        return nil
    }

    func remove(_ rule: PurchaseRule) {
        products.removeAll { $0.id == rule.id }
        if let data = try? JSONEncoder().encode(products) { defaults.set(data, forKey: "purchaseRules") }
    }

    func lastPurchased(_ rule: PurchaseRule) -> Date? {
        let timestamp = defaults.double(forKey: "lastPurchase.\(rule.id.uuidString)")
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    func recordPurchase(_ rule: PurchaseRule) {
        defaults.set(Date().timeIntervalSince1970, forKey: "lastPurchase.\(rule.id.uuidString)")
    }

    @discardableResult
    func importPurchaseCSV(at path: String) -> (imported: Int, errors: [String]) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return (0, ["CSVを読み込めませんでした"])
        }
        var imported = 0
        var errors: [String] = []
        for (offset, rawLine) in content.split(whereSeparator: { $0.isNewline }).enumerated() {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let comma = line.firstIndex(of: ",") else {
                errors.append("\(offset + 1)行目: 商品名とURLが必要です")
                continue
            }
            let name = String(line[..<comma]).trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
            var address = String(line[line.index(after: comma)...]).trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
            if !address.lowercased().hasPrefix("https://") { address = "https://" + address }
            guard let url = URL(string: address) else {
                errors.append("\(offset + 1)行目: URLを確認してください")
                continue
            }
            let isAlcohol = name.contains("ウイスキー") || name.contains("酒") || name.contains("ビール") || name.contains("ワイン")
            let rule = PurchaseRule(name: name,
                                    url: url,
                                    quantity: 1,
                                    maxTotalYen: 0,
                                    manualCheckoutOnly: isAlcohol ? true : nil)
            if let error = save(rule) { errors.append("\(offset + 1)行目: \(error)") }
            else { imported += 1 }
        }
        return (imported, errors)
    }
}
