import Foundation
import Observation

/// Подготовка свободного разговора: если на Маке нет Ollama или модели, Стив скачивает их сам, один раз, с показом хода загрузки.
/// Ollama берётся с официальной страницы выпусков, модель из официального каталога Ollama.
@MainActor
@Observable
final class ChatSetup {
    enum State: Equatable {
        case checking
        case ready
        case needsInstall
        case working(step: String, progress: Double?)
        case failed(String)
    }

    private(set) var state: State = .checking
    private let engine: OllamaEngine

    /// Модель по умолчанию: среднего размера, хорошо говорит по-русски.
    static let defaultModel = ProcessInfo.processInfo.environment["STEVE_DEFAULT_MODEL"] ?? "qwen3:4b"
    private static let binaryURL = URL(string: "https://github.com/ollama/ollama/releases/latest/download/ollama-darwin.tgz")!

    init(engine: OllamaEngine) { self.engine = engine }

    var hint: String {
        switch state {
        case .checking: return "Проверяю, есть ли языковая модель"
        case .ready: return "Модель установлена, Стив отвечает на любые темы без интернета"
        case .needsInstall: return "Нужно один раз скачать помощника и модель (около 2,7 ГБ). Дальше всё работает без сети"
        case .working(let step, _): return step
        case .failed(let message): return message
        }
    }

    func refresh() async {
        if case .working = state { return }
        state = await engine.hasUsableModel() ? .ready : .needsInstall
    }

    /// Ставит всё, чего не хватает: сначала Ollama, потом модель.
    func install() async {
        if case .working = state { return }
        do {
            if !engine.isInstalled {
                state = .working(step: "Скачиваю Ollama (около 190 МБ)…", progress: 0)
                try await downloadBinary()
            }
            state = .working(step: "Запускаю Ollama…", progress: nil)
            guard await engine.ensureServer() else { throw SetupError.serverDidNotStart }
            if await engine.pickModel() == nil {
                state = .working(step: "Скачиваю модель \(Self.defaultModel)…", progress: 0)
                try await pullModel()
            }
            engine.forgetChosenModel()
            await refresh()
        } catch {
            state = .failed("Не получилось: \(error.localizedDescription). Проверьте интернет и нажмите «Повторить»")
        }
    }

    enum SetupError: LocalizedError {
        case serverDidNotStart, noBinaryInArchive, extractionFailed
        var errorDescription: String? {
            switch self {
            case .serverDidNotStart: return "Ollama не запустилась"
            case .noBinaryInArchive: return "в архиве Ollama не нашлось программы"
            case .extractionFailed: return "не удалось распаковать Ollama"
            }
        }
    }

    // MARK: - Ollama

    func downloadBinary(into target: URL? = nil) async throws {
        let folder = target ?? OllamaEngine.ownDirectory
        let archive = try await Downloader().download(Self.binaryURL) { [weak self] fraction in
            Task { @MainActor in self?.state = .working(step: "Скачиваю Ollama (около 190 МБ)…", progress: fraction) }
        }
        defer { try? FileManager.default.removeItem(at: archive) }

        state = .working(step: "Распаковываю Ollama…", progress: nil)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let result = await ProcessRunner.run("/usr/bin/tar", ["-xzf", archive.path, "-C", folder.path], timeout: 180)
        guard result.status == 0 else { throw SetupError.extractionFailed }

        // программа может лежать в корне архива или глубже
        let paths = (try? FileManager.default.subpathsOfDirectory(atPath: folder.path)) ?? []
        var found: URL?
        for path in paths where (path as NSString).lastPathComponent == "ollama" {
            var isDirectory: ObjCBool = false
            let url = folder.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                found = url
                break
            }
        }
        guard let binary = found else { throw SetupError.noBinaryInArchive }
        let target = folder.appendingPathComponent("ollama")
        if binary != target { try? FileManager.default.removeItem(at: target); try FileManager.default.moveItem(at: binary, to: target) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        _ = await ProcessRunner.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", folder.path], timeout: 20)
    }

    // MARK: - Модель

    func pullModel(_ requested: String? = nil) async throws {
        let name = requested ?? Self.defaultModel
        var request = URLRequest(url: engine.base.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.timeoutInterval = 3600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "stream": true])
        let (bytes, _) = try await URLSession.shared.bytes(for: request)
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let error = json["error"] as? String { throw NSError(domain: "Ollama", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
            let total = (json["total"] as? Double) ?? 0
            let completed = (json["completed"] as? Double) ?? 0
            let status = (json["status"] as? String) ?? ""
            let fraction: Double? = total > 0 ? completed / total : nil
            let step = status.hasPrefix("pulling") ? "Скачиваю модель \(name)…" : "Модель: \(status)…"
            state = .working(step: step, progress: fraction)
        }
    }
}

extension OllamaEngine {
    /// Есть ли программа, сервер и хотя бы одна подходящая модель.
    func hasUsableModel() async -> Bool {
        guard isInstalled, await ensureServer() else { return false }
        return await pickModel() != nil
    }
}

/// Скачивание файла с показом доли загруженного.
private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private var progress: (@Sendable (Double) -> Void)?
    private var session: URLSession?

    func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        self.progress = progress
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // файл исчезает после выхода из метода: переносим его сразу
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("steve-ollama-\(UUID().uuidString).tgz")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            continuation?.resume(returning: kept)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, let pending = continuation {
            pending.resume(throwing: error)
            continuation = nil
        }
    }
}
