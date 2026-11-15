import AppKit
import EventKit
import SteveCore
import UserNotifications

/// Что получилось сделать: текст ответа и строка команды для показа в сообщении.
struct ToolResult {
    var reply: String
    var tool: String?
}

/// Выполняет команды в стандартных приложениях Mac: «Заметки», «Календарь», Safari и других.
@MainActor
final class Tools {
    /// Вызывается, когда сработал таймер. Озвучивает и показывает уведомление приложение.
    var onTimerFired: ((_ seconds: Int) -> Void)?

    private let eventStore = EKEventStore()
    private var timers: [UUID: Timer] = [:]
    /// Идущие таймеры: окно приложения показывает их с обратным отсчётом.
    private(set) var activeTimers: [ActiveTimer] = []
    var onTimersChanged: (() -> Void)?
    private var stopwatchStartedAt: Date?

    func execute(_ command: Command) async -> ToolResult {
        switch command {
        case .openApp(let name): return await openApp(name)
        case .timer(let seconds): return startTimer(seconds: seconds)
        case .timerStatus: return timerStatus()
        case .cancelTimers: return cancelTimers()
        case .startStopwatch: return startStopwatch()
        case .stopStopwatch: return stopStopwatch()
        case .createNote(let text): return await createNote(text)
        case .createEvent(let title, let start, let end): return await createEvent(title: title, start: start, end: end)
        case .setVolume(let percent): return await setVolume(percent)
        case .changeVolume(let delta): return await changeVolume(by: delta)
        case .currentTime: return currentTime()
        case .battery: return await battery()
        case .greeting: return ToolResult(reply: SmallTalk().greeting(), tool: nil)
        case .thanks: return ToolResult(reply: SmallTalk().thanksReply(), tool: nil)
        case .unknown: return ToolResult(reply: SmallTalk().unknownReply(), tool: nil)
        }
    }

    // MARK: - Приложения

    private func openApp(_ name: String) async -> ToolResult {
        let result = await run("/usr/bin/open", ["-a", name])
        let tool = "open_app(name=\"\(name)\")"
        guard result.status == 0 else { return ToolResult(reply: "Не нашёл приложение «\(name)»", tool: tool) }
        return ToolResult(reply: "Открываю \(name)", tool: tool)
    }

    // MARK: - Таймер и секундомер
    // У приложения «Часы» нет программного интерфейса, поэтому таймер и секундомер живут внутри Стива.

