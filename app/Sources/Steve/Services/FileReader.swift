import AppKit
import Foundation
import PDFKit
import Speech
import Vision

/// Что Стив понял про файл: короткое описание для ответа и текст для языковой модели.
struct FileDigest: Equatable {
    var name: String
    var kind: String
    /// Одна строка про файл: тип, размер, страницы.
    var summary: String
    /// Текст из файла (или распознанный с картинки и из записи), обрезанный до разумной длины.
    var text: String?
}

/// Читает прикреплённые файлы: текст, PDF, Word, Excel, картинки (распознавание текста), аудио и видео (распознавание речи).
/// Всё делается на этом Маке, без интернета.
enum FileReader {
    static let limit = 8000

    static func read(_ url: URL) async -> FileDigest {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
        let sizeText = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            let list = items.filter { !$0.hasPrefix(".") }.sorted()
            return FileDigest(name: name, kind: "папка", summary: "папка, внутри \(list.count)", text: list.prefix(60).joined(separator: "\n"))
        }

        switch ext {
        case "pdf":
            guard let document = PDFDocument(url: url) else { return plain(name, "PDF", sizeText) }
            let text = cut(document.string)
            return FileDigest(name: name, kind: "PDF", summary: "PDF, \(document.pageCount) стр., \(sizeText)" + (text == nil ? ", текста нет (возможно, скан)" : ""), text: text)
        case "docx":
            let text = cut(await office(url, part: "word/document.xml", paragraph: "</w:p>"))
            return FileDigest(name: name, kind: "Word", summary: "документ Word, \(sizeText)", text: text)
        case "xlsx":
            let text = cut(await office(url, part: "xl/sharedStrings.xml", paragraph: "</si>"))
            return FileDigest(name: name, kind: "Excel", summary: "таблица Excel, \(sizeText)", text: text)
        case "png", "jpg", "jpeg", "heic", "gif", "tiff", "bmp", "webp":
            let text = cut(await recognizeText(in: url))
            let pixels = NSImage(contentsOf: url).map { " \(Int($0.size.width))×\(Int($0.size.height))" } ?? ""
            return FileDigest(name: name, kind: "картинка", summary: "картинка\(pixels), \(sizeText)" + (text == nil ? ", текста на ней нет" : ""), text: text)
        case "mp3", "m4a", "wav", "aiff", "caf", "ogg", "opus", "mp4", "mov", "m4v":
            let text = cut(await transcribe(url))
            let video = ["mp4", "mov", "m4v"].contains(ext)
            return FileDigest(name: name, kind: video ? "видео" : "аудио", summary: (video ? "видео" : "аудио") + ", \(sizeText)" + (text == nil ? ", речь не распознана" : ""), text: text)
        default:
            if let text = cut(readText(url)) {
                return FileDigest(name: name, kind: "текст", summary: "текстовый файл, \(sizeText)", text: text)
            }
            return plain(name, ext.isEmpty ? "файл" : ext.uppercased(), sizeText)
        }
    }

    // MARK: - Разбор

    private static func plain(_ name: String, _ kind: String, _ size: String) -> FileDigest {
        FileDigest(name: name, kind: kind, summary: "\(kind), \(size). Содержимое я прочитать не умею", text: nil)
    }

    private static func cut(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
    }

    private static func readText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count < 5_000_000, !data.prefix(2048).contains(0) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251)
    }

    /// Word и Excel это архивы с XML: достаём нужную часть и убираем теги.
    private static func office(_ url: URL, part: String, paragraph: String) async -> String? {
        let result = await ProcessRunner.run("/usr/bin/unzip", ["-p", url.path, part], timeout: 30)
        guard result.status == 0 else { return nil }
        let xml = result.output.replacingOccurrences(of: paragraph, with: "\n")
        return xml.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }

    /// Распознавание текста на картинке (русский и английский).
    private static func recognizeText(in url: URL) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["ru-RU", "en-US"]
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(url: url)
                try? handler.perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.isEmpty ? nil : lines.joined(separator: "\n"))
            }
        }
    }

    /// Распознавание речи из записи на устройстве. Ждём не дольше двух минут.
    private static func transcribe(_ url: URL) async -> String? {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU")), recognizer.isAvailable else { return nil }
        return await withCheckedContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            let state = ResumeOnce(continuation)
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal { state.finish(result.bestTranscription.formattedString) }
                else if error != nil { state.finish(nil) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 120) { task.cancel(); state.finish(nil) }
        }
    }

    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String?, Never>?
        init(_ continuation: CheckedContinuation<String?, Never>) { self.continuation = continuation }
        func finish(_ value: String?) {
            lock.lock(); defer { lock.unlock() }
            continuation?.resume(returning: value)
            continuation = nil
        }
    }
}
