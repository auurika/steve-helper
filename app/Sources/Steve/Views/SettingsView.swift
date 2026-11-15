import AppKit
import AVFoundation
import SwiftUI
import SteveCore

/// Экран «Настройки»: каждая настройка в своей стеклянной плашке.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var pickingSlot: SlotPick?
    @State private var showingWake = false

    var body: some View {
        @Bindable var model = model

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Настройки")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.bottom, 4)

                SettingRow(title: "Прозрачность Liquid Glass", inline: true) {
                    HStack(spacing: 14) {
                        GlassSlider(percent: $model.settings.glassTransparency)
                            .frame(width: 110)
                        Text("\(model.settings.glassTransparency)%")
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }

                permissionsRow
                quickCommands
                wakePhrase
                hotkey
                voice

                toggle("Цензура", isOn: $model.settings.censorship)
                toggle("Отображение команд", hint: "Выполненные команды отображаются в сообщениях.", isOn: $model.settings.showCommands)
                toggle("Озвучивать ответы", isOn: $model.settings.speakAnswers)
                toggle("Запускать при входе в систему", isOn: $model.settings.launchAtLogin)
                toggle("Слушать постоянно", hint: "Ждать слово активации в фоне", isOn: $model.settings.listenAlways)
            }
            .padding(22)
            .foregroundStyle(Color.steveText)
        }
        .sheet(item: $pickingSlot) { pick in QuickCommandPicker(slot: pick.slot) }
        .sheet(isPresented: $showingWake) { WakePhraseSheet() }
    }

    // MARK: - Разрешения

    private var permissionsRow: some View {
        let permissions = model.permissions
        return SettingRow(title: "Разрешения", hint: "Без них часть умений не работает", fullWidthControls: true) {
            VStack(spacing: 8) {
                permission("Микрофон", state: permissions.microphone, ask: { await permissions.requestVoice() }, fix: .microphone)
                permission("Распознавание речи", state: permissions.speech, ask: { await permissions.requestVoice() }, fix: .speech)
                permission("Календарь", state: permissions.calendar, ask: { await permissions.requestCalendar() }, fix: .calendars)
                permission("Уведомления", state: permissions.notifications, ask: { await permissions.requestNotifications() }, fix: .notifications)
                HStack {
                    Text("«Заметки»").font(.system(size: 13))
                    Spacer(minLength: 8)
                    if permissions.notesResult == "Разрешено" {
                        Text("Разрешено").font(.system(size: 12)).foregroundStyle(Color.steveOK)
                    } else {
                        Button {
                            Permissions.openSettings(.automation)
                            Task { await permissions.checkNotes() }
                        } label: { Chip("Разрешить", highlighted: true) }.buttonStyle(.plain)
                    }
                }
            }
            .task {
                // пока экран открыт, проверяем права каждую секунду: «Разрешено» появляется сразу после ответа
                while !Task.isCancelled {
                    await permissions.refresh()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    private func permission(_ title: String, state: PermissionState, ask: @escaping () async -> Void, fix: Permissions.Pane) -> some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            if state == .granted {
                Text("Разрешено").font(.system(size: 12)).foregroundStyle(Color.steveOK)
            } else {
                // ещё не спрашивали: показываем системный вопрос; отказано раньше: ведём в настройки macOS
                Button {
                    if state == .notAsked { Task { await ask() } } else { Permissions.openSettings(fix) }
                } label: { Chip("Разрешить", highlighted: true) }.buttonStyle(.plain)
            }
        }
    }

    // MARK: - Быстрые команды

    private struct SlotPick: Identifiable {
        let slot: Int
        var id: Int { slot }
    }

    private var quickCommands: some View {
        SettingRow(title: "Быстрые команды", hint: "4 значка рядом со Стивом во всплывающем окне", fullWidthControls: true) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(model.quickPresets.enumerated()), id: \.offset) { slot, preset in
                    Button { pickingSlot = SlotPick(slot: slot) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: preset.symbol).frame(width: 20)
                            Text(preset.name).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 56)
                        .glassControl(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                    .help("Сменить команду")
                }
            }
        }
    }

    // MARK: - Слово активации

    private var wakePhrase: some View {
        SettingRow(title: "Слово активации") {
            HStack(spacing: 8) {
                Chip("«\(model.settings.wakePhrase)»")
                GlassIconButton(symbol: "pencil", size: 34) { showingWake = true }
                    .help("Изменить фразу и записать голос")
            }
        }
    }

    // MARK: - Сочетание для запуска

    private var hotkey: some View {
        @Bindable var model = model
        return SettingRow(title: "Сочетание для запуска") {
            HStack(spacing: 8) {
                Button {
                    model.settings.hotkeyMode = model.settings.hotkeyMode == .press ? .hold : .press
                } label: {
                    Chip(model.settings.hotkeyMode.title, minWidth: 114)
                }
                .buttonStyle(.plain)
                .help(model.settings.hotkeyMode == .press
                      ? "Нажал — Стив слушает, нажал ещё раз — закончил. Нажми, чтобы переключить на удерживание"
                      : "Стив слушает, пока держишь сочетание. Нажми, чтобы переключить на нажатие")
                HotkeyField(hotkey: $model.settings.hotkey)
            }
        }
    }

    // MARK: - Голос Стива

    private var voice: some View {
        SettingRow(title: "Голос Стива",
                   hint: model.voiceNote ?? "Русский текст читает русский голос. Больше голосов: кнопка справа") {
            HStack(spacing: 8) {
                VoicePicker()
                GlassIconButton(symbol: "arrow.down.circle", size: 34) { Permissions.openSettings(.spokenContent) }
                    .help("Скачать другие голоса в настройках macOS: Универсальный доступ → Устная речь")
            }
        }
    }

    // MARK: - Переключатели

    private func toggle(_ title: String, hint: String? = nil, isOn: Binding<Bool>) -> some View {
        SettingRow(title: title, hint: hint) {
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

/// Плашка настройки: подпись слева, управление справа. В узком окне управление уходит под подпись.
struct SettingRow<Controls: View>: View {
    let title: String
    var hint: String?
    var inline = false
    var fullWidthControls = false
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        Group {
            if fullWidthControls {
                VStack(alignment: .leading, spacing: 10) { label; controls() }
            } else if inline {
                HStack { label; Spacer(minLength: 8); controls() }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { label; Spacer(minLength: 8); controls() }
                    VStack(alignment: .leading, spacing: 10) { label; controls() }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPlate()
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let hint {
                Text(hint).font(.system(size: 11)).foregroundStyle(Color.steveMuted)
            }
        }
        .frame(minWidth: 110, alignment: .leading)
    }
}

/// Значение настройки в стеклянной таблетке.
struct Chip: View {
    let text: String
    var minWidth: CGFloat = 0
    var highlighted = false

    init(_ text: String, minWidth: CGFloat = 0, highlighted: Bool = false) {
        self.text = text
        self.minWidth = minWidth
        self.highlighted = highlighted
    }

    var body: some View {
        Text(text)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: minWidth)
            .glassControl(cornerRadius: 10, highlighted: highlighted)
    }
}

/// Ползунок прозрачности: заливка идёт от начала до конца шкалы, бегунок только украшает
/// (его середина стоит на конце заливки и может выходить за края).
struct GlassSlider: View {
    @Binding var percent: Int

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let value = Double(percent) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.34), lineWidth: 1))
                    .frame(height: 12)
                if percent > 0 {
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 190 / 255, green: 208 / 255, blue: 1).opacity(0.78), .white.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                        .frame(width: max(12, width * value), height: 12)
                }
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.55), .white.opacity(0.45), .white.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    .frame(width: 38, height: 26)
                    .offset(x: width * value - 19)
            }
            .frame(height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                percent = Int((min(max(drag.location.x / width, 0), 1) * 100).rounded())
            })
        }
        .frame(height: 30)
        .padding(.horizontal, 19)
        .accessibilityLabel("Прозрачность Liquid Glass")
        .accessibilityValue("\(percent)%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: percent = min(100, percent + 5)
            case .decrement: percent = max(0, percent - 5)
            @unknown default: break
            }
        }
    }
}

