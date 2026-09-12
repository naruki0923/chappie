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

@MainActor
final class Voice: ObservableObject {
    @Published var enabled = false
    @Published var status = "音声をオンにすると呼びかけを待ちます"
    @Published var transcript = ""
    @Published var receiving = false
    var onCommand: ((String) -> Void)?
    var onWake: (() -> Void)?
    var suppressed = false
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var renewal: Task<Void, Never>?
    private var silence: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var generation = 0
    private var installed = false
    private var requesting = false
    private var wakeSeen = false
    private var lastText = ""

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
    }
    func stop() {
        enabled = false
        UserDefaults.standard.set(false, forKey: "voiceEnabled")
        generation += 1
        renewal?.cancel(); silence?.cancel(); timeout?.cancel()
        task?.cancel(); task = nil
        engine.stop()
        if installed { engine.inputNode.removeTap(onBus: 0); installed = false }
        request?.endAudio(); request = nil
        receiving = false; transcript = ""; status = "音声オフ"
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
        guard format.sampleRate > 0, format.channelCount > 0 else { stop(); status = "マイクが見つかりません"; return }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in req.append(buffer) }
        installed = true
        do { engine.prepare(); try engine.start() } catch { stop(); status = "マイクを開始できません: \(error.localizedDescription)"; return }
        if !receiving { status = "「チャッピー」で呼んでね" }
        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.enabled, self.generation == current else { return }
                if let result { self.consume(result.bestTranscription.formattedString) }
                if error != nil || result?.isFinal == true {
                    self.renewal?.cancel()
                    self.renewal = Task {
                        try? await Task.sleep(nanoseconds: 100_000_000)
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
