import XCTest
@testable import SteveCore

final class CommandParserTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)
    private var parser: CommandParser!

    override func setUp() {
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        // воскресенье, 15 ноября 2026, 17:50
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 17, minute: 50))!
        parser = CommandParser(calendar: calendar, now: { now })
    }

    private func date(_ day: Int, _ month: Int, _ hour: Int, _ minute: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: таймер и секундомер

    func testTimerInMinutes() {
        XCTAssertEqual(parser.parse("Поставь таймер на 10 минут"), .timer(seconds: 600))
        XCTAssertEqual(parser.parse("таймер на пять минут"), .timer(seconds: 300))
        XCTAssertEqual(parser.parse("set a timer for 3 minutes"), .timer(seconds: 180))
    }

    func testTimerOtherUnits() {
        XCTAssertEqual(parser.parse("таймер на 30 секунд"), .timer(seconds: 30))
        XCTAssertEqual(parser.parse("таймер на полчаса"), .timer(seconds: 1800))
        XCTAssertEqual(parser.parse("таймер на 2 часа"), .timer(seconds: 7200))
    }

    func testTimerWithoutDurationDefaultsToFiveMinutes() {
        XCTAssertEqual(parser.parse("поставь таймер"), .timer(seconds: 300))
    }

    func testStopwatch() {
        XCTAssertEqual(parser.parse("запусти секундомер"), .startStopwatch)
        XCTAssertEqual(parser.parse("останови секундомер"), .stopStopwatch)
    }

    // MARK: календарь

    func testEventFromTheUserExample() {
        let command = parser.parse("23 ноября с 17:00 до 19:00 поставь событие зал")
        XCTAssertEqual(command, .createEvent(title: "Зал", start: date(23, 11, 17), end: date(23, 11, 19)))
    }

    func testEventWithShortHours() {
        let command = parser.parse("Добавь в календарь 23 ноября с 17 до 19 событие Зал")
        XCTAssertEqual(command, .createEvent(title: "Зал", start: date(23, 11, 17), end: date(23, 11, 19)))
    }

    func testEventTomorrowAtTimeLastsOneHour() {
        let command = parser.parse("завтра в 15:30 встреча с Олегом")
        XCTAssertEqual(command, .createEvent(title: "С олегом", start: date(16, 11, 15, 30), end: date(16, 11, 16, 30)))
    }

    func testEventDateInThePastMovesToNextYear() {
        guard case let .createEvent(_, start, _) = parser.parse("5 ноября с 10 до 11 событие Врач") else {
            return XCTFail("ожидали событие")
        }
        XCTAssertEqual(start, date(5, 11, 10, year: 2027))
    }

    func testEventOnWeekday() {
        // сегодня воскресенье, ближайший понедельник — 16 ноября
        guard case let .createEvent(title, start, _) = parser.parse("в понедельник в 9 событие планёрка") else {
            return XCTFail("ожидали событие")
        }
        XCTAssertEqual(title, "Планерка")
        XCTAssertEqual(start, date(16, 11, 9))
    }

    // MARK: заметки, приложения, громкость

    func testNoteKeepsOriginalCase() {
        XCTAssertEqual(parser.parse("Запиши заметку: купить Молоко"), .createNote("купить Молоко"))
        XCTAssertEqual(parser.parse("создай заметку позвонить маме"), .createNote("позвонить маме"))
    }

    func testOpenApp() {
        XCTAssertEqual(parser.parse("Открой Safari"), .openApp("Safari"))
        XCTAssertEqual(parser.parse("открой заметки"), .openApp("Notes"))
        XCTAssertEqual(parser.parse("запусти телеграм"), .openApp("Telegram"))
        XCTAssertEqual(parser.parse("открой Xcode"), .openApp("Xcode"))
    }

    func testVolume() {
        XCTAssertEqual(parser.parse("Громкость 30%"), .setVolume(percent: 30))
        XCTAssertEqual(parser.parse("сделай громкость на 50 процентов"), .setVolume(percent: 50))
        XCTAssertEqual(parser.parse("сделай потише"), .changeVolume(delta: -20))
        XCTAssertEqual(parser.parse("выключи звук"), .setVolume(percent: 0))
    }

    // MARK: разговор

    func testSystemQuestions() {
        XCTAssertEqual(parser.parse("сколько сейчас времени"), .currentTime)
        XCTAssertEqual(parser.parse("сколько заряда"), .battery)
    }

    func testTimerStatusAndCancel() {
        XCTAssertEqual(CommandParser().parse("Сколько до конца таймера"), .timerStatus)
        XCTAssertEqual(CommandParser().parse("отмени таймер"), .cancelTimers)
        XCTAssertEqual(CommandParser().parse("таймер на 10 минут"), .timer(seconds: 600))
    }

    func testUndo() {
        let parser = CommandParser()
        for phrase in ["отмени", "Откати", "верни как было", "отмени последнюю команду", "верни назад", "сделай обратно"] {
            XCTAssertEqual(parser.parse(phrase), .undo, phrase)
        }
        XCTAssertEqual(parser.parse("отмени таймер"), .cancelTimers)
    }

    func testStopwatchLap() {
        let parser = CommandParser()
        XCTAssertEqual(parser.parse("засеки круг"), .lapStopwatch)
        XCTAssertEqual(parser.parse("новый круг на секундомере"), .lapStopwatch)
        XCTAssertEqual(parser.parse("запусти секундомер"), .startStopwatch)
    }

    func testDesktopCommands() {
        let parser = CommandParser()
        XCTAssertEqual(parser.parse("Создай папку Привет Стив с файлом привет.txt: Привет, я Стив, твой помощник"),
                       .createFolder(name: "Привет Стив", fileName: "привет.txt", fileText: "Привет, я Стив, твой помощник"))
        XCTAssertEqual(parser.parse("создай папку Работа"), .createFolder(name: "Работа", fileName: nil, fileText: nil))
        XCTAssertEqual(parser.parse("создай файл список.txt с текстом молоко и хлеб"), .createFile(name: "список.txt", text: "молоко и хлеб", folder: nil))
        XCTAssertEqual(parser.parse("перемести файл список в папку Работа"), .moveItem(name: "список", toFolder: "Работа"))
        XCTAssertEqual(parser.parse("переименуй Работа в Учёба"), .renameItem(name: "Работа", newName: "Учёба"))
        XCTAssertEqual(parser.parse("что на рабочем столе"), .listDesktop)
        XCTAssertEqual(parser.parse("Перенести файл ДЗ ЭУ-163622 (для проверки).pdf в папку УрФУ"),
                       .moveItem(name: "ДЗ ЭУ-163622 (для проверки).pdf", toFolder: "УрФУ"))
    }

    func testNoteWithFillerWords() {
        XCTAssertEqual(CommandParser().parse("Напиши-ка мне новую заметку про создание сайта"), .createNote("про создание сайта"))
        XCTAssertEqual(CommandParser().parse("я хочу чтобы ты создал заметку"), .createNote("Заметка"))
    }

    func testGreetingAndThanks() {
        XCTAssertEqual(parser.parse("привет, как дела"), .greeting)
        XCTAssertEqual(parser.parse("Привет Стив"), .greeting)
        XCTAssertEqual(parser.parse("привет стив подскажи какая погода сейчас в москве"), .unknown("подскажи какая погода сейчас в москве"))
        XCTAssertEqual(parser.parse("привет стив сколько времени"), .currentTime)
        XCTAssertEqual(parser.parse("спасибо"), .thanks)
        XCTAssertEqual(parser.parse("молодец"), .thanks)
    }

    func testUnknown() {
        XCTAssertEqual(parser.parse("расскажи про динозавров"), .unknown("расскажи про динозавров"))
    }

    func testJoyWordsOnlyMatchTriggers() {
        XCTAssertTrue(JoyWords.matches("Спасибо тебе"))
        XCTAssertTrue(JoyWords.matches("ты молодец"))
        XCTAssertFalse(JoyWords.matches("поставь таймер"))
        XCTAssertFalse(JoyWords.matches("сколько времени"))
    }
}
