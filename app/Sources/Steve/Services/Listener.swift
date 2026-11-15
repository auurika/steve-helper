import AVFoundation
import Speech

/// Распознавание речи на устройстве: Стив слушает микрофон и превращает речь в текст без интернета.
@MainActor
final class Listener {
    enum ListenerError: Error, LocalizedError {
        case notAuthorized, unavailable, nothingHeard

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Нет доступа к микрофону или распознаванию речи. Разрешите его в настройках macOS."
            case .unavailable: return "Распознавание речи сейчас недоступно."
            case .nothingHeard: return "Ничего не расслышал."
            }
        }
    }

    /// Уровень звука 0...1 для волны в окне записи слова активации.
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finish: ((Result<String, Error>) -> Void)?
    private var silenceTimer: Timer?
    private var hasSpeech = false

    var isListening: Bool { engine.isRunning }

    static func requestAuthorization() async -> Bool {
        guard Packaging.isPackaged else { return false }
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// Слушает, пока человек говорит, и возвращает текст, когда он замолчал на `silence` секунд.
    func listenOnce(locale: Locale = Locale(identifier: "ru-RU"), hints: [String] = [],
                    silence: TimeInterval? = 1.2, maxDuration: TimeInterval = 55,
                    onPartial: ((String) -> Void)? = nil) async throws -> String {
        guard await Self.requestAuthorization() else { throw ListenerError.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { throw ListenerError.unavailable }
        stop()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = hints
        // распознаём на устройстве, если язык это умеет: так работает без интернета и ничего не уходит наружу
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        hasSpeech = false

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        // замыкание делаем вне главного актора: звук приходит на своём потоке, и проверка изоляции иначе роняет приложение
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(request: request) { [weak self] level in
            Task { @MainActor in self?.onLevel?(level) }
        })
        engine.prepare()
        try engine.start()
        NSLog("Steve.listener started, format=%@", format.description)

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let complete: (Result<String, Error>) -> Void = { [weak self] result in
                guard !resumed else { return }
                resumed = true
                self?.teardown()
                continuation.resume(with: result)
            }
            self.finish = complete

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        NSLog("Steve.listener partial=%@ final=%d", text, result.isFinal ? 1 : 0)
                        if !text.isEmpty { self.hasSpeech = true }
                        onPartial?(text)
                        if let silence { self.restartSilenceTimer(after: silence) }
                        if result.isFinal {
                            complete(text.isEmpty ? .failure(ListenerError.nothingHeard) : .success(text))
                        }
                    } else if let error {
                        NSLog("Steve.listener error=%@", error.localizedDescription)
                        complete(.failure(ListenerError.nothingHeard))
                    }
                }
            }
            // тишина: если за 10 секунд никто не заговорил, заканчиваем
            if silence != nil { DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self, self.request === request, !self.hasSpeech else { return }
                self.endAudio()
            } }
            // предел распознавания системы около минуты: заканчиваем раньше
            DispatchQueue.main.asyncAfter(deadline: .now() + maxDuration) { [weak self] in self?.endAudio() }
        }
    }

    /// Останавливает запись: распознавание отдаст то, что успело услышать.
    func endAudio() {
        silenceTimer?.invalidate()
        request?.endAudio()
    }

    func stop() {
        silenceTimer?.invalidate()
        task?.cancel()
        finish?(.failure(ListenerError.nothingHeard))
        teardown()
    }

    // MARK: - Внутреннее

    private func restartSilenceTimer(after seconds: TimeInterval) {
        silenceTimer?.invalidate()
        guard hasSpeech else { return }
        silenceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.endAudio() }
        }
    }

    private func teardown() {
        silenceTimer?.invalidate()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        finish = nil
    }

    private nonisolated static func makeTap(request: SFSpeechAudioBufferRecognitionRequest,
                                            onLevel: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            onLevel(level(of: buffer))
        }
    }

    private nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        return min(1, (sum / Float(count)).squareRoot() * 6)
    }
}
