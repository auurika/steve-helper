import AppKit
import AVFoundation
import EventKit
import Speech
import SteveCore

/// Служебный режим для разработки: `Steve --selftest <файл>` прогоняет настоящие команды через приложение
/// и пишет в файл, что получилось. Запускать через `open -n -a Стив.app --args --selftest <файл>`,
/// чтобы разрешения брались у самого приложения, а не у терминала.
@MainActor
enum SelfTest {
    static var isRequested: Bool { ["--selftest", "--add-voice", "--move-test", "--setup-test"].contains { CommandLine.arguments.contains($0) } }

    /// `Steve --add-voice <файл> <имя> <отчёт>`: добавляет свой голос из записи без окна выбора файла.
    private static func addVoiceIfRequested(model: AppModel) -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--add-voice"), arguments.count > index + 3 else { return false }
        let file = URL(fileURLWithPath: arguments[index + 1])
        let name = arguments[index + 2]
        let report = URL(fileURLWithPath: arguments[index + 3])
        Task {
            await model.addCustomVoice(from: file)
            if let last = model.settings.customVoices.indices.last { model.settings.customVoices[last].name = name }
            try? "\(model.voiceNote ?? "нет заметки")\nголосов: \(model.settings.customVoices.map(\.name))\n".write(to: report, atomically: true, encoding: .utf8)
            try? await Task.sleep(for: .seconds(1))
            NSApp.terminate(nil)
        }
        return true
    }

    /// `Steve --move-test <папка> <отчёт> <файл>...`: прикрепляет файлы, кладёт их в папку и затем отменяет.
    private static func moveTestIfRequested(model: AppModel) -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--move-test"), arguments.count > index + 3 else { return false }
        let folder = arguments[index + 1]
        let report = URL(fileURLWithPath: arguments[index + 2])
        let files = arguments[(index + 3)...].map { URL(fileURLWithPath: $0) }
        Task {
            model.attach(files)
            var log = ""
            let moved = await model.tools.execute(.moveAttached(folder: folder, copy: false))
            log += "перенос: \(moved.reply)\n"
            let undone = await model.tools.execute(.undo)
            log += "откат: \(undone.reply)\n"
            try? log.write(to: report, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
        return true
    }

    /// `Steve --setup-test <отчёт>`: скачивает Ollama в пустую папку и маленькую модель, показывает, что ход загрузки виден.
    private static func setupTestIfRequested(model: AppModel) -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--setup-test"), arguments.count > index + 1 else { return false }
        let report = URL(fileURLWithPath: arguments[index + 1])
        Task {
            var log = ""
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("steve-setup-test", isDirectory: true)
            do {
                try await model.chatSetup.downloadBinary(into: folder)
                let version = await ProcessRunner.run(folder.appendingPathComponent("ollama").path, ["--version"], timeout: 30)
                log += "Ollama скачана и распакована, версия: \(version.output.trimmingCharacters(in: .whitespacesAndNewlines)) \(version.error.trimmingCharacters(in: .whitespacesAndNewlines))\n"
            } catch { log += "ошибка загрузки Ollama: \(error.localizedDescription)\n" }
            var seen = Set<Int>()
            let watcher = Task { @MainActor in
                while !Task.isCancelled {
                    if case .working(_, let progress) = model.chatSetup.state, let progress { seen.insert(Int(progress * 10)) }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            do {
                try await model.chatSetup.pullModel("all-minilm")
                log += "модель all-minilm скачана, ступени хода загрузки: \(seen.sorted())\n"
            } catch { log += "ошибка загрузки модели: \(error.localizedDescription)\n" }
            watcher.cancel()
            try? log.write(to: report, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
        return true
    }

    static func runIfRequested(model: AppModel) {
        if setupTestIfRequested(model: model) { return }
        if moveTestIfRequested(model: model) { return }
        if addVoiceIfRequested(model: model) { return }
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--selftest"), arguments.indices.contains(index + 1) else { return }
        let output = URL(fileURLWithPath: arguments[index + 1])

        Task {
            var log = ""
            func note(_ line: String) {
                log += line + "\n"
                try? log.write(to: output, atomically: true, encoding: .utf8)
            }

            try? await Task.sleep(for: .milliseconds(800))
            note("упаковано в .app: \(Packaging.isPackaged)")
            note("доступ: речь=\(SFSpeechRecognizer.authorizationStatus().rawValue) (3=есть), микрофон=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) (3=есть), календарь=\(EKEventStore.authorizationStatus(for: .event).rawValue) (3=полный)")
            if CommandLine.arguments.contains("--ask-speech") {
                let got = await withCheckedContinuation { (c: CheckedContinuation<Int, Never>) in
                    var done = false
                    SFSpeechRecognizer.requestAuthorization { status in if !done { done = true; c.resume(returning: status.rawValue) } }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 25) { if !done { done = true; c.resume(returning: -1) } }
                }
                let mic = await AVAudioApplication.requestRecordPermission()
                note("запрос микрофона вернул: \(mic)")
                note("запрос речи вернул: \(got) (-1 = ответа нет за 25 с)")
            }
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
            note("распознавание ru-RU: доступно=\(recognizer?.isAvailable ?? false), на устройстве=\(recognizer?.supportsOnDeviceRecognition ?? false)")
            note("голоса: \(model.voices.count) шт., русские: \(model.voices.filter { $0.language.hasPrefix("ru") }.map(\.name))")

            // 1) команды через полный цикл ask(): проверяем, что ответ приходит и статус возвращается в «Готов»
            for phrase in ["сколько времени", "сколько заряда", "запусти секундомер", "останови секундомер", "таймер на 2 секунды", "привет", "спасибо", "почему небо голубое", "как лучше выучить английский"] {
                let before = model.messages.count
                let started = Date()
                let finished = await finishes(within: 120) { await model.ask(phrase, typed: true) }
                let reply = model.messages.dropFirst(before).last(where: { $0.role == .steve })
                note("[\(finished ? "OK" : "ЗАВИС")] «\(phrase)» -> «\(reply?.text ?? "нет ответа")» tool=\(reply?.tool ?? "-") за \(String(format: "%.1f", Date().timeIntervalSince(started))) с, статус после: \(model.status.label)")
            }

            // 2) быстрая команда после предыдущих: не должна блокироваться
            let before = model.messages.count
            if let preset = model.quickPresets.first(where: { $0.phrase.contains("Safari") }) {
                _ = preset // Safari не открываем, проверяем только таймер
            }
            model.runPreset(Preset(name: "t", description: "t", phrase: "таймер на 1 минуту", symbol: "timer"))
            try? await Task.sleep(for: .seconds(6))
            note("быстрая команда: сообщений добавилось \(model.messages.count - before), статус \(model.status.label)")

            // 3) выбор голоса: то, что выбрано в настройках, должно попадать в озвучку
            if let other = model.voices.first(where: { $0.language.hasPrefix("en") }) {
                model.settings.voiceIdentifier = other.identifier
                model.settings.selectedCustomVoice = nil
                note("голос выбран: \(other.name); озвучка возьмёт: \(model.currentVoice().0?.name ?? "nil")")
            }

            // 4) распознавание речи по записи, сделанной системным синтезатором
            if SFSpeechRecognizer.authorizationStatus() == .authorized, let recognizer, recognizer.isAvailable {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("steve-selftest.aiff")
                let say = Process()
                say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                say.arguments = ["-v", "Milena", "-o", file.path, "открой калькулятор"]
                try? say.run()
                say.waitUntilExit()
                let text = await recognize(file: file, with: recognizer)
                note("распознавание записи: «\(text ?? "ошибка")»")
            } else {
                note("распознавание записи пропущено: нет доступа к распознаванию речи")
            }

            if SFSpeechRecognizer.authorizationStatus() == .authorized, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                var peak: Float = 0
                let listener = Listener()
                listener.onLevel = { peak = max(peak, $0) }
                do { _ = try await listener.listenOnce(silence: 1, maxDuration: 3) } catch { note("микрофон: слушал 3 с без падения, итог: \(error.localizedDescription)") }
                note("микрофон: максимум уровня \(String(format: "%.3f", peak)) (0 = тишина или нет звука)")
            }
            note("конец")
            NSApp.terminate(nil)
        }
    }

    /// Выполняет работу и сообщает, закончилась ли она за отведённое время.
    private static func finishes(within seconds: Double, _ work: @escaping @MainActor () async -> Void) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await work(); return true }
            group.addTask { try? await Task.sleep(for: .seconds(seconds)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    private static func recognize(file: URL, with recognizer: SFSpeechRecognizer) async -> String? {
        await withCheckedContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: file)
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let result, result.isFinal {
                    resumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    resumed = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
