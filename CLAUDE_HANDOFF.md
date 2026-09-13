# チャッピー開発 引き継ぎ

## 目的

macOSで常時起動する、小型ロボット型の日本語音声アシスタントです。通常は小さなロボットだけを表示し、クリックすると会話画面を開きます。ドラッグで移動できます。「チャッピー」「チャピー」「チャピ」で起動し、続けて話した命令を処理します。

## 場所と実行

- ソース: `outputs/chappie`
- インストール先: `/Applications/Chappie.app`
- Bundle ID: `local.chappie.companion`
- テスト: `cd outputs/chappie && ./test.command`
- ビルド: `cd outputs/chappie && ./build.command`
- インストール: `ditto outputs/chappie/dist/Chappie.app /Applications/Chappie.app`
- 音声を有効にして起動: `defaults write local.chappie.companion voiceEnabled -bool true && open -a /Applications/Chappie.app --args --enable-voice`

アプリを入れ替える前に、実行中のChappieを終了させます。終了操作で音声設定がオフになる場合があるため、再起動前に上記defaultsを設定してください。

## 実装済み

- 小型ロボットUI、クリック展開、縮小、ドラッグ移動、常時手前表示
- 音声ウェイクと同じ発話内の命令抽出
- 応答直後から再度ウェイクできる音声状態管理
- Appleカレンダーの予定読み取り
- SpotlightによるMac内ファイル名検索
- 一般質問とWeb調査（現在はローカルのCodex CLIを子プロセスとして使用）
- CSVから購入商品を登録
- Amazon専用WKWebViewと永続ログインCookie
- 登録商品への曖昧一致。ひらがな・カタカナ、長音、空白、軽い言い間違いを吸収
- 「買って」「注文して」「頼んで」「欲しい」「お願い」などの購入意図判定
- Amazonの商品名、ASIN、通常価格、送料、数量、在庫の確認
- 金額を提示し、「いいよ」後だけ注文を確定。「やめて」で中止
- レジで送料込み合計を再確認し、承認額を超えたら停止
- 定期おトク便を選ばず、通常購入で注文
- 同一商品の連続購入防止
- 命令の振り分けを`Sources/Chappie/Intent.swift`に集約（2026-09-12）
  - 購入語は「買って・注文して・購入したい」などの明示語と、「欲しい・お願い」の弱い語に分け、弱い語は登録商品名を含むときだけ購入扱い
  - 「いいよ。」「はい、いいよ」「うん」「オッケー」を承認、「やめて・いいえ・待って・いらない」を中止として判定。否定語を含む返答は必ず中止側
  - 「旅行の予定を考えて」など計画語を含む文はカレンダーではなく調査へ。「今日/明日/明後日/今週/来週/今月の予定」「空いてる？」は読み取り
  - 予定の追加：「明日15時に会議を入れて」をNSDataDetectorでMac内解釈しEventKitへ保存（既定カレンダー、時刻なしは終日）
  - 予定一覧に旅行・出張があればプラン提案を案内
  - 文字入力の先頭の「チャッピー、」は取り除いてから判定
  - 「何が買える？」と、登録に無い商品の購入依頼には登録商品一覧を返す
  - 一般質問のプロンプトを秘書仕様に（旅行・外出は案2〜3件＋次の判断を1つ質問、読み上げ向けに短く）
- `Chappie --ask "文"` で1問だけ答えて終了するデバッグモード
- 注文状況（`Intent.isOrderStatusQuestion` → `Assistant.orderStatus`）：チャッピーが確定した注文は `Connections.purchaseLog`（UserDefaults `purchaseLog`、最大100件）に商品・金額・注文番号・お届け予定を保存。加えて `AmazonSessionWindowController.fetchOrders` が注文履歴ページ（timeFilter=last30）のカードを読み、`AmazonOrder.parse` で注文日・合計・注文番号・配送状況行（「10月6日にお届け」「お届け済み」「キャンセル済み」）を取り出す。`Chappie --dump-orders` でカードの生テキストを確認できる。「注文状況・注文履歴」は売上判定から外した
- 予約の段取り（`Intent.isBookingRequest` → `Assistant.booking`）：子Claude（MCPなし・ツールなし）に直近の会話込みで条件JSONを出させ、`BookingPlan.searchURL`（Yahoo!乗換案内／Googleフライト／Booking.com／食べログ、条件はURLパラメータ）を `BookingWindowController`（Amazonとは別窓「チャッピー — 予約」）に開く。必須項目が欠ければ開かずに聞き返す。DOM操作はしない
- Gmail（`Intent.mailRequest` → `Assistant.research(text, mail:)`）：メールの依頼だけ `--strict-mcp-config` を外し、`--allowedTools` にGmailの search/get（要約）＋ create_draft/list/get/update_draft（下書き）だけを渡す。send/reply/forward/trash/label系は `--disallowedTools` で明示禁止。宛先が見つからなければ下書きを作らず聞き返す
- 予定の変更・削除・空き時間（`Intent.calendarEdit`）：「を」の左を対象（日付語で検索範囲、残りを題名ヒント、「10時の」で開始時刻を絞る）、右を新しい日時（絶対／時刻のみ／日付のみ／「30分後ろ」の相対）。`Assistant.resolve`が1件に絞れたときだけ変更・削除し、複数なら候補を返す。空き時間は9〜18時で既定60分
- リマインド（`Intent.reminderDraft`）：相対時間「30分後」「あと10分」はMac内で計算、絶対時刻はNSDataDetector。時刻なしは9:00。`Assistant.addReminder`がUserDefaults（`chappieReminders`）に保存し、20秒ごとの`startReminderClock`で期限到来を読み上げ。同時にEKReminder（アラーム付き）を既定リストへ保存してiPhone/Watchに届ける。1時間以上前に過ぎたものは読み上げない
- 一般質問の子プロセスは `--strict-mcp-config --mcp-config {空}` でユーザーのclaude.aiコネクター（Google Calendar・Gmail等）を隠す。予定・リマインドはApple製アプリのみ、と本文プロンプトにも明記
- 会話で商品を登録・変更・削除（`Intent.registrationRequest / ruleChange / isRemovalRequest`）。URLを含む文だけが登録扱いなので音声からは発生しない。既存の同名商品は更新し、酒類の手動レジ設定は引き継ぐ。設定画面にも削除ボタン

