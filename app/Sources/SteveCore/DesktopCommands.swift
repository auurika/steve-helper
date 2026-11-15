import Foundation

/// Команды для рабочего стола: папки, файлы, перемещение и переименование.
/// Имена берутся из исходной фразы, чтобы сохранить заглавные буквы.
enum DesktopParser {
    static func parse(original: String, text: String) -> Command? {
        if let command = attached(original: original) { return command }
        if let command = createFolder(original: original, text: text) { return command }
        if let command = createFile(original: original, text: text) { return command }
        if let command = move(original: original) { return command }
        if let command = rename(original: original) { return command }
        if text.range(of: "что (лежит |есть )?на рабочем столе|покажи рабочий стол|список файлов", options: .regularExpression) != nil {
            return .listDesktop
        }
        return nil
    }

    // MARK: - Прикреплённые файлы

    /// «Положи их в папку Работа», «закинь в папку Работа», «скопируй файлы в Документы».
    private static func attached(original: String) -> Command? {
        let pattern = "^(перемести(?:ть)?|перенес(?:и|ти)|положи(?:ть)?|закинь|закинуть|кинь|сложи|скопируй|скопировать)\\s+(?:(?:их|его|это|эти|все|вложения|прикрепленные|прикреплённые)\\s+)*(?:файл\\w*\\s+)?(?:в|на)\\s+(?:папку\\s+)?(.+)$"
        guard let match = groups(pattern, in: original), match.count == 2 else { return nil }
        let folder = clean(match[1])
        guard !folder.isEmpty else { return nil }
        return .moveAttached(folder: folder, copy: match[0].lowercased().hasPrefix("скопир"))
    }

    // MARK: - Папка (и файл внутри)

    private static func createFolder(original: String, text: String) -> Command? {
        guard text.range(of: "(создай|создать|сделай|добавь|новая|новую)\\s+(\\S+\\s+){0,2}?папк", options: .regularExpression) != nil,
              let folderWord = original.range(of: "папк\\w*", options: [.regularExpression, .caseInsensitive]) else { return nil }
        let rest = String(original[folderWord.upperBound...])

        // «… с файлом имя.txt: текст» или «… и файл …»
        let splitter = "\\s+(?:с|и)\\s+(?:текстовым\\s+)?файл\\w*\\s*"
        guard let split = rest.range(of: splitter, options: [.regularExpression, .caseInsensitive]) else {
            let name = clean(rest)
            return name.isEmpty ? nil : .createFolder(name: name, fileName: nil, fileText: nil)
        }
        let folderName = clean(String(rest[..<split.lowerBound]))
        let filePart = String(rest[split.upperBound...])
        let (fileName, fileText) = fileAndText(filePart)
        return folderName.isEmpty ? nil : .createFolder(name: folderName, fileName: fileName, fileText: fileText)
    }

    // MARK: - Файл

    private static func createFile(original: String, text: String) -> Command? {
        guard text.range(of: "(создай|создать|сделай|добавь|новый)\\s+(\\S+\\s+){0,2}?файл", options: .regularExpression) != nil,
              let word = original.range(of: "файл\\w*", options: [.regularExpression, .caseInsensitive]) else { return nil }
        var rest = String(original[word.upperBound...])
        var folder: String?
        // «… в папке X»
        if let inFolder = rest.range(of: "\\s+в\\s+папк\\w*\\s+", options: [.regularExpression, .caseInsensitive]) {
            folder = clean(String(rest[inFolder.upperBound...]))
            rest = String(rest[..<inFolder.lowerBound])
        }
        let (name, body) = fileAndText(rest)
        return .createFile(name: name ?? "Новый файл.txt", text: body ?? "", folder: folder)
    }

    // MARK: - Перемещение и переименование

    private static func move(original: String) -> Command? {
        let pattern = "(?:перемести(?:ть)?|перенес(?:и|ти)|переложи(?:ть)?|положи(?:ть)?)\\s+(?:файл\\s+|папку\\s+)?(.+?)\\s+в\\s+(?:папку\\s+)?(.+)"
        guard let match = groups(pattern, in: original), match.count == 2 else { return nil }
        let item = clean(match[0]), folder = clean(match[1])
        return item.isEmpty || folder.isEmpty ? nil : .moveItem(name: item, toFolder: folder)
    }

    private static func rename(original: String) -> Command? {
        let pattern = "(?:переименуй(?:те)?|переименовать)\\s+(?:файл\\s+|папку\\s+)?(.+?)\\s+в\\s+(.+)"
        guard let match = groups(pattern, in: original), match.count == 2 else { return nil }
        let old = clean(match[0]), new = clean(match[1])
        return old.isEmpty || new.isEmpty ? nil : .renameItem(name: old, newName: new)
    }

    // MARK: - Разбор

    /// Имя файла и его текст: «привет.txt: Привет», «привет.txt Привет», «с текстом Привет».
    private static func fileAndText(_ part: String) -> (String?, String?) {
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }
        var body: String?
        var head = trimmed
        if let colon = trimmed.firstIndex(of: ":") {
            head = String(trimmed[..<colon])
            body = clean(String(trimmed[trimmed.index(after: colon)...]), keepInner: true)
        } else if let withText = trimmed.range(of: "\\s+с\\s+текстом\\s+", options: [.regularExpression, .caseInsensitive]) {
            head = String(trimmed[..<withText.lowerBound])
            body = clean(String(trimmed[withText.upperBound...]), keepInner: true)
        } else if let space = trimmed.range(of: "\\.\\w{1,4}\\s+", options: .regularExpression) {
            // «имя.txt текст»
            head = String(trimmed[..<space.lowerBound]) + String(trimmed[space.lowerBound..<space.upperBound]).trimmingCharacters(in: .whitespaces)
            body = clean(String(trimmed[space.upperBound...]), keepInner: true)
        }
        var name = clean(head)
        if !name.isEmpty, !name.contains(".") { name += ".txt" }
        return (name.isEmpty ? nil : name, body)
    }

    /// Убирает кавычки, лишние знаки по краям и символы, недопустимые в именах (если это не текст файла).
    private static func clean(_ value: String, keepInner: Bool = false) -> String {
        var result = value.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t.,:;!?«»\"'“”"))
        if !keepInner { result = result.replacingOccurrences(of: "[/:\\\\]", with: " ", options: .regularExpression) }
        return String(result.prefix(keepInner ? 2000 : 80)).trimmingCharacters(in: .whitespaces)
    }

    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }
}
