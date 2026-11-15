import AppKit
import AVFoundation
import Observation
import ServiceManagement
import SwiftUI
import SteveCore

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, steve }
    let id = UUID()
    let role: Role
    let text: String
    var tool: String?
}

enum AppSection { case chat, presets, settings }

/// Сердце приложения: настройки, диалог, статус Стива и всё, что с ним связано.
@MainActor
@Observable
final class AppModel {
    // MARK: Состояние для интерфейса
    var settings: AppSettings {
        didSet { settingsDidChange(from: oldValue) }
    }
    private(set) var messages = [ChatMessage(role: .steve, text: "Привет, меня зовут Стив, я твой друг. Я всегда рядом, если что-то нужно.")]
    private(set) var status = AssistantStatus.idle {
        didSet { character.apply(status: status) }
    }
    var section = AppSection.chat
    /// Распознанный голосом текст: появляется в строке ввода, пока человек говорит.
    var voiceDraft = ""
    /// Идущие таймеры для панели в окне.
    var activeTimers: [ActiveTimer] = []
    /// Идёт запись голоса и громкость звука 0...1: микрофон в окне пульсирует в такт.
    var isRecordingVoice = false
    var voiceLevel: Float = 0
    /// Только для снимков экрана: показать боковую панель раскрытой.
    var previewSidebarExpanded = false
    private(set) var menuBarImage = NSImage()
    private(set) var voices = Speaker.availableVoices()
    var voiceNote: String?

    // MARK: Службы
    let character = CharacterController()
    let network = NetworkMonitor()
    let permissions = Permissions()
    @ObservationIgnored let tools = Tools()
    @ObservationIgnored let speaker = Speaker()
    @ObservationIgnored let listener = Listener()
    @ObservationIgnored let hotkeys = HotkeyManager()
    @ObservationIgnored var openMainWindow: (() -> Void)?

    @ObservationIgnored private let parser = CommandParser()
    @ObservationIgnored private let engine: OllamaEngine?
    @ObservationIgnored private var isCapturingVoice = false
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var isProcessing = false
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    private static let settingsKey = "settings.v1"

