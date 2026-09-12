import Foundation

enum ProductNameMatcher {
    static func matches(command: String, productName: String) -> Bool {
        normalize(command).contains(normalize(productName))
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            // Keep the existing CSV typo compatible with the usual pronunciation.
            .replacingOccurrences(of: "ディヒューザー", with: "ディフューザー")
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
    @Published var noteURL = "" { didSet { UserDefaults.standard.set(noteURL, forKey: "noteSource") } }
    init() {
        noteURL = UserDefaults.standard.string(forKey: "noteSource") ?? ""
        if let data = UserDefaults.standard.data(forKey: "purchaseRules"),
           var rules = try? JSONDecoder().decode([PurchaseRule].self, from: data) {
            var migrated = false
            for index in rules.indices where rules[index].name == "ディヒューザー" {
                rules[index].name = "ディフューザー"
                migrated = true
            }
            products = rules
            if migrated, let updated = try? JSONEncoder().encode(rules) {
                UserDefaults.standard.set(updated, forKey: "purchaseRules")
            }
        }
    }
    func save(_ rule: PurchaseRule) -> String? {
        if let error = rule.validationError { return error }
        if let index = products.firstIndex(where: { $0.name == rule.name }) { products[index] = rule } else { products.append(rule) }
        if let data = try? JSONEncoder().encode(products) { UserDefaults.standard.set(data, forKey: "purchaseRules") }
        return nil
    }

    func lastPurchased(_ rule: PurchaseRule) -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: "lastPurchase.\(rule.id.uuidString)")
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    func recordPurchase(_ rule: PurchaseRule) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastPurchase.\(rule.id.uuidString)")
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
