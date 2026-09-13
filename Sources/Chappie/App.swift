import AppKit
import SwiftUI

@main
struct ChappieApp: App {
    @NSApplicationDelegateAdaptor(CompanionDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CompanionDelegate: NSObject, NSApplicationDelegate {
    let assistant = Assistant()
    private var panel: NSPanel!
    private var item: NSStatusItem!
    private var dragStartOrigin: CGPoint?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let index = CommandLine.arguments.firstIndex(of: "--import-purchases"), CommandLine.arguments.count > index + 1 {
            let result = assistant.connections.importPurchaseCSV(at: CommandLine.arguments[index + 1])
            print("IMPORTED:\(result.imported)")
            result.errors.forEach { print("ERROR:\($0)") }
            NSApp.terminate(nil)
            return
        }
        // `Chappie --ask "今日の予定"` answers one request on stdout and quits; used to check routing without the UI.
        // `Chappie --dump-orders` prints the raw text of each Amazon order card, for checking the parser after Amazon changes its page.
        if CommandLine.arguments.contains("--dump-orders") {
            AmazonOrder.debugDump = { print("----- CARD -----\n\($0)") }
            AmazonSessionWindowController.shared.fetchOrders { result in
                if case .failure(let error) = result { print("ERROR: \(error.localizedDescription)") }
                NSApp.terminate(nil)
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--ask"), CommandLine.arguments.count > index + 1 {
            let initial = assistant.answer
            assistant.readAloud = false
            assistant.submit(CommandLine.arguments[index + 1])
            var ticks = 0
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [assistant] timer in
                MainActor.assumeIsolated {
                    ticks += 1
                    guard (assistant.answer != initial && !assistant.busy) || ticks > 400 else { return }
                    timer.invalidate()
                    print("ANSWER:\n\(assistant.answer)")
                    assistant.files.forEach { print("FILE:\($0.url.path)") }
                    NSApp.terminate(nil)
                }
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-icon"), CommandLine.arguments.count > index + 1 {
            let renderer = ImageRenderer(content: ChappieIcon())
            renderer.scale = 1
            if let cg = renderer.cgImage {
                let bitmap = NSBitmapImageRep(cgImage: cg)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            }
            NSApp.terminate(nil)
            return
        }
        panel = CompanionPanel(contentRect: CGRect(x: 0, y: 0, width: 180, height: 184), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: CompanionView(
            model: assistant,
            resize: { [weak self] expanded in self?.resize(expanded) },
            move: { [weak self] translation, ended in self?.movePanel(translation: translation, ended: ended) }
        ))
        if let frame = NSScreen.main?.visibleFrame { panel.setFrameOrigin(NSPoint(x: frame.maxX - 205, y: frame.minY + 25)) }
        panel.orderFrontRegardless()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "チャッピー")
        let menu = NSMenu()
        menu.addItem(withTitle: "チャッピーを表示", action: #selector(show), keyEquivalent: "") .target = self
        menu.addItem(withTitle: "終了", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        if CommandLine.arguments.contains("--enable-login") { assistant.setLogin(true) }
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            let destination = CommandLine.arguments[index + 1]
            assistant.expanded = true
            resize(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                guard let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { NSApp.terminate(nil); return }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: destination))
                NSApp.terminate(nil)
            }
            return
        }
        if CommandLine.arguments.contains("--enable-voice") || UserDefaults.standard.bool(forKey: "voiceEnabled") { Task { await assistant.voice.start() } }
        assistant.startReminderClock()
    }
    private func resize(_ expanded: Bool) {
        let old = panel.frame
        let size = CGSize(width: expanded ? 390 : 180, height: expanded ? 560 : 184)
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? old
        let x = min(max(old.maxX - size.width, visible.minX), visible.maxX - size.width)
        let y = min(max(old.minY, visible.minY), visible.maxY - size.height)
        panel.setFrame(CGRect(origin: CGPoint(x: x, y: y), size: size), display: true)
        if expanded { panel.makeKeyAndOrderFront(nil) }
    }
    private func movePanel(translation: CGSize, ended: Bool) {
        if dragStartOrigin == nil { dragStartOrigin = panel.frame.origin }
        guard let start = dragStartOrigin else { return }
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        let proposed = CGPoint(x: start.x + translation.width,
                               y: start.y - translation.height)
        let x = min(max(proposed.x, visible.minX), visible.maxX - panel.frame.width)
        let y = min(max(proposed.y, visible.minY), visible.maxY - panel.frame.height)
        panel.setFrameOrigin(CGPoint(x: x, y: y))
        if ended { dragStartOrigin = nil }
    }
    @objc private func show() { panel.orderFrontRegardless(); assistant.expanded = true }
    @objc private func quit() { assistant.cancel(); assistant.voice.stop(); NSApp.terminate(nil) }
}