    /// Нужен делегату приложения, чтобы открыть окно по клику на значок в Dock.
    static let shared = AppModel()

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = AppSettings()
        }
        let local = OllamaEngine()
        engine = ProcessInfo.processInfo.environment["STEVE_ENGINE"] == "off" ? nil : local
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { local.shutdown() }
        }
    }

    var isBusy: Bool { status != .idle }

    private func waitUntilFinished() async {
        for _ in 0..<60 where isProcessing { try? await Task.sleep(for: .milliseconds(50)) }
    }
    var quickPresets: [Preset] { settings.quick.compactMap { id in settings.presets.first { $0.id == id } } }

    /// Запускается один раз при старте приложения.
    func start() {
        guard !started, !SnapshotTool.isRequested, !SelfTest.isRequested else { return } // в режиме снимков микрофон не трогаем
        started = true

        character.startIdleLife { [weak self] in self?.isBusy ?? false }
        tools.onTimerFired = { [weak self] seconds in
            guard let self else { return }
            Task { await self.speakAnswer("Таймер на \(Tools.describe(seconds: seconds)) сработал") }
        }
        tools.onTimersChanged = { [weak self] in self?.activeTimers = self?.tools.activeTimers ?? [] }
        hotkeys.onPress = { [weak self] in self?.hotkeyPressed() }
        hotkeys.onRelease = { [weak self] in self?.hotkeyReleased() }
        hotkeys.register(settings.hotkey)

        applyLaunchAtLogin()
        // вернулся из системных настроек: права могли измениться, показываем сразу
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.permissions.refresh() }
        }
        Task {
            await permissions.refresh()
            if permissions.speech == .notAsked || permissions.microphone == .notAsked { await permissions.requestVoice() }
            restartWakeWord()
        }
        Task { await keepMenuBarIconFresh() }
        Task { _ = await engine?.reply(to: "привет", history: []) } // прогрев: модель загружается в память заранее
    }

    // MARK: - Диалог

    /// Полный цикл ответа: слушает, думает, выполняет, отвечает.
    func ask(_ text: String, typed: Bool = false) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isProcessing {
            // новая просьба во время ответа: прерываем речь и ждём, пока прошлый ответ закончится
            guard typed || status == .speaking else { return }
            speaker.stop()
            await waitUntilFinished()
        }
        isProcessing = true
        defer {
            isProcessing = false
            status = .idle // что бы ни случилось внутри, Стив не остаётся «занятым»
        }
        character.touch()

        messages.append(ChatMessage(role: .user, text: trimmed))
        status = .thinking
        var command = parser.parse(trimmed)

        // то, что приложение не умеет само, пробует закрыть языковая модель, если она подключена
        var chatReply: String?
        if case .unknown = command, let engine {
            let history = messages.dropLast().suffix(8).map { ChatTurn(isUser: $0.role == .user, text: $0.text) }
            chatReply = await engine.reply(to: trimmed, history: history)
        }
        if case .unknown = command, chatReply == nil { command = .unknown(trimmed) }

        let needsTool = !(command == .greeting || command == .thanks) && chatReply == nil
        if needsTool { status = .working }
        let result: ToolResult
        if let chatReply {
            result = ToolResult(reply: chatReply, tool: nil)
        } else {
            result = await tools.execute(command)
        }

        let reply = StyleFilter(censorship: settings.censorship).finalize(result.reply)
        messages.append(ChatMessage(role: .steve, text: reply, tool: result.tool))

        status = .speaking
        if JoyWords.matches(trimmed) { character.play(.happy) }
        await speakAnswer(reply)
        status = .idle
    }

    private func speakAnswer(_ text: String) async {
        guard settings.speakAnswers else { return }
        let (voice, pitch) = currentVoice()
        await speaker.speak(text, voice: voice, pitch: pitch)
    }

    /// Пока человек печатает, Стив «слушает» и следит глазами за кареткой.
    func typingChanged(_ text: String) {
        guard !isCapturingVoice, status == .idle || status == .listening else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            status = .idle
            character.stopFollowing()
        } else {
            status = .listening
            character.follow(column: text.split(separator: "\n", omittingEmptySubsequences: false).last?.count ?? 0)
        }
    }

    func clearConversation() {
        messages = Array(messages.prefix(1))
    }

    // MARK: - Голос с микрофона

    /// Нажатие на Стива или на микрофон, а также горячая клавиша.
    func toggleVoiceCapture() {
        if isCapturingVoice { stopVoiceCapture() } else { Task { await captureVoice() } }
    }

    /// Останавливает запись голоса: текст остаётся в строке ввода, ничего не отправляется.
    func cancelTimer(_ id: UUID) { tools.cancel(id) }

    func stopVoiceCapture() {
        stopRequested = true
        listener.endAudio()
    }

    /// Записывает голос, пока человек не нажмёт на микрофон ещё раз. Текст пишется в строку ввода,
    /// чтобы его можно было поправить, и сам не отправляется.
    func captureVoice() async {
        guard !isCapturingVoice, status == .idle || status == .listening else { return }
        isCapturingVoice = true
        stopRequested = false
        // фоновое ожидание слова активации занимает тот же микрофон: на время записи его останавливаем
        pauseWakeWord()
        defer {
            isCapturingVoice = false
            if status == .listening { status = .idle }
            restartWakeWord()
        }
        character.touch()

        // без доступа к микрофону и речи слушать нечем: спрашиваем сейчас, а не молчим
        await permissions.refresh()
        if !permissions.isReadyForVoice, Packaging.isPackaged {
            if permissions.speech == .notAsked || permissions.microphone == .notAsked { await permissions.requestVoice() }
            if !permissions.isReadyForVoice {
                let missing = permissions.microphone != .granted ? "микрофону" : "распознаванию речи"
                messages.append(ChatMessage(role: .steve, text: "Нет доступа к \(missing). Разреши его в Настройках → Разрешения или в системных настройках, раздел «Конфиденциальность»."))
                Permissions.openSettings(permissions.microphone != .granted ? .microphone : .speech)
                return
            }
        }

        status = .listening
        isRecordingVoice = true
        listener.onLevel = { [weak self] level in
            guard let self else { return }
            voiceLevel = max(level, voiceLevel * 0.8) // плавное затухание
        }
        defer {
            isRecordingVoice = false
            voiceLevel = 0
            listener.onLevel = nil
        }
        var committed = voiceDraft.trimmingCharacters(in: .whitespacesAndNewlines) // то, что уже было в строке, остаётся
        func joined(_ extra: String) -> String { committed.isEmpty ? extra : (extra.isEmpty ? committed : committed + " " + extra) }

        while !stopRequested {
            let started = Date()
            do {
                // отрезок записи: система ограничивает его примерно минутой, поэтому склеиваем отрезки
                let text = try await listener.listenOnce(hints: [settings.wakePhrase], silence: nil, maxDuration: 50) { [weak self] partial in
                    self?.voiceDraft = joined(partial)
                }
                committed = joined(text)
                voiceDraft = committed
            } catch {
                if let error = error as? Listener.ListenerError, case .nothingHeard = error {
                    if Date().timeIntervalSince(started) < 1 { try? await Task.sleep(for: .milliseconds(400)) }
                    continue
                }
                messages.append(ChatMessage(role: .steve, text: error.localizedDescription))
                break
            }
        }
        voiceDraft = committed
    }

    private func hotkeyPressed() {
        character.touch()
        switch settings.hotkeyMode {
        case .press: toggleVoiceCapture()
        case .hold: if !isCapturingVoice { Task { await captureVoice() } }
        }
    }

    private func hotkeyReleased() {
        if settings.hotkeyMode == .hold, isCapturingVoice { stopVoiceCapture() }
    }

    // MARK: - Слово активации

    /// Останавливает фоновое прослушивание, например пока микрофон нужен окну записи слова активации.
    func pauseWakeWord() {
        wakeTask?.cancel()
        wakeTask = nil
        listener.stop()
    }

    /// Слушает микрофон в фоне и ждёт слово активации. Следующая фраза после него считается командой.
    func restartWakeWord() {
        wakeTask?.cancel()
        wakeTask = nil
        guard settings.listenAlways, !settings.wakePhrase.isEmpty, Packaging.isPackaged else { return }
        wakeTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.listenForWakeWordOnce()
            }
        }
    }

    private func listenForWakeWordOnce() async {
        await permissions.refresh()
        guard status == .idle, !isCapturingVoice, permissions.isReadyForVoice else {
            try? await Task.sleep(for: .seconds(2)) // ждём, пока освободится или разрешат микрофон и распознавание речи
            return
        }
        let phrase = CommandParser.normalize(settings.wakePhrase)
        do {
            let heard = try await listener.listenOnce(hints: [settings.wakePhrase], silence: 1.2, maxDuration: 50)
            let normalized = CommandParser.normalize(heard)
            guard let range = normalized.range(of: phrase) else { return }
            let tail = String(normalized[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!"))
            showMenuBarPopover() // услышал слово активации: открываем маленькое окно из меню-бара
            if !tail.isEmpty { voiceDraft = tail }
            await captureVoice() // пишем голос, пока не нажмут на микрофон; текст остаётся в строке
        } catch {
            // нет разрешения или ничего не расслышал: ждём немного и пробуем снова
            try? await Task.sleep(for: .seconds(error is Listener.ListenerError ? 3 : 1))
        }
    }

    /// Открывает маленькое окно у значка Стива в меню-баре, как будто на него нажали.
    func showMenuBarPopover() {
        func findButton(in view: NSView) -> NSStatusBarButton? {
            if let button = view as? NSStatusBarButton { return button }
            for sub in view.subviews { if let found = findButton(in: sub) { return found } }
            return nil
        }
        for window in NSApp.windows {
            guard String(describing: type(of: window)).contains("StatusBar"),
                  let content = window.contentView, let button = findButton(in: content) else { continue }
            let isOpen = NSApp.windows.contains { $0.isVisible && String(describing: type(of: $0)).contains("MenuBarExtra") }
            if !isOpen { button.performClick(nil) }
            return
        }
    }

    // MARK: - Голос Стива

    /// Системный голос и тон для озвучки: выбранный свой голос или голос из списка.
    func currentVoice() -> (AVSpeechSynthesisVoice?, Float) {
        let base = voices.first { Speaker.isPersonal($0) && $0.identifier == settings.voiceIdentifier }
            ?? voices.first { $0.identifier == settings.voiceIdentifier }
            ?? voices.first { $0.language.hasPrefix("ru") }
        if let id = settings.selectedCustomVoice, let custom = settings.customVoices.first(where: { $0.id == id }) {
            return (voices.first { $0.language.hasPrefix("ru") } ?? base, custom.pitchMultiplier)
        }
        return (base, 1)
    }

    func refreshVoices() async {
        _ = await Speaker.requestPersonalVoiceAccess()
        voices = Speaker.availableVoices()
    }

    func previewVoice() {
        Task { await speakPreview() }
    }

    private func speakPreview() async {
        let (voice, pitch) = currentVoice()
        // образец на языке выбранного голоса: английский голос не прочтёт русскую фразу
        let sample = voice?.language.hasPrefix("en") == true ? "Hi, my name is Steve" : "Привет, меня зовут Стив"
        await speaker.speak(sample, voice: voice, pitch: pitch)
    }

    /// Свой голос из аудиофайла: измеряем тон и говорим системным голосом с этим тоном.
    func addCustomVoice(from url: URL) async {
        voiceNote = "Слушаю запись…"
        let analysis: (Double?, String) = await Task.detached {
            guard let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil,
                  let channel = buffer.floatChannelData?[0] else { return (nil, url.deletingPathExtension().lastPathComponent) }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            return (PitchEstimator.estimate(samples: samples, sampleRate: file.processingFormat.sampleRate), url.deletingPathExtension().lastPathComponent)
        }.value

        guard let hertz = analysis.0 else {
            voiceNote = "В записи не слышно голоса или файл не читается. Подойдёт аудио: mp3, wav, m4a."
            return
        }
        let voice = CustomVoice(name: analysis.1, hertz: hertz)
        settings.customVoices.append(voice)
        settings.selectedCustomVoice = voice.id
        voiceNote = "Тон вашего голоса: \(Int(hertz)) Гц. Стив говорит с этим тоном."
        previewVoice()
    }

    // MARK: - Пресеты

    func save(preset: Preset) {
        if let index = settings.presets.firstIndex(where: { $0.id == preset.id }) {
            settings.presets[index] = preset
        } else {
            settings.presets.append(preset)
        }
    }

    func setQuick(slot: Int, to id: UUID) {
        guard settings.quick.indices.contains(slot), !settings.quick.contains(id) || settings.quick[slot] == id else { return }
        settings.quick[slot] = id
    }

    func runPreset(_ preset: Preset) {
        Task { await ask(preset.phrase) }
    }

    // MARK: - Побочные эффекты настроек

    private func settingsDidChange(from old: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        if old.hotkey != settings.hotkey { hotkeys.register(settings.hotkey) }
        if old.launchAtLogin != settings.launchAtLogin { applyLaunchAtLogin() }
        if old.listenAlways != settings.listenAlways || old.wakePhrase != settings.wakePhrase { restartWakeWord() }
    }

    private func applyLaunchAtLogin() {
        do {
            if settings.launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // запуск из папки сборки без установки в «Программы» не регистрируется, это нормально
        }
    }

    // MARK: - Значок в меню-баре

    /// Значок в меню-баре перерисовывается, пока Стив что-то делает, и реже, пока он спокоен.
    private func keepMenuBarIconFresh() async {
        while !Task.isCancelled {
            let renderer = ImageRenderer(content: SteveCanvas(frame: character.frame(at: Date()), isTiny: true).frame(width: 21, height: 23))
            renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
            if let image = renderer.nsImage { menuBarImage = image }
            try? await Task.sleep(for: .milliseconds(character.animation == nil && !character.isAsleep ? 400 : 120))
        }
    }
}
