import AppKit
import Foundation

/// Работа с рабочим столом: Стив создаёт папки и файлы, перекладывает и переименовывает их, как это сделал бы человек в Finder.
/// После каждого действия показывает результат в Finder, чтобы было видно, что произошло.
extension Tools {
    private var desktopURL: URL? { FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first }

    func createFolder(name: String, fileName: String?, fileText: String?) -> ToolResult {
        let tool = "Desktop.create_folder(name=\"\(name)\"" + (fileName.map { ", file=\"\($0)\"" } ?? "") + ")"
        guard let desktop = desktopURL else { return ToolResult(reply: "Не нашёл рабочий стол", tool: tool) }
        do {
            let folder = desktop.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            let existed = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue
            if !existed { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
            Permissions.desktopRemembered = true
            var reveal = folder
            var createdFile: URL?
            var reply = existed ? "Папка «\(name)» уже есть на рабочем столе" : "Создал папку «\(name)» на рабочем столе"
            if let fileName {
                let file = try write(text: fileText ?? "", named: fileName, in: folder)
                reveal = file
                createdFile = file
                reply += existed ? ", добавил в неё файл «\(file.lastPathComponent)»" : " и файл «\(file.lastPathComponent)» в ней"
            }
            NSWorkspace.shared.activateFileViewerSelecting([reveal])
            // «отмени»: в корзину уходит то, что создал Стив (папка вместе с файлом, а если папка уже была, то только файл)
            let created = existed ? createdFile : folder
            if let created { pushUndo("create_folder") { Self.trash(created, "Убрал «\(created.lastPathComponent)» в корзину") } }
            return ToolResult(reply: reply, tool: tool)
        } catch {
            return ToolResult(reply: Self.desktopFailure(error, action: "создать папку"), tool: tool)
        }
    }

    func createFile(name: String, text: String, folder: String?) -> ToolResult {
        let tool = "Desktop.create_file(name=\"\(name)\"" + (folder.map { ", folder=\"\($0)\"" } ?? "") + ")"
        guard let desktop = desktopURL else { return ToolResult(reply: "Не нашёл рабочий стол", tool: tool) }
        do {
            var directory = desktop
            if let folder {
                guard let found = find(folder, in: desktop, foldersOnly: true) else {
                    return ToolResult(reply: "Не нашёл папку «\(folder)» на рабочем столе", tool: tool)
                }
                directory = found
            }
            let file = try write(text: text, named: name, in: directory)
            Permissions.desktopRemembered = true
            NSWorkspace.shared.activateFileViewerSelecting([file])
            pushUndo("create_file") { Self.trash(file, "Убрал файл «\(file.lastPathComponent)» в корзину") }
            return ToolResult(reply: "Создал файл «\(file.lastPathComponent)»" + (folder == nil ? " на рабочем столе" : " в папке «\(directory.lastPathComponent)»"), tool: tool)
        } catch {
            return ToolResult(reply: Self.desktopFailure(error, action: "создать файл"), tool: tool)
        }
    }

    func moveItem(name: String, toFolder: String) -> ToolResult {
        let tool = "Desktop.move(name=\"\(name)\", to=\"\(toFolder)\")"
        guard let desktop = desktopURL else { return ToolResult(reply: "Не нашёл рабочий стол", tool: tool) }
        guard let item = find(name, in: desktop, foldersOnly: false) else {
            return ToolResult(reply: "Не нашёл «\(name)» на рабочем столе", tool: tool)
        }
        guard let folder = find(toFolder, in: desktop, foldersOnly: true) else {
            return ToolResult(reply: "Не нашёл папку «\(toFolder)» на рабочем столе", tool: tool)
        }
        guard item != folder else { return ToolResult(reply: "Папку нельзя переложить в саму себя", tool: tool) }
        do {
            let target = uniqueURL(folder.appendingPathComponent(item.lastPathComponent))
            try FileManager.default.moveItem(at: item, to: target)
            Permissions.desktopRemembered = true
            NSWorkspace.shared.activateFileViewerSelecting([target])
            pushUndo("move") { Self.moveBack(from: target, to: item, "Вернул «\(item.lastPathComponent)» на прежнее место") }
            return ToolResult(reply: "Переложил «\(item.lastPathComponent)» в папку «\(folder.lastPathComponent)»", tool: tool)
        } catch {
            return ToolResult(reply: Self.desktopFailure(error, action: "переместить"), tool: tool)
        }
    }

    func renameItem(name: String, newName: String) -> ToolResult {
        let tool = "Desktop.rename(name=\"\(name)\", to=\"\(newName)\")"
        guard let desktop = desktopURL else { return ToolResult(reply: "Не нашёл рабочий стол", tool: tool) }
        guard let item = find(name, in: desktop, foldersOnly: false) else {
            return ToolResult(reply: "Не нашёл «\(name)» на рабочем столе", tool: tool)
        }
        do {
            // у файла расширение остаётся прежним, если в новом имени его нет
            var finalName = newName
            if item.pathExtension.isEmpty == false, (newName as NSString).pathExtension.isEmpty { finalName += "." + item.pathExtension }
            let target = uniqueURL(desktop.appendingPathComponent(finalName))
            try FileManager.default.moveItem(at: item, to: target)
            Permissions.desktopRemembered = true
            NSWorkspace.shared.activateFileViewerSelecting([target])
            pushUndo("rename") { Self.moveBack(from: target, to: item, "Вернул имя «\(item.lastPathComponent)»") }
            return ToolResult(reply: "Переименовал «\(item.lastPathComponent)» в «\(target.lastPathComponent)»", tool: tool)
        } catch {
            return ToolResult(reply: Self.desktopFailure(error, action: "переименовать"), tool: tool)
        }
    }

    func listDesktop() -> ToolResult {
        let tool = "Desktop.list()"
        guard let desktop = desktopURL else { return ToolResult(reply: "Не нашёл рабочий стол", tool: tool) }
        do {
            let names = try FileManager.default.contentsOfDirectory(atPath: desktop.path).filter { !$0.hasPrefix(".") }.sorted()
            Permissions.desktopRemembered = true
            NSWorkspace.shared.open(desktop)
            if names.isEmpty { return ToolResult(reply: "На рабочем столе пусто", tool: tool) }
            let shown = names.prefix(8).map { "«\($0)»" }.joined(separator: ", ")
            return ToolResult(reply: "На рабочем столе \(names.count): \(shown)" + (names.count > 8 ? " и ещё \(names.count - 8)" : ""), tool: tool)
        } catch {
            return ToolResult(reply: Self.desktopFailure(error, action: "посмотреть рабочий стол"), tool: tool)
        }
    }

    // MARK: - Вспомогательное

    /// Отправляет созданное в корзину: так «отмени» ничего не стирает насовсем.
    private static func trash(_ url: URL, _ done: String) -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "«\(url.lastPathComponent)» уже нет на месте" }
        return (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil ? done : "Не получилось убрать «\(url.lastPathComponent)»"
    }

