import AppKit
import ApplicationServices

/// Управляет приложением «Часы» так же, как это делал бы человек: открывает таймеры, вводит время, жмёт кнопки.
/// У «Часов» нет программного интерфейса, поэтому работа идёт через универсальный доступ macOS:
/// без этого права Стив только открывает «Часы», а таймер ведёт сам.
@MainActor
enum ClockController {
    static let bundleID = "com.apple.clock"

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Показывает системный вопрос про универсальный доступ.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: - Действия

    /// Ставит таймер на `seconds` секунд в «Часах» и запускает его. Возвращает false, если не вышло.
    static func startTimer(seconds: Int) async -> Bool {
        guard isTrusted, let app = await launch() else { return false }
        guard var window = await mainWindow(of: app) else { return false }

        // если уже идёт другой таймер, окно показывает его: просим «Часы» открыть новый
        if find(in: window, role: "AXButton", titles: ["Старт", "Start"]) == nil {
            if let add = find(in: window, role: "AXMenuButton", titles: ["Добавить", "Add"]) {
                press(add)
                try? await Task.sleep(for: .milliseconds(500))
                window = await mainWindow(of: app) ?? window
            }
        }
        guard let start = find(in: window, role: "AXButton", titles: ["Старт", "Start"]),
              let startFrame = frame(of: start) else { return false }

        // поля часов, минут и секунд: по их положению относительно кнопки «Старт» (в точках)
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60, secs = seconds % 60
        let centerX = startFrame.midX - 85 // середина окна: кнопка «Старт» правее середины
        let y = startFrame.midY - 281
        let fields: [(dx: CGFloat, text: String)] = [(-138, two(hours)), (-5, two(minutes)), (133, two(secs))]
        for field in fields {
            click(at: CGPoint(x: centerX + field.dx, y: y))
            try? await Task.sleep(for: .milliseconds(150))
            type(field.text)
            try? await Task.sleep(for: .milliseconds(150))
        }
        press(start)
        return true
    }

    /// Нажимает «Пауза» или «Продолжить», смотря что сейчас есть в окне.
    static func togglePause() async -> Bool {
        guard isTrusted, let app = runningClock(), let window = await mainWindow(of: app) else { return false }
        if let button = find(in: window, role: "AXButton", titles: ["Пауза", "Pause", "Продолжить", "Возобновить", "Resume"]) {
            press(button)
            return true
        }
        return false
    }

    /// Отменяет таймер и закрывает окно «Часов».
    static func stopAndClose() async {
        guard isTrusted, let app = runningClock(), let window = await mainWindow(of: app) else { return }
        if let cancel = find(in: window, role: "AXButton", titles: ["Отменить", "Cancel"]) { press(cancel) }
        try? await Task.sleep(for: .milliseconds(300))
        var close: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &close) == .success, let button = close {
            press(button as! AXUIElement) // swiftlint:disable:this force_cast
        }
    }

    // MARK: - Запуск и окно

    private static func runningClock() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    private static func launch() async -> NSRunningApplication? {
        if let app = runningClock() {
            app.activate()
            return app
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private static func mainWindow(of app: NSRunningApplication) async -> AXUIElement? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        for _ in 0..<20 { // ждём до 4 секунд, пока окно появится
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
               let windows = value as? [AXUIElement], let first = windows.first {
                return first
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return nil
    }

    // MARK: - Поиск элементов и нажатия

    private static func text(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func find(in root: AXUIElement, role: String, titles: [String], depth: Int = 0) -> AXUIElement? {
        guard depth < 14 else { return nil }
        if text(root, kAXRoleAttribute as String) == role {
            let label = text(root, kAXTitleAttribute as String) ?? text(root, kAXDescriptionAttribute as String) ?? ""
            if titles.contains(where: { label.localizedCaseInsensitiveCompare($0) == .orderedSame }) { return root }
        }
        for child in children(root) {
            if let found = find(in: child, role: role, titles: titles, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let positionValue = position, let sizeValue = size else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point) // swiftlint:disable:this force_cast
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &dimensions) // swiftlint:disable:this force_cast
        return CGRect(origin: point, size: dimensions)
    }

    @discardableResult
    private static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private static func click(at point: CGPoint) {
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }

    private static let digitKeys: [Character: CGKeyCode] = ["0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25]

    private static func type(_ digits: String) {
        for character in digits {
            guard let key = digitKeys[character] else { continue }
            CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap)
        }
    }

    private static func two(_ value: Int) -> String { String(format: "%02d", min(99, max(0, value))) }
}
