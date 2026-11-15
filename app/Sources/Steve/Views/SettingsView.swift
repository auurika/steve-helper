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
                            .frame(minWidth: 140, idealWidth: 260, maxWidth: 260)
                        Text("\(model.settings.glassTransparency)%")
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }

                quickCommands
                wakePhrase
                hotkey
                voice

                toggle("Цензура", isOn: $model.settings.censorship)
                toggle("Отображение команд", hint: "Выполненные команды отображаются в сообщениях.", isOn: $model.settings.showCommands)
                toggle("Озвучивать ответы", isOn: $model.settings.speakAnswers)
                toggle("Запускать при входе в систему", isOn: $model.settings.launchAtLogin)
                toggle("Слушать постоянно", hint: "Ждать слово активации в фоне", isOn: $model.settings.listenAlways)
                permissionsRow
            }
            .padding(.vertical, 22)
            .foregroundStyle(Color.steveText)
        }
        .glassModal(item: $pickingSlot) { pick in QuickCommandPicker(slot: pick.slot) }
        .glassModal(isPresented: $showingWake) { WakePhraseSheet() }
    }

    // MARK: - Разрешения

    private var permissionsRow: some View {
        let permissions = model.permissions
        return SettingRow(title: "Разрешения, необходимые для работы", hint: permissions.progressHint, inline: true) {
            HStack(spacing: 12) {
                Text("\(permissions.grantedCount)/\(permissions.totalCount) разрешено")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(permissions.allGranted ? Color.steveOK : Color.steveText)
                if !permissions.allGranted {
                    Button { Task { await permissions.requestAll() } } label: {
                        Chip(permissions.isRequesting ? "Запрашиваю…" : "Разрешить", highlighted: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(permissions.isRequesting)
                }
            }
            .task {
                // пока экран открыт, проверяем права каждую секунду: счётчик растёт сразу после ответа
                while !Task.isCancelled {
                    await permissions.refresh()
                    try? await Task.sleep(for: .seconds(1))
                }
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
        let missing = !model.voices.contains { Speaker.isSteveVoice($0) }
        return SettingRow(title: "Голос Стива",
                   hint: model.voiceNote ?? (missing ? "Мужской голос Юрий скачивается один раз в настройках macOS" : nil)) {
            VoicePicker()
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
    private let thumbWidth: CGFloat = 38

    var body: some View {
        GeometryReader { proxy in
            // дорожка короче области жеста на ширину ползунка: так его можно взять и на 0%, и на 100%
            let track = max(1, proxy.size.width - thumbWidth)
            let value = Double(percent) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.34), lineWidth: 1))
                    .frame(height: 12)
                    .padding(.horizontal, thumbWidth / 2)
                if percent > 0 {
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 190 / 255, green: 208 / 255, blue: 1).opacity(0.78), .white.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                        .frame(width: max(12, track * value + thumbWidth / 2), height: 12)
                        .padding(.leading, thumbWidth / 2 - 6)
                }
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.55), .white.opacity(0.45), .white.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    .frame(width: thumbWidth, height: 26)
                    .offset(x: track * value)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            // тянуть можно за ползунок и за любое место полосы: значение следует за курсором
            .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { drag in
                percent = Int((min(max((drag.location.x - thumbWidth / 2) / track, 0), 1) * 100).rounded())
            })
        }
        .frame(height: 30)
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

/// Выбор голоса: Юрий, свои голоса и «Добавить свой голос…». Оформлен как остальные стеклянные элементы.
struct VoicePicker: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    private var steveVoice: AVSpeechSynthesisVoice? { model.voices.first { Speaker.isSteveVoice($0) } }

    var body: some View {
        Menu {
            if let voice = steveVoice {
                Button { choose(voice) } label: {
                    if isSelected(voice) { Label("Юрий", systemImage: "checkmark") } else { Text("Юрий") }
                }
            } else {
                Button("Юрий: скачать в настройках macOS…") { Permissions.openSettings(.spokenContent) }
            }
            ForEach(model.voices.filter { Speaker.isPersonal($0) }, id: \.identifier) { voice in
                Button { choose(voice) } label: {
                    if isSelected(voice) { Label("\(voice.name) (личный голос)", systemImage: "checkmark") } else { Text("\(voice.name) (личный голос)") }
                }
            }
            if !model.settings.customVoices.isEmpty { Divider() }
            ForEach(model.settings.customVoices) { custom in
                Button {
                    model.settings.selectedCustomVoice = custom.id
                    model.voiceNote = nil
                    model.previewVoice()
                } label: {
                    let text = "Свой: \(custom.name) (\(Int(custom.hertz)) Гц)"
                    if model.settings.selectedCustomVoice == custom.id { Label(text, systemImage: "checkmark") } else { Text(text) }
                }
            }
            Divider()
            Button("Добавить свой голос…") { chooseFile() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "waveform").font(.system(size: 13))
                Text(currentTitle).lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.steveMuted)
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.steveText)
            .padding(.horizontal, 14)
            .frame(width: 250, height: 38)
            .glassControl(cornerRadius: 13, highlighted: hovering)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering = $0 }
        .task { await model.refreshVoices() }
    }

    private var currentTitle: String {
        if let id = model.settings.selectedCustomVoice, let custom = model.settings.customVoices.first(where: { $0.id == id }) {
            return "Свой: \(custom.name) (\(Int(custom.hertz)) Гц)"
        }
        if let id = model.settings.voiceIdentifier, let voice = model.voices.first(where: { $0.identifier == id }) {
            return Speaker.isPersonal(voice) ? "\(voice.name) (личный голос)" : "Юрий"
        }
        return steveVoice == nil ? "Юрий (не скачан)" : "Юрий"
    }

    private func isSelected(_ voice: AVSpeechSynthesisVoice) -> Bool {
        guard model.settings.selectedCustomVoice == nil else { return false }
        if let id = model.settings.voiceIdentifier { return id == voice.identifier }
        return Speaker.isSteveVoice(voice)
    }

    private func choose(_ voice: AVSpeechSynthesisVoice) {
        model.settings.voiceIdentifier = voice.identifier
        model.settings.selectedCustomVoice = nil
        model.voiceNote = nil
        model.previewVoice() // сразу даём послушать, чтобы было слышно, что голос применился
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
    @Environment(\.closeModal) private var dismiss

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