## 2026-09-12の実地確認

登録名「シャンプー」、ASIN `B0FS22VBRJ`、数量1で次を確認済みです。

1. 「シャンプー注文して」で商品を特定
2. 商品¥1,210、送料無料、合計¥1,210と提示
3. 「いいよ」で専用Amazon画面からレジへ移動
4. 数量1、通常購入、請求額¥1,210を再確認
5. Amazonの注文完了画面まで到達

注文番号、住所、カード情報などの個人情報は、この引き継ぎ文書には保存していません。

## 主なファイル

- `Sources/Chappie/Intent.swift`: 命令の振り分け判定（購入語、承認/中止、予定の読み取り/追加、日時解釈、ファイル検索語）。Foundationのみで単体テスト対象
- `Sources/Chappie/Assistant.swift`: 振り分けの実行、会話、購入確認、予定の読み取り・追加、ファイル検索、調査
- `Sources/Chappie/AmazonSession.swift`: Amazon専用画面、価格取得、レジ、注文確定、完了確認
- `Sources/Chappie/PurchaseRules.swift`: 商品登録、曖昧一致、購入上限、連続購入防止
- `Sources/Chappie/Voice.swift`: ウェイクワードと音声認識状態
- `Sources/Chappie/App.swift`: メインUI・設定画面・ロボット描画・起動オプション
- `Sources/Chappie/ConnectionView.swift`: 商品・note登録画面
- `Tests/ChappieTests/ChappieTests.swift`: ウェイク、商品照合、購入条件のテスト

## 次に進める項目

1. 一般質問のバックエンドを選べるようにする
   - `Assistant.research`はログイン済みClaude Code CLIを優先し、見つからない場合だけCodex CLIへ戻ります。
   - Anthropic APIおよびOpenAI APIのキーは使用しません。ユーザーはAPI課金を望んでいません。
   - 将来設定画面でClaude/Codexを選べるようにする場合も、ログイン済みCLIだけを対象にしてください。
2. Amazon購入の表示改善
   - 注文完了画面から配送予定日と注文番号を安定して抽出する。
   - Amazon側のHTML変更時に、確定前で安全に停止し、理由を分かりやすく表示する。
3. 商品登録の確認（会話での登録・変更・削除は実装済み）
   - CSVの全行が取り込まれたか、重複・引用符・カンマを含むCSVにも対応する。
   - 現在の簡易CSVパーサーは、商品名内のカンマを扱えません。
4. TikTok Shop購入を接続（予約サイトのDOM操作による「フォーム自動入力」も未実装。現状はURLパラメータで検索結果まで）
5. 売上サービスを確定して今日の売上と注文状況を接続
6. ユーザー指定note URLを登録し、競艇予想の質問で参照する

## 購入処理で守る条件

- URLのホストとASINを照合する。
- 登録数量とレジ数量を照合する。
- 定期便チェックがオフであることを確認する。
- 追加商品、保証、会員登録、ギフトを追加しない。
- 送料・税込み最終合計がユーザーの承認額以下の場合だけ確定する。
- ログイン、OTP、CAPTCHA、新しい住所・支払い方法が必要なら停止する。
- 注文完了が確認できない場合は成功として記録しない。
- 実地テストで注文確定する場合は、その都度ユーザーの具体的な許可を得る。

## 既知の注意点

- 再ビルドするとアドホック署名が変わり、カレンダー許可が「未許可」に戻ることがあります。`tccutil reset Calendar local.chappie.companion` の後、実アプリで予定を聞くと許可ダイアログが出ます。

- AmazonページのDOMは変わる可能性があります。見つからないボタンを推測で押さず、確定前に停止してください。
- `AmazonSession.swift`はWKWebViewの画面遷移中にJavaScriptコールバックがキャンセルされる場合を考慮しています。
- 一般質問用の子CodexからChappie専用WKWebViewを操作する方式は使えませんでした。購入はChappie自身のWKWebView処理へ移行済みです。
- 音声認識にはmacOSのマイク・音声認識権限が必要です。
