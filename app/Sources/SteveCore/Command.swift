import Foundation

/// То, что Стив понял из сказанного. Выполняет команды уже приложение (см. Tools.swift).
public enum Command: Equatable {
    case openApp(String)
    case timer(seconds: Int)
    case timerStatus
    case cancelTimers
    case startStopwatch
    case stopStopwatch
    case lapStopwatch
    /// «Отмени секундомер»: убрать его без итога.
    case cancelStopwatch
    case createNote(String)
    case createEvent(title: String, start: Date, end: Date)
    case setVolume(percent: Int)
    case changeVolume(delta: Int)
    case currentTime
    case battery
    /// Папка на рабочем столе; при желании сразу с текстовым файлом внутри.
    case createFolder(name: String, fileName: String?, fileText: String?)
    case createFile(name: String, text: String, folder: String?)
    case moveItem(name: String, toFolder: String)
    case renameItem(name: String, newName: String)
    /// Прикреплённые к чату файлы: переложить (или скопировать) в папку.
    case moveAttached(folder: String, copy: Bool)
    /// «Открой файл»: открыть прикреплённые файлы в программе по умолчанию.
    case openAttached
    /// «Покажи в папке»: показать прикреплённые файлы в Finder.
    case revealAttached
    case listDesktop
    /// «Отмени», «откати», «верни как было»: обратить последнее действие.
    case undo
    case greeting
    case thanks
    case unknown(String)
}

/// Слова, на которые Стив радуется. Только на них, больше ни на что.
public enum JoyWords {
    private static let pattern = "спасибо|благодар|пожалуйста|молодец|умница|умничка|супер|отлично|круто|классно|thank|good job|well done"

    public static func matches(_ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
