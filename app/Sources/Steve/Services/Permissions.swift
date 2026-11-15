import AppKit
import AVFoundation
import EventKit
import Observation
import Speech
import UserNotifications

enum PermissionState {
    case granted, notAsked, denied

    var label: String {
        switch self {
        case .granted: return "Разрешено"
        case .notAsked: return "Не спрашивали"
        case .denied: return "Запрещено"
        }
    }
}

/// Разрешения macOS, без которых Стив теряет умения. Показываются в настройках с кнопками «Разрешить».
@MainActor
@Observable
final class Permissions {
    private(set) var microphone = PermissionState.notAsked
    private(set) var speech = PermissionState.notAsked
    private(set) var calendar = PermissionState.notAsked
    private(set) var notifications = PermissionState.notAsked
    /// Результат последней проверки доступа к «Заметкам»: у него нет статуса, только проба.
    private(set) var notesResult: String?

    var isReadyForVoice: Bool { microphone == .granted && speech == .granted }

    func refresh() async {
        microphone = Self.state(avStatus: AVCaptureDevice.authorizationStatus(for: .audio))
        speech = Self.state(speechStatus: SFSpeechRecognizer.authorizationStatus())
        calendar = Self.state(calendarStatus: EKEventStore.authorizationStatus(for: .event))
        if Packaging.isPackaged {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notifications = Self.state(notificationStatus: settings.authorizationStatus)
        }
    }

    // MARK: - Запросы (показывают системное окно с вопросом)

    func requestVoice() async {
        NSApp.activate(ignoringOtherApps: true) // системный вопрос не должен остаться за чужими окнами
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        _ = await AVAudioApplication.requestRecordPermission()
        await refresh()
    }

    func requestCalendar() async {
        NSApp.activate(ignoringOtherApps: true)
        _ = try? await EKEventStore().requestFullAccessToEvents()
        await refresh()
    }

    func requestNotifications() async {
        guard Packaging.isPackaged else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
    }

    /// Пробное обращение к «Заметкам»: так macOS показывает вопрос про автоматизацию.
    func checkNotes() async {
        notesResult = "Проверяю…"
        let result = await ProcessRunner.run("/usr/bin/osascript", ["-e", "tell application \"Notes\" to count notes"], timeout: 30)
        if result.status == 0 {
            notesResult = "Разрешено"
        } else if result.error.contains("-1743") {
            notesResult = "Запрещено"
        } else if result.timedOut {
            notesResult = "Нет ответа: ответьте на вопрос macOS и нажмите ещё раз"
        } else {
            notesResult = "Не получилось: \(result.error.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }

    /// Открывает нужный раздел системных настроек.
    static func openSettings(_ pane: Pane) {
        if let url = URL(string: "x-apple.systempreferences:\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }

    enum Pane: String {
        case microphone = "com.apple.preference.security?Privacy_Microphone"
        case speech = "com.apple.preference.security?Privacy_SpeechRecognition"
        case calendars = "com.apple.preference.security?Privacy_Calendars"
        case automation = "com.apple.preference.security?Privacy_Automation"
        case notifications = "com.apple.Notifications-Settings.extension"
        case spokenContent = "com.apple.Accessibility-Settings.extension?SpokenContent"
    }

    // MARK: - Перевод системных статусов

    private static func state(avStatus: AVAuthorizationStatus) -> PermissionState {
        switch avStatus {
        case .authorized: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    private static func state(speechStatus: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch speechStatus {
        case .authorized: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    private static func state(calendarStatus: EKAuthorizationStatus) -> PermissionState {
        switch calendarStatus {
        case .fullAccess: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    private static func state(notificationStatus: UNAuthorizationStatus) -> PermissionState {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }
}
