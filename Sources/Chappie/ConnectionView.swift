import SwiftUI
struct ConnectionView: View {
    @ObservedObject var store: Connections
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var link = ""
    @State private var quantity = "1"
    @State private var limit = ""
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("商品と参照先").font(.headline); Spacer(); Button("閉じる") { dismiss() } }
            Text("予想の参照元").font(.subheadline.bold())
            TextField("https://note.com/…", text: $store.noteURL)
            Divider()
            Text("購入ルール").font(.subheadline.bold())
            TextField("呼び名（例：シャンプー）", text: $name)
            TextField("Amazon / TikTokの商品URL", text: $link)
            HStack { TextField("数量", text: $quantity); TextField("上限（0＝都度確認）", text: $limit) }
            Text("通常購入のみ。購入前に金額を読み上げて確認し、同じ商品の再購入は24時間以上あけます。会話でも「このURLをシャンプーとして登録して」で登録できます。")
                .font(.caption).foregroundStyle(.secondary)
            Button("Amazonを開く・ログイン") {
                AmazonSessionWindowController.shared.show(URL(string: "https://www.amazon.co.jp/")!)
            }
            Button("ルールを保存") {
                guard let url = URL(string: link), let count = Int(quantity), let yen = Int(limit) else { message = "URL・数量・上限金額を確認してください"; return }
                message = store.save(PurchaseRule(name: name, url: url, quantity: count, maxTotalYen: yen)) ?? "保存しました"
            }
            Text(message).font(.caption)
            ScrollView {
                ForEach(store.products) { rule in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) {
                            Text(rule.maxTotalYen == 0
                                 ? "\(rule.name) ×\(rule.quantity) / 購入時に価格確認"
                                 : "\(rule.name) ×\(rule.quantity) / 上限 ¥\(rule.maxTotalYen)")
                            Link("商品ページ", destination: rule.url)
                        }
                        Spacer()
                        Button("削除") { store.remove(rule) }.font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }
            }
        }.textFieldStyle(.roundedBorder).padding(22).frame(width: 350, height: 430)
    }
}