    /// Возвращает файл или папку на прежнее место и под прежним именем.
    private static func moveBack(from current: URL, to original: URL, _ done: String) -> String {
        guard FileManager.default.fileExists(atPath: current.path) else { return "«\(current.lastPathComponent)» уже не там, где я его оставил" }
        guard !FileManager.default.fileExists(atPath: original.path) else { return "Прежнее место занято, ничего не трогаю" }
        return (try? FileManager.default.moveItem(at: current, to: original)) != nil ? done : "Не получилось вернуть «\(current.lastPathComponent)»"
    }

    private func write(text: String, named name: String, in folder: URL) throws -> URL {
        let url = uniqueURL(folder.appendingPathComponent(name))
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Если такое имя занято, добавляет номер: «файл 2.txt».
    private func uniqueURL(_ url: URL) -> URL {
        var candidate = url
        var number = 2
        let base = url.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = url.pathExtension.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(url.pathExtension)"
            candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            number += 1
        }
        return candidate
    }

    /// Ищет файл или папку по имени без учёта регистра: точное совпадение, затем начало имени, затем часть.
    private func find(_ name: String, in directory: URL, foldersOnly: Bool) -> URL? {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        let candidates = urls.filter { url in
            guard !url.lastPathComponent.hasPrefix(".") else { return false }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return !foldersOnly || isDirectory
        }
        // имена сравниваем без регистра, пробелов и знаков: голосом дефис и скобки передаются неточно
        func key(_ text: String) -> String {
            text.lowercased().replacingOccurrences(of: "ё", with: "е").filter { $0.isLetter || $0.isNumber }
        }
        let target = key(name)
        guard !target.isEmpty else { return nil }
        func plain(_ url: URL) -> String { key(url.deletingPathExtension().lastPathComponent) }
        return candidates.first { key($0.lastPathComponent) == target || plain($0) == target }
            ?? candidates.first { key($0.lastPathComponent).hasPrefix(target) }
            ?? candidates.first { key($0.lastPathComponent).contains(target) }
    }

    private static func desktopFailure(_ error: Error, action: String) -> String {
        let code = (error as NSError).code
        if code == NSFileReadNoPermissionError || code == NSFileWriteNoPermissionError {
            Permissions.desktopRemembered = false
            return "Нет доступа к рабочему столу, поэтому не смог \(action). Разреши его в Настройках → Разрешения"
        }
        return "Не получилось \(action): \(error.localizedDescription)"
    }
}
