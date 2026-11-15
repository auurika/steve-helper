import Foundation

/// Пресет: готовая или своя команда быстрого доступа.
public struct Preset: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var description: String
    public var phrase: String
    /// Имя значка из SF Symbols.
    public var symbol: String

    public static let nameLimit = 30
    public static let descriptionLimit = 60
    public static let phraseLimit = 40

    public init(id: UUID = UUID(), name: String, description: String, phrase: String, symbol: String) {
        self.id = id
        self.name = name
        self.description = description
        self.phrase = phrase
        self.symbol = symbol
    }

    /// Пять готовых пресетов. Идентификаторы фиксированы, чтобы быстрые команды переживали обновления.
    public static let defaults: [Preset] = [
        Preset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Открыть Safari",
               description: "Открывает Safari на Mac", phrase: "Открой Safari", symbol: "safari"),
        Preset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Таймер на 10 минут",
               description: "Запускает таймер на 10 минут", phrase: "Таймер на 10 минут", symbol: "timer"),
        Preset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Новая заметка",
               description: "Создаёт новую заметку в приложении «Заметки»", phrase: "Запиши заметку: купить молоко", symbol: "note.text"),
        Preset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "Событие в календаре",
               description: "Добавляет событие в приложение «Календарь»", phrase: "23 ноября с 17 до 19 событие Зал", symbol: "calendar"),
        Preset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, name: "Громкость 30%",
               description: "Системный звук становится на уровень 30%", phrase: "Громкость 30%", symbol: "speaker.wave.2"),
    ]

    /// Какие четыре пресета стоят во всплывающем окне по умолчанию: таймер, заметка, Safari, календарь.
    public static let defaultQuick: [UUID] = [defaults[1].id, defaults[2].id, defaults[0].id, defaults[3].id]
}

public enum HotkeyMode: String, Codable, CaseIterable {
    case press, hold

    public var title: String { self == .press ? "Нажатие" : "Удерживание" }
}

/// Сочетание клавиш для запуска: от 1 до 3 клавиш (модификаторы тоже считаются).
public struct Hotkey: Codable, Equatable {
    public enum Modifier: String, Codable, CaseIterable {
        // порядок как в macOS: ⌃ ⌥ ⇧ ⌘
        case control, option, shift, command

        public var symbol: String {
            switch self {
            case .control: return "⌃"
            case .option: return "⌥"
            case .shift: return "⇧"
            case .command: return "⌘"
            }
        }
    }

    public static let maxKeys = 3

    public var modifiers: [Modifier]
    /// Код основной клавиши. Nil, если сочетание состоит только из модификаторов.
    public var keyCode: UInt16?
    public var keyLabel: String?

    public init(modifiers: [Modifier], keyCode: UInt16? = nil, keyLabel: String? = nil) {
        self.modifiers = Modifier.allCases.filter(modifiers.contains)
        self.keyCode = keyCode
        self.keyLabel = keyLabel
    }

    public static let `default` = Hotkey(modifiers: [.option], keyCode: 49, keyLabel: "Пробел")

    public var keyCount: Int { modifiers.count + (keyLabel == nil ? 0 : 1) }
    public var isValid: Bool { keyCount >= 1 && keyCount <= Self.maxKeys }

    /// Например «⌥ + Пробел».
    public var display: String {
        (modifiers.map(\.symbol) + [keyLabel].compactMap { $0 }).joined(separator: " + ")
    }
}

/// Свой голос из файла: системный голос с тоном, измеренным в записи.
public struct CustomVoice: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var hertz: Double

    public init(id: UUID = UUID(), name: String, hertz: Double) {
        self.id = id
        self.name = name
        self.hertz = hertz
    }

    public var pitchMultiplier: Float { PitchEstimator.pitchMultiplier(forHz: hertz) }
}

/// Все настройки приложения. Хранятся в UserDefaults; новые поля безопасно добавляются без потери старых.
public struct AppSettings: Codable, Equatable {
    /// 0 — почти матовое стекло, 100 — почти невидимое.
    public var glassTransparency = 60
    public var censorship = true
    public var showCommands = true
    public var speakAnswers = true
    public var launchAtLogin = false
    public var listenAlways = true
    public var wakePhrase = "Привет, Стив"
    public var hotkey = Hotkey.default
    public var hotkeyMode = HotkeyMode.press
    /// Идентификатор системного голоса (AVSpeechSynthesisVoice.identifier) или nil — голос по умолчанию.
    public var voiceIdentifier: String?
    public var customVoices: [CustomVoice] = []
    public var selectedCustomVoice: UUID?
    public var presets = Preset.defaults
    public var quick = Preset.defaultQuick

    public init() {}

    /// Плотность стекла: 0.9 при 0% и 0.05 при 100%.
    public var glassAlpha: Double { 0.9 - Double(glassTransparency) / 100 * 0.85 }

    enum CodingKeys: String, CodingKey {
        case glassTransparency, censorship, showCommands, speakAnswers, launchAtLogin, listenAlways, wakePhrase
        case hotkey, hotkeyMode, voiceIdentifier, customVoices, selectedCustomVoice, presets, quick
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        glassTransparency = try container.decodeIfPresent(Int.self, forKey: .glassTransparency) ?? glassTransparency
        censorship = try container.decodeIfPresent(Bool.self, forKey: .censorship) ?? censorship
        showCommands = try container.decodeIfPresent(Bool.self, forKey: .showCommands) ?? showCommands
        speakAnswers = try container.decodeIfPresent(Bool.self, forKey: .speakAnswers) ?? speakAnswers
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? launchAtLogin
        listenAlways = try container.decodeIfPresent(Bool.self, forKey: .listenAlways) ?? listenAlways
        wakePhrase = try container.decodeIfPresent(String.self, forKey: .wakePhrase) ?? wakePhrase
        hotkey = try container.decodeIfPresent(Hotkey.self, forKey: .hotkey) ?? hotkey
        hotkeyMode = try container.decodeIfPresent(HotkeyMode.self, forKey: .hotkeyMode) ?? hotkeyMode
        voiceIdentifier = try container.decodeIfPresent(String.self, forKey: .voiceIdentifier)
        customVoices = try container.decodeIfPresent([CustomVoice].self, forKey: .customVoices) ?? customVoices
        selectedCustomVoice = try container.decodeIfPresent(UUID.self, forKey: .selectedCustomVoice)
        presets = try container.decodeIfPresent([Preset].self, forKey: .presets) ?? presets
        quick = try container.decodeIfPresent([UUID].self, forKey: .quick) ?? quick
    }
}
