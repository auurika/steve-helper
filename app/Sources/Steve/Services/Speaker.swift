import AVFoundation
import SteveCore

/// Озвучка ответов системным синтезатором речи. Работает без интернета.
/// Поддерживает «Личный голос» из настроек macOS и свой голос из файла (системный голос с измеренным тоном).
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var finished: CheckedContinuation<Void, Never>?
    private var currentToken: UUID?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Голоса для выбора: мужской русский голос Юрий (системный, работает без сети) и личные голоса пользователя.
    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { isSteveVoice($0) || isPersonal($0) }
    }

    /// Юрий: единственный мужской русский голос macOS. Скачивается один раз в «Универсальный доступ → Устная речь».
    static func isSteveVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.language.hasPrefix("ru") && voice.identifier.localizedCaseInsensitiveContains("yuri")
    }

    static func isPersonal(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.voiceTraits.contains(.isPersonalVoice)
    }

    /// Просит доступ к «Личному голосу». Без него личные голоса в списке не появятся.
    static func requestPersonalVoiceAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Язык текста: русский, если есть кириллица, иначе английский.
    static func language(of text: String) -> String {
        text.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil ? "ru-RU" : "en-US"
    }

    /// Голос для нужного языка. Выбранный голос подходит, только если говорит на этом языке: английский голос
    /// молчит или коверкает русский текст. Иначе берём лучший голос языка: личный, затем улучшенный.
    static func voice(for language: String, preferred: AVSpeechSynthesisVoice?) -> AVSpeechSynthesisVoice? {
        let prefix = String(language.prefix(2))
        if let preferred, preferred.language.hasPrefix(prefix) { return preferred }
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
        let best = candidates.max { lhs, rhs in
            (isPersonal(lhs) ? 1 : 0, lhs.quality.rawValue) < (isPersonal(rhs) ? 1 : 0, rhs.quality.rawValue)
        }
        return best ?? AVSpeechSynthesisVoice(language: language)
    }

    /// Произносит текст и ждёт, пока речь закончится. Кавычки, скобки и значки разметки не читаются.
    func speak(_ text: String, voice: AVSpeechSynthesisVoice?, pitch: Float = 1) async {
        let clean = SpeechText.clean(text)
        guard !clean.isEmpty else { return }

        // Прерываем только настоящую речь и только по границе слова: резкая остановка даёт щелчок.
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .word) }

        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = Self.voice(for: Self.language(of: clean), preferred: voice)
        if pitch != 1 { utterance.pitchMultiplier = pitch }
        utterance.postUtteranceDelay = 0.15 // даём звуку допеть до конца, чтобы речь не обрывалась щелчком

        // Если синтезатор по какой-то причине не сообщит об окончании, Стив не должен зависнуть в «Выполняет».
        let token = UUID()
        let limit = max(4, Double(clean.count) / 8 + 3)
        await withCheckedContinuation { continuation in
            finished?.resume() // предыдущая фраза прервана, отпускаем тех, кто её ждал
            finished = continuation
            currentToken = token
            synthesizer.speak(utterance)
            DispatchQueue.main.asyncAfter(deadline: .now() + limit) { [weak self] in
                guard let self, self.currentToken == token else { return }
                self.finished?.resume()
                self.finished = nil
            }
        }
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .word) }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.finished?.resume()
            self.finished = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.finished?.resume()
            self.finished = nil
        }
    }
}
