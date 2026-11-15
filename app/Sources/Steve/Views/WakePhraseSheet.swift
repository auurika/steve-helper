import SwiftUI
import SteveCore

/// Слово активации: фраза и три записи голоса. Запись принимается, только если Стив расслышал фразу,
/// так что окно заодно проверяет, что распознавание вас понимает.
struct WakePhraseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var phrase = ""
    @State private var recorded = 0
    @State private var isRecording = false
    @State private var level: Float = 0
    @State private var hint = ""

    private let samplesNeeded = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Слово активации").font(.system(size: 18, weight: .semibold))
            Text("Напиши фразу и произнеси её 3 раза обычным голосом. Стив запомнит твой голос и будет реже ошибаться.")
                .foregroundStyle(Color.steveMuted)

            CountedField(title: "Фраза", text: $phrase, limit: 30, height: 44)
                .onChange(of: phrase) { recorded = 0; hint = "" }

            VStack(spacing: 8) {
                Text(hint.isEmpty ? defaultHint : hint).font(.system(size: 12)).foregroundStyle(Color.steveMuted)
                Text("«\(phrase)»").font(.system(size: 20))
                waveform
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))

            HStack(spacing: 8) {
                ForEach(0..<samplesNeeded, id: \.self) { index in
                    Text("\(index + 1) · \(index < recorded ? "готово" : "ожидает")")
                        .font(.system(size: 12))
                        .foregroundStyle(index < recorded ? Color.steveOK : (index == recorded ? Color.steveText : Color.steveMuted))
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .glassControl(cornerRadius: 12)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(index < recorded ? Color.steveOK : (index == recorded ? Color.steveAccent : .clear), lineWidth: 1)
                        }
                }
            }

            Text("Лучше записывать в тишине. Короткие фразы из 2–3 слов работают надёжнее.")
                .font(.system(size: 12)).foregroundStyle(Color.steveMuted)

            HStack {
                Spacer()
                Button { record() } label: {
                    Label(isRecording ? "Слушаю…" : "Записать", systemImage: "record.circle")
                }
                .disabled(isRecording || recorded >= samplesNeeded || phrase.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Сохранить") {
                    model.settings.wakePhrase = phrase.trimmingCharacters(in: .whitespaces)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(recorded < samplesNeeded)
            }
        }
        .padding(22)
        .frame(width: 440)
        .foregroundStyle(Color.steveText)
        .onAppear {
            phrase = model.settings.wakePhrase
            model.pauseWakeWord() // микрофон нужен окну записи
        }
        .onDisappear { model.restartWakeWord() }
    }

    private var defaultHint: String {
        recorded >= samplesNeeded
            ? "Все образцы записаны. Сохрани, чтобы применить."
            : "Образец \(recorded + 1) из \(samplesNeeded) — нажми «Записать» и произнеси:"
    }

    private var waveform: some View {
        HStack(spacing: 3) {
            ForEach(0..<28, id: \.self) { index in
                let wobble = isRecording ? CGFloat(abs(sin(Double(index) * 1.7 + Double(level) * 9))) : 0
                Capsule()
                    .fill(isRecording ? Color.steveAccent2 : Color.steveMuted)
                    .frame(width: 4, height: 6 + CGFloat(level) * 28 * wobble)
            }
        }
        .frame(height: 36)
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func record() {
        isRecording = true
        hint = "Говори сейчас…"
        model.listener.onLevel = { level = $0 }
        Task {
            defer {
                isRecording = false
                level = 0
                model.listener.onLevel = nil
            }
            do {
                let heard = try await model.listener.listenOnce(hints: [phrase], silence: 0.9, maxDuration: 6)
                if Self.matches(heard: heard, phrase: phrase) {
                    recorded += 1
                    hint = ""
                } else {
                    hint = "Расслышал «\(heard)». Скажи ещё раз:"
                }
            } catch {
                hint = error.localizedDescription
            }
        }
    }

    /// Фраза засчитывается, если совпала целиком или хотя бы 60% слов.
    static func matches(heard: String, phrase: String) -> Bool {
        let target = CommandParser.normalize(phrase).split(separator: " ").map(String.init)
        let said = Set(CommandParser.normalize(heard).split(separator: " ").map(String.init))
        guard !target.isEmpty else { return false }
        let hits = target.filter(said.contains).count
        return Double(hits) / Double(target.count) >= 0.6
    }
}
