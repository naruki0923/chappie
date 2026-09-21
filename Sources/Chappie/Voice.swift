import AVFoundation
import Speech

struct WakePhrase {
    private static let phrases = [
        "チャッピー", "チャッピ", "チャピー", "チャピ",
        "ちゃっぴー", "ちゃっぴ", "ちゃぴー", "ちゃぴ",
        "chappie", "chappy"
    ]

    static func command(in text: String) -> String? {
        for phrase in phrases {
            if let range = text.range(of: phrase, options: .caseInsensitive) {
                return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            }
        }
        return nil
    }
}

/// Timestamp of the last microphone buffer, written from the audio thread and read by the watchdog.
final class Heartbeat: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Date()
    var last: Date {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

@MainActor
final class Voice: ObservableObject {
    @Published var enabled = false
    @Published var status = "音声をオンにすると呼びかけを待ちます"
    @Published var transcript = ""
    @Published var receiving = false
    /// Voice is on but the microphone is not delivering audio right now (device switching, wake from sleep); a retry is pending.
    @Published private(set) var degraded = false
    var onCommand: ((String) -> Void)?
    var onWake: (() -> Void)?
    var suppressed = false
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let heartbeat = Heartbeat()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var renewal: Task<Void, Never>?
    private var silence: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var configurationObserver: NSObjectProtocol?
    private var generation = 0
    private var installed = false
    private var requesting = false
    private var wakeSeen = false
    private var lastText = ""

    init() {
        // macOS stops the engine when the input device changes (AirPods, a display with a mic, sleep/wake).
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.audioConfigurationChanged() }
        }
    }

    func toggle() { if enabled { stop() } else { Task { await start() } } }
    func start() async {
        guard !enabled, !requesting else { return }
        requesting = true
        defer { requesting = false }
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            status = "日本語の端末内音声認識が利用できません。文字入力をご利用ください。"; return
        }
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard authorization == .authorized else { status = "システム設定でチャッピーの音声認識を許可してください"; return }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { status = "システム設定でチャッピーのマイクを許可してください"; return }
        enabled = true
        UserDefaults.standard.set(true, forKey: "voiceEnabled")
        restart()
        armWatchdog()
    }
    /// The user turned voice off: remembered across launches.
    func stop() {
        UserDefaults.standard.set(false, forKey: "voiceEnabled")
        shutDown()
    }
    /// The app is quitting: release the microphone but keep the saved preference so the next launch listens again.
    func suspend() { shutDown() }
    /// The Mac woke from sleep: audio devices need a moment before the engine can start again.
    func recover() {
        guard enabled else { return }
        tearDownAudio()
        status = "マイクを再開しています…"
        scheduleRestart(after: 1.5)
    }
    private func shutDown() {
        enabled = false
        timeout?.cancel(); watchdog?.cancel(); retry?.cancel(); retry = nil
        tearDownAudio()
        receiving = false; transcript = ""; degraded = false; status = "音声オフ"
    }
    private func tearDownAudio() {
        degraded = true
        generation += 1
        renewal?.cancel(); silence?.cancel()
        task?.cancel(); task = nil
        engine.stop()
        if installed { engine.inputNode.removeTap(onBus: 0); installed = false }
        request?.endAudio(); request = nil
    }
    /// A microphone problem is usually temporary (device switching, wake from sleep), so keep voice on and try again.
    private func fail(_ message: String) {
        tearDownAudio()
        status = "\(message)。数秒後にもう一度試します"
        scheduleRestart(after: 3)
    }
    private func scheduleRestart(after seconds: Double) {
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.enabled else { return }
            self.retry = nil
            self.restart()
        }
    }
    private func audioConfigurationChanged() {
        guard enabled else { return }
        status = "マイクを切り替えています…"
        scheduleRestart(after: 0.5)
    }
    /// Every few seconds, confirm audio is still flowing; the engine can stop, or a device can die, without any error reaching us.
    private func armWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self, self.enabled else { return }
                guard self.retry == nil else { continue }
                if !self.engine.isRunning || Date().timeIntervalSince(self.heartbeat.last) > 5 {
                    self.status = "マイクを再開しています…"
                    self.restart()
                }
            }
        }
    }
    func listenForCommand() {
        guard enabled else { Task { await start() }; return }
        receiving = true; wakeSeen = false; transcript = ""; lastText = ""
        status = "聞いています…"
        restart()
        armTimeout()
    }
    func listenForWakePhrase() {
        guard enabled else { return }
        renewal?.cancel(); silence?.cancel(); timeout?.cancel()
        receiving = false; wakeSeen = false; transcript = ""; lastText = ""
        status = "「チャッピー」で呼んでね"
        restart()
    }
    private func armTimeout() {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.receiving = false; self.transcript = ""; self.status = "「チャッピー」で呼んでね"; self.restart()
        }
    }
    private func restart() {
        guard enabled else { return }
        retry?.cancel(); retry = nil
        generation += 1
        let current = generation
        renewal?.cancel(); task?.cancel(); engine.stop()
        if installed { engine.inputNode.removeTap(onBus: 0); installed = false }
        request?.endAudio()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        request = req
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { fail("マイクが見つかりません"); return }
        let beat = heartbeat
        beat.last = Date()
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in req.append(buffer); beat.last = Date() }
        installed = true
        do { engine.prepare(); try engine.start() } catch { fail("マイクを開始できません: \(error.localizedDescription)"); return }
        degraded = false
        status = receiving ? "聞いています…" : "「チャッピー」で呼んでね"
        let startedAt = Date()
        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.enabled, self.generation == current else { return }
                if let result { self.consume(result.bestTranscription.formattedString) }
                if error != nil || result?.isFinal == true {
                    let delay = Self.renewalDelay(afterError: error != nil, elapsed: Date().timeIntervalSince(startedAt))
                    self.renewal?.cancel()
                    self.renewal = Task {
                        try? await Task.sleep(nanoseconds: delay)
                        guard !Task.isCancelled, self.generation == current else { return }
                        // A new recognition task has no wake phrase prefix.
                        self.wakeSeen = false
                        self.restart()
                    }
                }
            }
        }
        renewal = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled, let self, !self.receiving else { return }
            self.restart()
        }
    }
    /// An error within a second of starting means recognition itself is unavailable; back off instead of spinning.
    nonisolated static func renewalDelay(afterError: Bool, elapsed: TimeInterval) -> UInt64 {
        afterError && elapsed < 1 ? 2_000_000_000 : 100_000_000
    }
    private func consume(_ text: String) {
        guard !suppressed else { return }
        if !receiving {
            guard let wakeCommand = WakePhrase.command(in: text) else { return }
            receiving = true; wakeSeen = true; onWake?(); status = "聞いています…"; armTimeout()
            // A wake-only utterance often becomes final before the user starts the
            // actual request. Start a fresh recognition task immediately so the
            // beginning of that next sentence is not lost during task renewal.
            if wakeCommand.isEmpty {
                lastText = ""
                renewal?.cancel()
                renewal = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard !Task.isCancelled, let self, self.receiving else { return }
                    self.wakeSeen = false
                    self.restart()
                }
                return
            }
        }
        let command = wakeSeen ? (WakePhrase.command(in: text) ?? "") : text
        guard command != lastText else { return }
        lastText = command; transcript = command
        silence?.cancel()
        guard !command.isEmpty else { return }
        silence = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled, let self, !self.suppressed else { return }
            self.timeout?.cancel(); self.receiving = false; self.wakeSeen = false; self.lastText = ""
            self.onCommand?(command)
            self.restart()
        }
    }
}