struct CompanionView: View {
    @ObservedObject var model: Assistant
    @ObservedObject var voice: Voice
    let resize: (Bool) -> Void
    let move: (CGSize, Bool) -> Void
    @State private var settings = false
    @State private var connections = false
    init(model: Assistant,
         resize: @escaping (Bool) -> Void,
         move: @escaping (CGSize, Bool) -> Void) {
        self.model = model
        self.voice = model.voice
        self.resize = resize
        self.move = move
    }
    private let ink = Color(red: 0.19, green: 0.20, blue: 0.26)
    var body: some View {
        VStack(spacing: 8) {
            if model.expanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Circle().fill(voice.enabled ? Color.green : Color.gray).frame(width: 7, height: 7)
                        Text("チャッピー").font(.system(size: 15, weight: .bold, design: .rounded))
                        Spacer()
                        Button { settings.toggle() } label: { Image(systemName: "slider.horizontal.3") }.help("設定")
                        Button { model.expanded = false } label: { Image(systemName: "minus") }.help("小さくする")
                    }
                    if settings {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("音声で返事する", isOn: $model.readAloud)
                            Toggle("ログイン時に起動", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                            Text("呼びかけの認識はこのMac内で処理します。一般の質問と旅行などの提案は、ログイン済みのClaude Code CLI（無い場合はCodex CLI）に送信します。ファイル名検索と予定の確認・追加は端末内で処理します。")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Button("商品・noteを登録") { connections = true }
                            Text("Amazon購入：専用ブラウザで都度価格確認 / 売上サービス：未接続").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.padding(10).background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(model.answer).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(model.files) { file in
                                Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: {
                                    Label(file.url.lastPathComponent, systemImage: "doc").font(.system(size: 12)).lineLimit(2)
                                }.help(file.url.path)
                            }
                        }
                    }.frame(maxHeight: .infinity)
                    if !voice.transcript.isEmpty { Text(voice.transcript).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2) }
                    HStack(spacing: 6) {
                        chip("予定", icon: "calendar") { model.submit("今日の予定") }
                        chip("ファイル", icon: "folder") { model.input = "ファイル " }
                        chip("価格", icon: "magnifyingglass") { model.input = "価格を調べて " }
                        chip("購入", icon: "bag") { model.submit("何が買える？") }
                    }
                    HStack(alignment: .center, spacing: 8) {
                        TextField("何を手伝おう？", text: $model.input).textFieldStyle(.plain).onSubmit { model.submit() }
                        if model.busy {
                            Button { model.cancel() } label: { Image(systemName: "stop.circle.fill") }.help("停止")
                        } else {
                            Button { model.submit() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 23)) }.help("送信")
                        }
                    }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16))
                    HStack {
                        Button { voice.toggle() } label: { Label(voice.enabled ? "音声オン" : "音声をオン", systemImage: voice.enabled ? "mic.fill" : "mic.slash") }
                        Spacer()
                        if model.busy { ProgressView().controlSize(.small) }
                        Text(voice.receiving ? "聞いています" : "CHAPPIE").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                    }.font(.system(size: 11))
                    Text(voice.status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3)
                }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.97, green: 0.96, blue: 0.93), in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.9), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            }
            HStack {
                if model.expanded { Spacer() }
                VStack(spacing: 0) {
                    Robot(active: voice.receiving || model.busy)
                        .frame(width: 122, height: 112)
                        .contentShape(Rectangle())
                        .onTapGesture { model.expanded.toggle() }
                        .gesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { move($0.translation, false) }
                                .onEnded { move($0.translation, true) }
                        )
                    if !model.expanded {
                        Text(voice.receiving ? "聞いているよ" : "チャッピー").font(.system(size: 11, weight: .medium, design: .rounded))
                            .padding(.horizontal, 12).padding(.vertical, 5).background(.regularMaterial, in: Capsule())
                    }
                }
            }.frame(height: model.expanded ? 104 : 160)
        }.padding(10).foregroundStyle(ink).buttonStyle(.plain)
            .sheet(isPresented: $connections) { ConnectionView(store: model.connections) }
            .onChange(of: model.expanded) { _, value in resize(value) }
    }
    private func chip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(.system(size: 10)).padding(.horizontal, 8).padding(.vertical, 7).background(.white.opacity(0.9), in: Capsule()) }.disabled(model.busy)
    }
}

