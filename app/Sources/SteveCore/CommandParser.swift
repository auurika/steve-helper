import Foundation

/// Превращает фразу на русском или английском в команду. Работает без интернета и без модели.
public struct CommandParser {
    private let calendar: Calendar
    private let now: () -> Date

    public init(calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.calendar = calendar
        self.now = now
    }

    public func parse(_ rawText: String) -> Command {
        let text = Self.normalize(rawText)

        if text.contains("секундомер") || text.contains("stopwatch") {
            let stops = ["останов", "стоп", "выключ", "сброс", "stop"].contains { text.contains($0) }
            return stops ? .stopStopwatch : .startStopwatch
        }
        if text.contains("таймер") || text.contains("timer") || text.hasPrefix("засеки") {
            return .timer(seconds: Self.duration(in: text) ?? 300)
        }
        if let volume = volumeCommand(in: text) {
            return volume
        }
        if let event = eventCommand(in: text, original: rawText) {
            return event
        }
        if let note = noteCommand(in: text, original: rawText) {
            return note
        }
        if text.contains("батаре") || text.contains("заряд") || text.contains("battery") {
            return .battery
        }
        if text.range(of: "сколько (сейчас )?времени|который час|what time", options: .regularExpression) != nil {
            return .currentTime
        }
        if let app = openAppCommand(in: text) {
            return app
        }
        if let greeting = text.range(of: "^(привет|здарова|здравствуй|добрый (день|вечер|утро)|hello|hi)\\b[,!. ]*(стив\\b[,!. ]*)?", options: .regularExpression) {
            // «привет» с продолжением это обращение, а не приветствие: отвечаем на сам вопрос
            let rest = String(text[greeting.upperBound...]).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty || rest.range(of: "^(как (дела|ты|жизнь)|что нового|ты (тут|здесь))\\??$", options: .regularExpression) != nil {
                return .greeting
            }
            let original = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedOriginal = original.split(separator: " ", omittingEmptySubsequences: true)
                .drop { word in
                    let w = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                    return ["привет", "здарова", "здравствуй", "hello", "hi", "стив"].contains(w)
                }.joined(separator: " ")
            let command = parse(rest)
            if case .unknown = command { return .unknown(trimmedOriginal.isEmpty ? original : trimmedOriginal) }
            return command
        }
        if JoyWords.matches(text) {
            return .thanks
        }
        return .unknown(rawText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Громкость

    private func volumeCommand(in text: String) -> Command? {
        guard text.range(of: "громк|тише|громче|звук|volume", options: .regularExpression) != nil else { return nil }
        if let percent = Self.firstInt(in: text, pattern: "(\\d{1,3})\\s*(%|процент)") {
            return .setVolume(percent: min(100, percent))
        }
        if text.contains("выключи звук") || text.contains("без звука") || text.contains("mute") {
            return .setVolume(percent: 0)
        }
        if text.contains("максимум") || text.contains("на полную") {
            return .setVolume(percent: 100)
        }
        if text.contains("тише") { return .changeVolume(delta: -20) }
        if text.contains("громче") { return .changeVolume(delta: 20) }
        return nil
    }

    // MARK: - Заметки

    private func noteCommand(in text: String, original: String) -> Command? {
        guard text.range(of: "(запиши|записать|создай|добавь|новая|сделай)\\s+(заметк|note)|^запиши\\b|^note\\b", options: .regularExpression) != nil else {
            return nil
        }
        // Текст заметки: всё после двоеточия или после слова «заметка», в исходном регистре
        let body: String
        if let colon = original.firstIndex(of: ":") {
            body = String(original[original.index(after: colon)...])
        } else if let range = text.range(of: "заметк\\w*|note", options: .regularExpression) {
            let offset = text.distance(from: text.startIndex, to: range.upperBound)
            body = String(original.dropFirst(min(offset, original.count)))
        } else {
            body = original.replacingOccurrences(of: "запиши", with: "", options: .caseInsensitive)
        }
        let cleaned = body.trimmingCharacters(in: CharacterSet(charactersIn: " :,.-—\n"))
        return .createNote(cleaned.isEmpty ? "Заметка" : cleaned)
    }

    // MARK: - Открыть приложение

    private static let appAliases: [String: String] = [
        "сафари": "Safari", "safari": "Safari", "браузер": "Safari",
        "заметки": "Notes", "заметка": "Notes", "notes": "Notes",
        "календарь": "Calendar", "calendar": "Calendar",
        "часы": "Clock", "clock": "Clock",
        "почта": "Mail", "почту": "Mail", "mail": "Mail",
        "музыка": "Music", "музыку": "Music", "music": "Music",
        "сообщения": "Messages", "messages": "Messages",
        "фото": "Photos", "photos": "Photos",
        "настройки": "System Settings", "settings": "System Settings",
        "терминал": "Terminal", "terminal": "Terminal",
        "финдер": "Finder", "finder": "Finder",
        "телеграм": "Telegram", "telegram": "Telegram",
        "карты": "Maps", "maps": "Maps",
        "калькулятор": "Calculator", "calculator": "Calculator",
    ]

    private func openAppCommand(in text: String) -> Command? {
        guard let match = Self.groups(in: text, pattern: "(?:открой|открыть|запусти|запустить|включи|open|launch)\\s+(?:приложение\\s+)?(.+)$") else {
            return nil
        }
        let target = match[1].trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        let firstWord = target.split(separator: " ").first.map(String.init) ?? target
        if let name = Self.appAliases[target] ?? Self.appAliases[firstWord] {
            return .openApp(name)
        }
        return .openApp(target.capitalized)
    }

    // MARK: - События календаря

    private static let months = [
        "января": 1, "февраля": 2, "марта": 3, "апреля": 4, "мая": 5, "июня": 6,
        "июля": 7, "августа": 8, "сентября": 9, "октября": 10, "ноября": 11, "декабря": 12,
    ]
    // Calendar.weekday: воскресенье = 1
    private static let weekdays = [
        "воскресенье": 1, "понедельник": 2, "вторник": 3, "среду": 4, "среда": 4,
        "четверг": 5, "пятницу": 6, "пятница": 6, "субботу": 7, "суббота": 7,
    ]

    private func eventCommand(in text: String, original: String) -> Command? {
        let hasEventWord = text.range(of: "событи|встреч|календар|запланир|мероприяти", options: .regularExpression) != nil
        let hasRange = Self.groups(in: text, pattern: "с\\s*\\d{1,2}([:.]\\d{2})?\\s*(до|по)\\s*\\d{1,2}") != nil
        let hasMonthDate = Self.groups(in: text, pattern: "\\d{1,2}\\s+(" + Self.months.keys.joined(separator: "|") + ")") != nil
        guard hasEventWord || (hasRange && hasMonthDate) else { return nil }

        var working = text
        let day = extractDate(from: &working)
        let times = extractTimes(from: &working)

        let today = calendar.startOfDay(for: now())
        let baseDay = day ?? (times.map { time -> Date in
            // без даты: сегодня, если время ещё не прошло, иначе завтра
            let candidate = calendar.date(bySettingHour: time.startHour, minute: time.startMinute, second: 0, of: today) ?? today
            return candidate > now() ? today : (calendar.date(byAdding: .day, value: 1, to: today) ?? today)
        } ?? today)

        let start: Date
        let end: Date
        if let time = times {
            start = calendar.date(bySettingHour: time.startHour, minute: time.startMinute, second: 0, of: baseDay) ?? baseDay
            end = time.endHour.flatMap { hour in
                calendar.date(bySettingHour: hour, minute: time.endMinute ?? 0, second: 0, of: baseDay)
            } ?? start.addingTimeInterval(3600)
        } else {
            // без времени: событие на весь день с 9 до 10
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: baseDay) ?? baseDay
            end = start.addingTimeInterval(3600)
        }

        return .createEvent(title: Self.eventTitle(from: working, original: original), start: start, end: max(end, start.addingTimeInterval(900)))
    }

    private struct TimeSpan {
        var startHour: Int
        var startMinute: Int
        var endHour: Int?
        var endMinute: Int?
    }

    /// Находит дату, вырезает её из строки и возвращает начало этого дня.
    private func extractDate(from text: inout String) -> Date? {
        let today = calendar.startOfDay(for: now())

        if let match = Self.groups(in: text, pattern: "(\\d{1,2})\\s+(" + Self.months.keys.joined(separator: "|") + ")"),
           let dayNumber = Int(match[1]), let month = Self.months[match[2]] {
            text = text.replacingOccurrences(of: match[0], with: " ")
            var components = calendar.dateComponents([.year], from: today)
            components.month = month
            components.day = dayNumber
            if let thisYear = calendar.date(from: components), thisYear >= today { return thisYear }
            components.year = (components.year ?? 0) + 1
            return calendar.date(from: components)
        }
        for (word, offset) in [("послезавтра", 2), ("завтра", 1), ("сегодня", 0)] where text.contains(word) {
            text = text.replacingOccurrences(of: word, with: " ")
            return calendar.date(byAdding: .day, value: offset, to: today)
        }
        for (word, weekday) in Self.weekdays {
            if let range = text.range(of: "(в|во)\\s+\(word)\\b", options: .regularExpression) {
                text.replaceSubrange(range, with: " ")
                let current = calendar.component(.weekday, from: today)
                let ahead = (weekday - current + 7) % 7
                return calendar.date(byAdding: .day, value: ahead == 0 ? 7 : ahead, to: today)
            }
        }
        return nil
    }

    private func extractTimes(from text: inout String) -> TimeSpan? {
        if let match = Self.groups(in: text, pattern: "с\\s*(\\d{1,2})(?:[:.](\\d{2}))?\\s*(?:до|по)\\s*(\\d{1,2})(?:[:.](\\d{2}))?"),
           let startHour = Int(match[1]), let endHour = Int(match[3]), startHour < 24, endHour < 24 {
            text = text.replacingOccurrences(of: match[0], with: " ")
            return TimeSpan(startHour: startHour, startMinute: Int(match[2]) ?? 0, endHour: endHour, endMinute: Int(match[4]) ?? 0)
        }
        if let match = Self.groups(in: text, pattern: "(?:в|на|к)\\s*(\\d{1,2})(?:[:.](\\d{2}))?(?!\\s*(?:мин|сек|час))"),
           let hour = Int(match[1]), hour < 24 {
            text = text.replacingOccurrences(of: match[0], with: " ")
            return TimeSpan(startHour: hour, startMinute: Int(match[2]) ?? 0, endHour: nil, endMinute: nil)
        }
        return nil
    }

    /// Название берём после слова «событие» или «встреча»; если его нет, то остаток фразы без служебных слов.
    private static func eventTitle(from working: String, original: String) -> String {
        let source = working.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        var title = source
        if let match = groups(in: source, pattern: "(?:событие|событии|встреча|встречу|мероприятие)\\s+(.+)$") {
            title = match[1]
        } else {
            let service = "поставь|поставить|добавь|добавить|создай|создать|запланируй|запиши|в календарь|календарь|на|в|пожалуйста|мне"
            title = source.replacingOccurrences(of: "\\b(\(service))\\b", with: " ", options: .regularExpression)
        }
        title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: " ,.:-—"))
        return title.isEmpty ? "Событие" : title.prefix(1).uppercased() + title.dropFirst()
    }

    // MARK: - Общие помощники

    /// Нижний регистр, «ё» как «е», лишние пробелы убраны.
    public static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let numberWords: [String: Int] = [
        "одну": 1, "один": 1, "две": 2, "два": 2, "три": 3, "четыре": 4, "пять": 5, "шесть": 6, "семь": 7,
        "восемь": 8, "девять": 9, "десять": 10, "пятнадцать": 15, "двадцать": 20, "тридцать": 30,
        "сорок": 40, "пятьдесят": 50, "шестьдесят": 60,
    ]

    /// Длительность в секундах из фраз вроде «10 минут», «пять минут», «полчаса», «час».
    public static func duration(in text: String) -> Int? {
        if text.contains("полчаса") { return 1800 }
        let unitPattern = "(сек\\w*|мин\\w*|час\\w*|sec\\w*|min\\w*|hour\\w*)"
        if let match = groups(in: text, pattern: "(\\d+)\\s*" + unitPattern), let value = Int(match[1]) {
            return value * seconds(forUnit: match[2])
        }
        for (word, value) in numberWords {
            if let match = groups(in: text, pattern: "\\b\(word)\\s+" + unitPattern) {
                return value * seconds(forUnit: match[1])
            }
        }
        if text.range(of: "на час\\b|1 час\\b", options: .regularExpression) != nil { return 3600 }
        return nil
    }

    private static func seconds(forUnit unit: String) -> Int {
        if unit.hasPrefix("сек") || unit.hasPrefix("sec") { return 1 }
        if unit.hasPrefix("мин") || unit.hasPrefix("min") { return 60 }
        return 3600
    }

    private static func firstInt(in text: String, pattern: String) -> Int? {
        groups(in: text, pattern: pattern).flatMap { Int($0[1]) }
    }

    /// Первое совпадение шаблона: [целиком, группа 1, группа 2...]. Пустая группа даёт пустую строку.
    static func groups(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}
