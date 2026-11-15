import Foundation

enum Packaging {
    /// Запущено ли приложение из собранного пакета .app (scripts/build-app.sh).
    /// Без пакета у программы нет описаний разрешений, и macOS аварийно закрывает её при первом обращении
    /// к микрофону, календарю или уведомлениям. Поэтому в таком режиме эти возможности отключены.
    static var isPackaged: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static let notPackagedHint = "Запусти собранное приложение (scripts/build-app.sh): без него macOS не даёт доступ к микрофону, календарю и уведомлениям"
}
