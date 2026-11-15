import AppKit
import Carbon.HIToolbox
import SteveCore

/// Глобальное сочетание клавиш для запуска Стива из любого приложения.
///
/// Сочетания с обычной клавишей (например ⌥ + Пробел) регистрируются через Carbon и не требуют разрешений.
/// Сочетания только из модификаторов (например ⌥) ловятся по событиям клавиатуры и требуют
/// разрешения «Мониторинг ввода» в настройках конфиденциальности.
@MainActor
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var flagsMonitors: [Any] = []
    private var modifiersHeld = false

    private static let signature: OSType = 0x5354_4556 // 'STEV'

    /// Заменяет текущее сочетание новым.
    func register(_ hotkey: Hotkey) {
        unregister()
        guard hotkey.isValid else { return }
        if let keyCode = hotkey.keyCode {
            registerCarbon(keyCode: keyCode, modifiers: hotkey.modifiers)
        } else {
            registerModifierOnly(hotkey.modifiers)
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        flagsMonitors.forEach(NSEvent.removeMonitor)
        flagsMonitors = []
        modifiersHeld = false
    }

    // MARK: - Carbon

    private func registerCarbon(keyCode: UInt16, modifiers: [Hotkey.Modifier]) {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            DispatchQueue.main.async { pressed ? manager.onPress?() : manager.onRelease?() }
            return noErr
        }, specs.count, &specs, userData, &handlerRef)

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(UInt32(keyCode), Self.carbonModifiers(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private static func carbonModifiers(_ modifiers: [Hotkey.Modifier]) -> UInt32 {
        modifiers.reduce(0) { result, modifier in
            switch modifier {
            case .control: return result | UInt32(controlKey)
            case .option: return result | UInt32(optionKey)
            case .shift: return result | UInt32(shiftKey)
            case .command: return result | UInt32(cmdKey)
            }
        }
    }

    // MARK: - Только модификаторы

    private func registerModifierOnly(_ modifiers: [Hotkey.Modifier]) {
        let wanted = Self.eventFlags(modifiers)
        let handle: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let pressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isSuperset(of: wanted)
            if pressed, !self.modifiersHeld {
                self.modifiersHeld = true
                self.onPress?()
            } else if !pressed, self.modifiersHeld {
                self.modifiersHeld = false
                self.onRelease?()
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { event in
            Task { @MainActor in handle(event) }
        }) {
            flagsMonitors.append(global)
        }
        flagsMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handle(event)
            return event
        } as Any)
    }

    private static func eventFlags(_ modifiers: [Hotkey.Modifier]) -> NSEvent.ModifierFlags {
        modifiers.reduce(into: NSEvent.ModifierFlags()) { flags, modifier in
            switch modifier {
            case .control: flags.insert(.control)
            case .option: flags.insert(.option)
            case .shift: flags.insert(.shift)
            case .command: flags.insert(.command)
            }
        }
    }
}

/// Запись нового сочетания: нажми клавиши, Escape отменяет. Подходят от 1 до 3 клавиш.
@MainActor
final class HotkeyRecorder {
    enum Result { case recorded(Hotkey), tooManyKeys, cancelled }

    private var monitor: Any?
    private var peakModifiers: [Hotkey.Modifier] = []
    private var onUpdate: ((String) -> Void)?
    private var onFinish: ((Result) -> Void)?

    func start(onUpdate: @escaping (String) -> Void, onFinish: @escaping (Result) -> Void) {
        stop()
        self.onUpdate = onUpdate
        self.onFinish = onFinish
        peakModifiers = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            self.handle(event)
            return nil // клавиши записи не должны попадать в окно
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func finish(_ result: Result) {
        let callback = onFinish
        stop()
        callback?(result)
    }

    private func handle(_ event: NSEvent) {
        let held = Self.modifiers(from: event.modifierFlags)

        if event.type == .flagsChanged {
            if held.count > Hotkey.maxKeys { return finish(.tooManyKeys) }
            if held.count >= peakModifiers.count { peakModifiers = held }
            // все модификаторы отпущены и ничего больше не нажимали: сохраняем только их
            if held.isEmpty, !peakModifiers.isEmpty { return finish(.recorded(Hotkey(modifiers: peakModifiers))) }
            onUpdate?(held.isEmpty ? "" : held.map(\.symbol).joined(separator: " + ") + " + …")
            return
        }

        if event.keyCode == UInt16(kVK_Escape) { return finish(.cancelled) }
        let label = Self.keyLabel(for: event)
        let hotkey = Hotkey(modifiers: held, keyCode: event.keyCode, keyLabel: label)
        finish(hotkey.isValid ? .recorded(hotkey) : .tooManyKeys)
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> [Hotkey.Modifier] {
        var result: [Hotkey.Modifier] = []
        if flags.contains(.control) { result.append(.control) }
        if flags.contains(.option) { result.append(.option) }
        if flags.contains(.shift) { result.append(.shift) }
        if flags.contains(.command) { result.append(.command) }
        return result
    }

    private static func keyLabel(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Пробел"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        default:
            let characters = event.charactersIgnoringModifiers ?? ""
            return characters.isEmpty ? "Клавиша \(event.keyCode)" : characters.uppercased()
        }
    }
}
