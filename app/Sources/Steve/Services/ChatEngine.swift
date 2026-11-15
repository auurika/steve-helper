import Foundation

/// Реплика прошлого разговора, которую видит языковая модель.
struct ChatTurn {
    var isUser: Bool
    var text: String
}

/// Движок живого разговора на темы, которые Стив не умеет выполнять командами.
protocol ChatEngine {
    /// Ответ на реплику или nil, если ответить нечем.
    func reply(to text: String, history: [ChatTurn], allowProfanity: Bool) async -> String?
}

/// Локальная языковая модель через Ollama. Всё работает на этом Mac, интернет нужен только один раз,
/// чтобы скачать модель. Если сервер Ollama не запущен, Стив запускает его сам.
@MainActor
final class OllamaEngine: ChatEngine {
    private let base = URL(string: "http://127.0.0.1:11434")!
    private var server: Process?
    private var chosenModel: String?

    /// Модели в порядке предпочтения: лучше всех говорят по-русски.
    private static let preferred = ["qwen3", "qwen2.5", "gemma3", "llama3", "mistral"]
    private static let binaryPaths = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama",
                                      "/Applications/Ollama.app/Contents/Resources/ollama"]

    var isInstalled: Bool { Self.binaryPaths.contains { FileManager.default.isExecutableFile(atPath: $0) } }

    func shutdown() {
        server?.terminate() // гасим только тот сервер, который запустили сами
    }

    func reply(to text: String, history: [ChatTurn], allowProfanity: Bool = false) async -> String? {
        guard await ensureServer(), let model = await pickModel() else { return nil }

        // манера речи: при выключенной цензуре Стив говорит как друг, с матом к месту, а не вежливым ассистентом
        let manner = allowProfanity
            ? " Говори как близкий друг по-пацански: просто, грубовато, с матом. Обязательно вставляй в ответ матерное слово (бля, хуй, нахуй, пиздец, ёбаный, хуйня и подобные) примерно в каждом втором ответе, там где оно звучит естественно. Примеры твоей манеры: «Да нормально, бля, живу», «Хуйня вопрос, щас разберёмся», «Ну пиздец, конечно». Не оскорбляй собеседника, не извиняйся и не читай нотаций, отвечай коротко."
            : " Выражайся прилично, без мата."
        var messages: [[String: String]] = [[
            "role": "system",
            "content": "Ты Стив, дружелюбный голосовой помощник на Mac, пиксельный фиолетовый осьминог. Отвечай по-русски, если с тобой говорят по-русски. Отвечай коротко: одна-две фразы, без списков, без разметки, без эмодзи. Заметки, события календаря, таймеры, громкость и запуск приложений ты сам не выполняешь, их делают отдельные команды. Никогда не обещай их выполнить и не говори «создам». Если просят такое, коротко подскажи фразу, например: «Запиши заметку: купить молоко».\(manner)",
        ]]
        for turn in history.suffix(8) {
            messages.append(["role": turn.isUser ? "user" : "assistant", "content": turn.text])
        }
        messages.append(["role": "user", "content": text])

        let body: [String: Any] = ["model": model, "stream": false, "think": false, "messages": messages,
                                   "options": ["temperature": 0.7, "num_predict": 200]]
        guard let json = await post("api/chat", body: body, timeout: 120),
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        let clean = content.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    // MARK: - Сервер и модель

    private func ensureServer() async -> Bool {
        if await isRunning() { return true }
        guard let path = Self.binaryPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        server = process
        for _ in 0..<40 { // ждём до 10 секунд
            try? await Task.sleep(for: .milliseconds(250))
            if await isRunning() { return true }
        }
        return false
    }

    private func isRunning() async -> Bool {
        var request = URLRequest(url: base.appendingPathComponent("api/tags"))
        request.timeoutInterval = 1.5
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private func pickModel() async -> String? {
        if let chosenModel { return chosenModel }
        if let forced = ProcessInfo.processInfo.environment["STEVE_OLLAMA_MODEL"] { return forced }
        var request = URLRequest(url: base.appendingPathComponent("api/tags"))
        request.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return nil }
        let names = models.compactMap { $0["name"] as? String }
        let pick = Self.preferred.lazy.compactMap { family in names.first { $0.hasPrefix(family) } }.first ?? names.first
        chosenModel = pick
        return pick
    }

    private func post(_ path: String, body: [String: Any], timeout: TimeInterval) async -> [String: Any]? {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