// Pixel-grid artwork: the same little blue robot appears on the desktop and icon.
struct RobotArtwork: View {
    var active = false
    var body: some View {
        Canvas { c, size in
            let unit = min(size.width / 40, size.height / 44)
            c.translateBy(x: (size.width - 40 * unit) / 2, y: (size.height - 44 * unit) / 2)
            c.scaleBy(x: unit, y: unit)
            let outline = Color(red: 0.07, green: 0.12, blue: 0.22)
            let blue = Color(red: 0.30, green: 0.47, blue: 0.94)
            let light = Color(red: 0.40, green: 0.59, blue: 1.0)
            let shadow = Color(red: 0.23, green: 0.32, blue: 0.78)
            let glint = Color(red: 0.56, green: 0.72, blue: 1.0)
            let screen = Color(red: 0.07, green: 0.13, blue: 0.30)
            let cyan = Color(red: 0.50, green: 0.95, blue: 1.0)
            func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Color) {
                c.fill(Path(CGRect(x: x,y: y,width: w,height: h)),with: .color(color),style: FillStyle(antialiased: false))
            }
            func poly(_ points: [(Double,Double)], _ color: Color) {
                var p = Path()
                for (i, point) in points.enumerated() {
                    if i == 0 { p.move(to: CGPoint(x: point.0,y: point.1)) }
                    else { p.addLine(to: CGPoint(x: point.0,y: point.1)) }
                }
                p.closeSubpath()
                let box = p.boundingRect
                for y in Int(floor(box.minY))..<Int(ceil(box.maxY)) {
                    for x in Int(floor(box.minX))..<Int(ceil(box.maxX)) {
                        if p.contains(CGPoint(x: Double(x) + 0.5,y: Double(y) + 0.5)) {
                            rect(Double(x),Double(y),1,1,color)
                        }
                    }
                }
            }
            // Discrete stair-step silhouettes keep the low-resolution character intentional.
            rect(12,41,16,1,outline.opacity(0.10))
            poly([(12,28),(10,29),(8,32),(7,35),(7,38),(8,39),(11,39),(12,36),(14,34),(14,29)],outline)
            poly([(28,28),(30,29),(32,32),(33,35),(33,38),(32,39),(29,39),(28,36),(26,34),(26,29)],outline)
            poly([(11,30),(9,33),(8,36),(8,38),(10,38),(11,35),(13,33),(13,30)],blue)
            poly([(29,30),(31,33),(32,36),(32,38),(30,38),(29,35),(27,33),(27,30)],blue)
            rect(9,33,1,4,light); rect(31,35,1,3,shadow)
            poly([(13,34),(19,34),(19,39),(18,39),(18,42),(13,42),(12,41),(12,37)],outline)
            poly([(21,34),(27,34),(28,37),(28,41),(27,42),(22,42),(22,39),(21,39)],outline)
            rect(13,36,5,4,blue); rect(14,40,3,1,shadow)
            rect(22,36,5,4,blue); rect(23,40,4,1,shadow)
            poly([(14,27),(26,27),(28,30),(28,36),(26,38),(14,38),(12,36),(12,30)],outline)
            poly([(15,28),(25,28),(27,30),(27,35),(25,37),(15,37),(13,35),(13,30)],shadow)
            rect(14,29,12,6,blue); rect(15,29,10,1,glint)
            rect(14,35,12,1,light)
            rect(18,31,1,1,.white); rect(19,32,1,1,.white); rect(18,33,1,1,.white)
            rect(22,32,3,1,.white)
            // Cloud-like rounded head, with a dark one-pixel outline.
            poly([(5,13),(6,10),(9,8),(12,7),(13,4),(16,2),(21,2),(23,3),(25,3),(26,2),(29,3),(32,6),(33,8),(35,10),(36,13),(37,14),(37,21),(36,22),(36,25),(34,28),(31,30),(10,30),(7,28),(5,25),(5,22),(3,21),(3,16)],outline)
            poly([(6,13),(7,10),(10,9),(13,8),(14,5),(17,3),(21,3),(23,4),(26,4),(27,3),(29,4),(31,6),(32,9),(34,11),(35,14),(36,15),(36,21),(35,22),(35,25),(33,27),(30,29),(11,29),(8,27),(6,25),(6,21),(4,20),(4,16)],blue)
            poly([(6,14),(7,11),(10,10),(14,9),(15,6),(18,4),(21,4),(23,5),(27,4),(29,5),(31,7),(32,10),(34,12),(34,14),(31,13),(11,13),(9,16),(5,18)],light)
            rect(17,3,4,1,glint); rect(14,6,1,2,glint); rect(8,11,2,1,glint)
            poly([(4,19),(8,19),(9,22),(10,25),(14,27),(30,27),(34,24),(35,21),(36,21),(35,25),(33,27),(30,29),(11,29),(8,27),(6,25),(6,21),(4,20)],shadow)
            rect(10,27,3,1,light); rect(14,28,15,1,blue)
            // Screen bezel and luminous terminal expression.
            poly([(13,12),(29,12),(32,13),(33,15),(33,25),(31,27),(13,27),(11,26),(10,24),(10,15),(11,13)],outline)
            poly([(13,13),(29,13),(31,14),(32,16),(32,24),(30,26),(13,26),(11,24),(11,15)],screen)
            rect(13,13,16,1,Color(red: 0.16,green: 0.23,blue: 0.43))
            rect(13,26,17,1,glint.opacity(0.6))
            rect(14,16,1,2,cyan); rect(15,17,1,2,cyan); rect(16,18,1,2,cyan)
            rect(15,20,1,1,cyan); rect(14,21,1,1,cyan)
            if active {
                rect(23,19,1,3,cyan); rect(25,17,1,5,cyan); rect(27,18,1,4,cyan)
            } else {
                rect(23,21,4,1,cyan); rect(23,20,1,1,cyan); rect(27,20,1,2,cyan)
            }
        }
    }
}

struct Robot: View {
    var active: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !active)) { context in
            RobotArtwork(active: active).offset(y: active ? sin(context.date.timeIntervalSinceReferenceDate * 4) * 2 : 0)
        }.accessibilityLabel("チャッピーを開く")
    }
}

struct ChappieIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 220).fill(LinearGradient(colors: [Color(red: 0.93,green: 0.96,blue: 1),Color(red: 0.78,green: 0.85,blue: 0.97)],startPoint: .topLeading,endPoint: .bottomTrailing))
            RobotArtwork().frame(width: 800,height: 880)
        }.frame(width: 1024,height: 1024).clipShape(RoundedRectangle(cornerRadius: 220))
    }
}
