import AVFoundation
import SteveCore

/// Озвучка ответов системным синтезатором речи. Работает без интернета.
/// Поддерживает «Личный голос» из настроек macOS и свой голос из файла (системный голос с измеренным тоном).
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var finished: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Русские и английские голоса: русские первыми, личные голоса отмечены.
    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ru") || $0.language.hasPrefix("en") }
            .sorted { lhs, rhs in
                let lhsRussian = lhs.language.hasPrefix("ru")
                let rhsRussian = rhs.language.hasPrefix("ru")
                if lhsRussian != rhsRussian { return lhsRussian }
                return lhs.name < rhs.name
            }
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

    /// Произносит текст и ждёт, пока речь закончится. Кавычки, скобки и значки разметки не читаются.
    func speak(_ text: String, voice: AVSpeechSynthesisVoice?, pitch: Float = 1) async {
        let clean = SpeechText.clean(text)
        guard !clean.isEmpty else { return }

        // Прерываем только настоящую речь и только по границе слова: резкая остановка даёт щелчок.
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .word) }

        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: clean.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil ? "ru-RU" : "en-US")
        if pitch != 1 { utterance.pitchMultiplier = pitch }
        utterance.postUtteranceDelay = 0.15 // даём звуку допеть до конца, чтобы речь не обрывалась щелчком

        await withCheckedContinuation { continuation in
            finished?.resume() // предыдущая фраза прервана, отпускаем тех, кто её ждал
            finished = continuation
            synthesizer.speak(utterance)
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