    private func startTimer(seconds: Int) -> ToolResult {
        requestNotificationAccess()
        let id = UUID()
        timers[id] = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.timerFired(id: id, seconds: seconds) }
        }
        activeTimers.append(ActiveTimer(id: id, end: Date().addingTimeInterval(TimeInterval(seconds)), total: seconds))
        onTimersChanged?()
        // у «Часов» нет программного интерфейса: открываем приложение, а отсчёт и сигнал ведёт Стив
        Task { _ = await run("/usr/bin/open", ["-a", "Clock"]) }
        return ToolResult(reply: "Поставил таймер на \(Self.describe(seconds: seconds))", tool: "timer(seconds=\(seconds))")
    }

    private func timerStatus() -> ToolResult {
        guard let next = activeTimers.map(\.end).min() else { return ToolResult(reply: "Таймеров нет", tool: "timer_status()") }
        let left = max(1, Int(next.timeIntervalSinceNow.rounded()))
        return ToolResult(reply: "До конца таймера \(Self.describe(seconds: left))", tool: "timer_status()")
    }

    private func cancelTimers() -> ToolResult {
        let count = activeTimers.count
        cancel(nil)
        return ToolResult(reply: count == 0 ? "Таймеров нет" : (count == 1 ? "Таймер отменён" : "Таймеры отменены"), tool: "cancel_timers()")
    }

    /// Отменяет один таймер или все, если `id` не указан.
    func cancel(_ id: UUID?) {
        for key in (id.map { [$0] } ?? Array(timers.keys)) {
            timers[key]?.invalidate()
            timers[key] = nil
        }
        activeTimers.removeAll { id == nil || $0.id == id }
        onTimersChanged?()
    }

    private func timerFired(id: UUID, seconds: Int) {
        timers[id] = nil
        activeTimers.removeAll { $0.id == id }
        onTimersChanged?()
        guard Packaging.isPackaged else { onTimerFired?(seconds); return }
        let content = UNMutableNotificationContent()
        content.title = "Стив"
        content.body = "Таймер на \(Self.describe(seconds: seconds)) сработал"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        onTimerFired?(seconds)
    }

    private func requestNotificationAccess() {
        guard Packaging.isPackaged else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func startStopwatch() -> ToolResult {
        stopwatchStartedAt = Date()
        return ToolResult(reply: "Секундомер запущен", tool: "start_stopwatch()")
    }

    private func stopStopwatch() -> ToolResult {
        guard let start = stopwatchStartedAt else { return ToolResult(reply: "Секундомер не был запущен", tool: "stop_stopwatch()") }
        stopwatchStartedAt = nil
        let seconds = Int(Date().timeIntervalSince(start))
        return ToolResult(reply: "Секундомер остановлен: \(seconds / 60) мин \(seconds % 60) сек", tool: "stop_stopwatch()")
    }

    static func describe(seconds: Int) -> String {
        switch seconds {
        case 3600...: return "\(seconds / 3600) ч" + (seconds % 3600 >= 60 ? " \(seconds % 3600 / 60) мин" : "")
        case 60...: return "\(seconds / 60) мин" + (seconds % 60 > 0 ? " \(seconds % 60) сек" : "")
        default: return "\(seconds) сек"
        }
    }

    // MARK: - «Заметки»

    private static let noteScript = """
    on run argv
        tell application "Notes"
            activate
            set theNote to make new note with properties {name:(item 1 of argv), body:(item 2 of argv)}
            show theNote
        end tell
        return "ok"
    end run
    """

    private func createNote(_ text: String) async -> ToolResult {
        let title = String(text.split(separator: "\n").first?.prefix(40) ?? "Заметка")
        let result = await run("/usr/bin/osascript", ["-e", Self.noteScript, title, text], timeout: 40)
        let tool = "Notes.create_note(text=\"\(title)\")"
        if result.status == 0 { return ToolResult(reply: "Создал заметку в «Заметках»", tool: tool) }
        return ToolResult(reply: Self.automationHint(result.err, app: "Заметкам"), tool: tool)
    }

    // MARK: - «Календарь»

    private func createEvent(title: String, start: Date, end: Date) async -> ToolResult {
        let tool = "Calendar.create_event(title=\"\(title)\", start=\"\(Self.isoFormatter.string(from: start))\", end=\"\(Self.isoFormatter.string(from: end))\")"
        guard Packaging.isPackaged else { return ToolResult(reply: Packaging.notPackagedHint, tool: tool) }
        NSApp.activate(ignoringOtherApps: true)
        do {
            guard try await eventStore.requestFullAccessToEvents() else {
                return ToolResult(reply: "Нет доступа к «Календарю». Разрешите его в настройках macOS", tool: tool)
            }
            guard let calendar = eventStore.defaultCalendarForNewEvents else {
                return ToolResult(reply: "Не нашёл календарь для новых событий", tool: tool)
            }
            let event = EKEvent(eventStore: eventStore)
            event.title = title
            event.startDate = start
            event.endDate = end
            event.calendar = calendar
            try eventStore.save(event, span: .thisEvent)
            await showInCalendar(start)
            return ToolResult(reply: "Добавил в «Календарь» событие «\(title)»: \(Self.eventFormatter.string(from: start))–\(Self.hourFormatter.string(from: end))", tool: tool)
        } catch {
            return ToolResult(reply: "Не получилось добавить событие: \(error.localizedDescription)", tool: tool)
        }
    }

    /// Открывает «Календарь» на дне нового события, чтобы было видно, что оно появилось.
    private func showInCalendar(_ date: Date) async {
        let script = """
        on run argv
            set d to (current date)
            set year of d to (item 1 of argv as integer)
            set month of d to (item 2 of argv as integer)
            set day of d to (item 3 of argv as integer)
            tell application "Calendar"
                activate
                switch view to day view
                view calendar at d
            end tell
        end run
        """
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        _ = await run("/usr/bin/osascript", ["-e", script, "\(parts.year ?? 2026)", "\(parts.month ?? 1)", "\(parts.day ?? 1)"], timeout: 20)
    }

    // MARK: - Громкость, время, батарея

    private func setVolume(_ percent: Int) async -> ToolResult {
        let level = max(0, min(100, percent))
        _ = await run("/usr/bin/osascript", ["-e", "set volume output volume \(level)"])
        return ToolResult(reply: "Громкость \(level)%", tool: "set_volume(percent=\(level))")
    }

    private func changeVolume(by delta: Int) async -> ToolResult {
        let current = await run("/usr/bin/osascript", ["-e", "output volume of (get volume settings)"])
        let now = Int(current.out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 50
        return await setVolume(now + delta)
    }

    private func currentTime() -> ToolResult {
        ToolResult(reply: "Сейчас \(Self.hourFormatter.string(from: Date())), \(Self.weekdayFormatter.string(from: Date()))", tool: "get_time()")
    }

    private func battery() async -> ToolResult {
        let result = await run("/usr/bin/pmset", ["-g", "batt"])
        let percent = result.out.range(of: "\\d+%", options: .regularExpression).map { String(result.out[$0]) }
        let charging = result.out.contains("AC Power") ? "на зарядке" : "не на зарядке"
        return ToolResult(reply: percent.map { "Заряд \($0), \(charging)" } ?? "Не вижу батарею", tool: "battery()")
    }

    // MARK: - Помощники

    private static func automationHint(_ error: String, app: String) -> String {
        if error.contains("нет ответа") {
            return "Нет ответа от приложения. Ответь на вопрос macOS о доступе к \(app) и повтори"
        }
        return error.contains("-1743")
            ? "Нет доступа к \(app). Разрешите Стиву управлять приложением в настройках macOS: Конфиденциальность → Автоматизация"
            : "Не получилось. \(error.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = format
        return formatter
    }

    private static let eventFormatter = formatter("d MMMM, HH:mm")
    private static let hourFormatter = formatter("HH:mm")
    private static let weekdayFormatter = formatter("EEEE")
    private static let isoFormatter = formatter("yyyy-MM-dd HH:mm")

    /// Запускает программу и ждёт её завершения, но не дольше положенного.
    private func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 20) async -> (status: Int32, out: String, err: String) {
        let result = await ProcessRunner.run(path, arguments, timeout: timeout)
        return (result.status, result.output, result.error)
    }
}

/// Запущенный таймер для показа в окне.
struct ActiveTimer: Identifiable, Equatable {
    let id: UUID
    let end: Date
    let total: Int
}
