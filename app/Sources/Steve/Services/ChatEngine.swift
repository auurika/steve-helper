import Foundation

/// Реплика прошлого разговора, которую видит языковая модель.
struct ChatTurn {
    var isUser: Bool
    var text: String
}

/// Движок живого разговора на темы, которые Стив не умеет выполнять командами.
protocol ChatEngine {
    /// Ответ на реплику или nil, если ответить нечем.
    func reply(to text: String, history: [ChatTurn], allowProfanity: Bool, fileContext: String?) async -> String?
}

/// Локальная языковая модель через Ollama. Всё работает на этом Mac, интернет нужен только один раз,
/// чтобы скачать модель. Если сервер Ollama не запущен, Стив запускает его сам.
@MainActor
final class OllamaEngine: ChatEngine {
    let base = URL(string: "http://127.0.0.1:11434")!
    private var server: Process?
    private var chosenModel: String?

    /// Копия Ollama, которую Стив скачал сам (если на Маке её не было).
    static var ownDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Steve/ollama", isDirectory: true)
    }

    func forgetChosenModel() { chosenModel = nil }

    /// Модели в порядке предпочтения: лучше всех говорят по-русски.
    private static let preferred = ["qwen3", "qwen2.5", "gemma3", "llama3", "mistral"]
    static var binaryPaths: [String] {
        ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/Applications/Ollama.app/Contents/Resources/ollama",
         ownDirectory.appendingPathComponent("ollama").path]
    }

    var isInstalled: Bool { Self.binaryPaths.contains { FileManager.default.isExecutableFile(atPath: $0) } }

    func shutdown() {
        server?.terminate() // гасим только тот сервер, который запустили сами
    }

    func reply(to text: String, history: [ChatTurn], allowProfanity: Bool = false, fileContext: String? = nil) async -> String? {
        guard await ensureServer(), let model = await pickModel() else { return nil }

        // манера речи: при выключенной цензуре Стив говорит как друг, с матом к месту, а не вежливым ассистентом
        // примеры манеры каждый раз берутся из большого набора разные: одни и те же примеры модель начинает повторять
        let examples = ["Да нормально, бля, живу", "Хуйня вопрос, щас разберёмся", "Ну пиздец, конечно", "Тут без вариантов, брат", "Слушай, ебать, это жёстко",
                        "Ладно, поехали нахуй", "Всё чётко, не парься", "Ну ты даёшь, бля", "Да похуй, давай по делу", "Ща всё порешаем, брат",
                        "Охуенно, продолжай", "Ебаный день, но держимся"].shuffled().prefix(3).map { "«\($0)»" }.joined(separator: ", ")
        let manner = allowProfanity
            ? " Говори как близкий друг по-пацански: просто, грубовато, с матом. Вставляй матерное слово (бля, хуй, нахуй, пиздец, ёбаный, хуйня и подобные) примерно в каждом втором ответе, где оно звучит естественно. Примеры манеры, но не копируй их: \(examples). Не оскорбляй собеседника, не извиняйся и не читай нотаций, отвечай коротко."
            : " Выражайся прилично, без мата."
        var messages: [[String: String]] = [[
            "role": "system",
            "content": "Ты Стив, дружелюбный голосовой помощник на Mac, пиксельный фиолетовый осьминог. Отвечай по-русски, если с тобой говорят по-русски. Отвечай коротко: одна короткая фраза, максимум две, без списков, без разметки, без эмодзи. Заметки, события календаря, таймеры, громкость и запуск приложений ты сам не выполняешь, их делают отдельные команды. Никогда не обещай их выполнить и не говори «создам». Если просят такое, коротко подскажи фразу, например: «Запиши заметку: купить молоко».\(manner)",
        ]]
        // память короткая: последний обмен, а ответы Стива сжаты до первых слов, чтобы модель не пересказывала их
        for turn in history.suffix(2) {
            let content = turn.isUser ? turn.text : turn.text.split(separator: " ").prefix(10).joined(separator: " ") + "…"
            messages.append(["role": turn.isUser ? "user" : "assistant", "content": content])
        }
        // свои недавние ответы модель видит отдельным списком и не повторяет их
        let recent = history.filter { !$0.isUser }.suffix(6).map(\.text)
        if !recent.isEmpty {
            // цитируем только начала прошлых ответов: целиком их модель начинает пересказывать
            let openings = recent.map { reply in "«" + reply.split(separator: " ").prefix(4).joined(separator: " ") + "…»" }
            messages[0]["content"]! += " Отвечай каждый раз по-новому: другими словами, другим началом и другим настроением, и не возвращайся к темам прошлых ответов. Так уже начинал, так больше не начинай: " + openings.joined(separator: ", ") + "."
        }
        // прикреплённые файлы: модель отвечает по их содержимому
        if let fileContext, !fileContext.isEmpty {
            messages[0]["content"]! += " Пользователь прислал файлы, их содержимое ниже. Отвечай по нему и ничего не выдумывай. Если просят пересказать или объяснить, можно до пяти коротких фраз.\n\nФАЙЛЫ:\n" + fileContext
        }
        messages.append(["role": "user", "content": text])

        // первая попытка с обычным разбросом, при повторе вторая с большим разбросом и новым зерном
        for attempt in 0..<2 {
            let options: [String: Any] = [
                "temperature": attempt == 0 ? 0.95 : 1.15, "top_p": 0.95, "repeat_penalty": 1.25,
                "num_predict": (fileContext?.isEmpty == false) ? 400 : 120, "seed": Int.random(in: 1...1_000_000),
            ]
            let body: [String: Any] = ["model": model, "stream": false, "think": false, "messages": messages, "options": options]
            guard let json = await post("api/chat", body: body, timeout: 120),
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? String else { return nil }
            let clean = content.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return nil }
            if attempt == 1 || !Self.repeats(clean, recent: recent) { return clean }
        }
        return nil
    }

    /// Ответ повторяет недавний: совпадает целиком или начинается с тех же трёх слов.
    private static func repeats(_ reply: String, recent: [String]) -> Bool {
        func key(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " } }
        let new = key(reply)
        let newStart = new.split(separator: " ").prefix(3).joined(separator: " ")
        return recent.contains { old in
            let oldKey = key(old)
            return oldKey == new || (!newStart.isEmpty && oldKey.split(separator: " ").prefix(3).joined(separator: " ") == newStart)
        }
    }

    // MARK: - Сервер и модель

    func ensureServer() async -> Bool {
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

    func pickModel() async -> String? {
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

    func post(_ path: String, body: [String: Any], timeout: TimeInterval) async -> [String: Any]? {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
