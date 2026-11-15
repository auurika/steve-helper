import Foundation

/// Движок живого разговора на темы, которые Стив не умеет выполнять командами.
///
/// Сейчас Стив работает только по командам и коротким репликам. Языковую модель внутри приложения
/// ещё предстоит встроить: системная модель Apple не знает русский язык, поэтому нужна своя модель в пакете.
protocol ChatEngine {
    /// Ответ на реплику или nil, если ответить нечем.
    func reply(to text: String) async -> String?
}

/// Необязательный режим для разработки: разговор через локальный Ollama (STEVE_ENGINE=ollama).
/// В готовое приложение он не входит и по умолчанию выключен.
struct OllamaEngine: ChatEngine {
    private let model = ProcessInfo.processInfo.environment["STEVE_OLLAMA_MODEL"] ?? "qwen3:8b"
    private let endpoint = URL(string: "http://127.0.0.1:11434/api/chat")!

    func reply(to text: String) async -> String? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "think": false,
            "messages": [
                ["role": "system", "content": "Ты Стив, дружелюбный голосовой помощник на Mac. Отвечай коротко, 1–2 фразы, без разметки."],
                ["role": "user", "content": text],
            ],
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = payload
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