/// Поле сочетания: нажми на него и нажми новое сочетание (от 1 до 3 клавиш).
struct HotkeyField: View {
    @Binding var hotkey: Hotkey
    @State private var recorder = HotkeyRecorder()
    @State private var live: String?
    @State private var isRecording = false
    @State private var warning = false

    var body: some View {
        Button {
            guard !isRecording else { return }
            isRecording = true
            warning = false
            live = "Нажми сочетание…"
            recorder.start(onUpdate: { text in live = text.isEmpty ? "Нажми сочетание…" : text }) { result in
                isRecording = false
                switch result {
                case .recorded(let new): hotkey = new; live = nil
                case .cancelled: live = nil
                case .tooManyKeys:
                    warning = true
                    live = "Максимум \(Hotkey.maxKeys) клавиши"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { warning = false; live = nil }
                }
            }
        } label: {
            Chip(live ?? hotkey.display, highlighted: isRecording)
                .overlay {
                    if isRecording || warning {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(warning ? Color.steveDanger : Color.steveAccent, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help("Нажми, чтобы записать новое сочетание (от 1 до 3 клавиш)")
    }
}

/// Выбор голоса. Последний пункт «Добавить свой голос…» открывает выбор файла с записью голоса.
struct VoicePicker: View {
    @Environment(AppModel.self) private var model

    private static let addTag = "add"

    var body: some View {
        @Bindable var model = model

        Picker("", selection: selection) {
            ForEach(model.voices, id: \.identifier) { voice in
                Text(label(for: voice)).tag(voice.identifier)
            }
            ForEach(model.settings.customVoices) { custom in
                Text("Свой: \(custom.name) (\(Int(custom.hertz)) Гц)").tag("custom:\(custom.id.uuidString)")
            }
            Divider()
            Text("Добавить свой голос…").tag(Self.addTag)
        }
        .labelsHidden()
        .frame(maxWidth: 260)
        .task { await model.refreshVoices() }
    }

    private func label(for voice: AVSpeechSynthesisVoice) -> String {
        Speaker.isPersonal(voice) ? "\(voice.name) (личный голос)" : "\(voice.name) (\(voice.language))"
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                if let id = model.settings.selectedCustomVoice { return "custom:\(id.uuidString)" }
                return model.settings.voiceIdentifier ?? model.voices.first { $0.language.hasPrefix("ru") }?.identifier ?? ""
            },
            set: { value in
                if value == Self.addTag {
                    chooseFile()
                } else if value.hasPrefix("custom:"), let id = UUID(uuidString: String(value.dropFirst(7))) {
                    model.settings.selectedCustomVoice = id
                    model.voiceNote = nil
                    model.previewVoice()
                } else {
                    model.settings.voiceIdentifier = value
                    model.settings.selectedCustomVoice = nil
                    model.voiceNote = nil
                    model.previewVoice() // сразу даём послушать, чтобы было слышно, что голос применился
                }
            }
        )
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Выберите запись вашего голоса"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.addCustomVoice(from: url) }
    }
}

/// Выбор быстрой команды для кнопки. Уже выбранные в других слотах недоступны.
struct QuickCommandPicker: View {
    let slot: Int
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Быстрая команда").font(.system(size: 18, weight: .semibold))
            Text("Выбери команду для кнопки \(slot + 1). Уже выбранные недоступны.").foregroundStyle(Color.steveMuted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(model.settings.presets) { preset in
                    let mine = model.settings.quick.indices.contains(slot) && model.settings.quick[slot] == preset.id
                    let taken = model.settings.quick.contains(preset.id) && !mine
                    Button {
                        model.setQuick(slot: slot, to: preset.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: preset.symbol).frame(width: 20)
                            Text(preset.name).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 56)
                        .glassControl(cornerRadius: 14)
                        .overlay {
                            if mine { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.steveAccent, lineWidth: 2) }
                        }
                        .opacity(taken ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(taken)
                }
            }
        }
        .padding(22)
        .frame(width: 440)
        .foregroundStyle(Color.steveText)
    }
}
