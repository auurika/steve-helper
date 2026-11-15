import SwiftUI
import SteveCore

/// Экран «Пресеты»: готовые и свои команды быстрого доступа. Все карточки одного размера.
struct PresetsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: PresetDraft?

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Пресеты").font(.system(size: 18, weight: .semibold))
                Text("Команды быстрого доступа")
                    .foregroundStyle(Color.steveMuted)
                    .padding(.bottom, 12)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.settings.presets) { preset in
                        PresetCard(symbol: preset.symbol, title: preset.name, description: preset.description, phrase: preset.phrase) {
                            editing = PresetDraft(preset: preset)
                        }
                    }
                    PresetCard(symbol: "plus", title: "Новая команда", description: "Создайте свою собственную команду для Стива", phrase: nil, isAddCard: true) {
                        editing = PresetDraft(preset: nil)
                    }
                }
            }
            .padding(22)
            .foregroundStyle(Color.steveText)
        }
        .sheet(item: $editing) { draft in
            PresetEditorView(draft: draft)
        }
    }
}

struct PresetDraft: Identifiable {
    let id = UUID()
    let preset: Preset?
}

private struct PresetCard: View {
    let symbol: String
    let title: String
    let description: String
    let phrase: String?
    var isAddCard = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.18)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.steveMuted)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if let phrase {
                    Text("«\(phrase)»")
                        .font(.system(size: 12).italic())
                        .foregroundStyle(Color.steveAccent)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .topLeading)
            .background {
                if isAddCard {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(hovering ? 0.18 : 0)))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.22 : 0.14))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Окно создания и правки команды. Под полем, пока печатаешь, виден счётчик «введено/максимум».
struct PresetEditorView: View {
    let draft: PresetDraft
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var phrase = ""
    @State private var symbol = "puzzlepiece"
    @State private var showingIcons = false
    @FocusState private var focus: Field?

    private enum Field { case name, description, phrase }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.preset == nil ? "Новая команда" : "Редактирование команды")
                .font(.system(size: 18, weight: .semibold))

            HStack(alignment: .top, spacing: 8) {
                Button { showingIcons = true } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 18))
                        .frame(width: 44, height: 44)
                        .glassControl(cornerRadius: 14)
                }
                .buttonStyle(.plain)
                .help("Выбрать иконку")
                labeled("Название") {
                    CountedField(title: "Например: Таймер", text: $name, limit: Preset.nameLimit, height: 44)
                        .focused($focus, equals: .name)
                }
            }
            labeled("Описание") {
                CountedField(title: "Что делает команда", text: $description, limit: Preset.descriptionLimit)
                    .focused($focus, equals: .description)
            }
            labeled("Фраза быстрой активации") {
                CountedField(title: "Что сказать Стиву", text: $phrase, limit: Preset.phraseLimit)
                    .focused($focus, equals: .phrase)
            }

            HStack {
                Spacer()
                Button(draft.preset == nil ? "Создать" : "Сохранить") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || phrase.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440)
        .foregroundStyle(Color.steveText)
        .onAppear {
            if let preset = draft.preset {
                name = preset.name
                description = preset.description
                phrase = preset.phrase
                symbol = preset.symbol
            }
        }
        .sheet(isPresented: $showingIcons) {
            IconPickerView(selection: $symbol)
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.steveMuted)
            content()
        }
    }

    private func save() {
        let preset = Preset(
            id: draft.preset?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces).isEmpty ? "Своя команда" : description.trimmingCharacters(in: .whitespaces),
            phrase: phrase.trimmingCharacters(in: .whitespaces),
            symbol: symbol
        )
        model.save(preset: preset)
        dismiss()
    }
}

/// Поле со счётчиком символов внутри справа: виден, пока печатаешь.
struct CountedField: View {
    let title: String
    @Binding var text: String
    let limit: Int
    var height: CGFloat = 40
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.trailing, 52)
            .frame(height: height)
            .glassControl(cornerRadius: 14)
            .overlay(alignment: .trailing) {
                Text("\(text.count)/\(limit)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(limit - text.count <= 5 ? Color(red: 1, green: 0.71, blue: 0.66) : Color.steveMuted)
                    .padding(.trailing, 14)
                    .opacity(focused ? 1 : 0)
            }
            .focused($focused)
            .onChange(of: text) {
                if text.count > limit { text = String(text.prefix(limit)) }
            }
    }
}

/// Выбор значка из SF Symbols.
struct IconPickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    static let symbols = [
        "safari", "timer", "note.text", "calendar", "speaker.wave.2", "stopwatch", "clock", "message", "mic", "puzzlepiece",
        "globe", "bolt", "bell", "moon", "sun.max", "lightbulb", "music.note", "envelope", "phone", "camera",
        "photo", "folder", "doc.text", "magnifyingglass", "lock", "key", "house", "mappin", "cart", "creditcard",
        "book", "graduationcap", "dumbbell", "cup.and.saucer", "fork.knife", "car", "airplane", "heart", "star", "flag",
        "bookmark", "tag", "trash", "arrow.down.circle", "paperplane", "bubble.left", "person", "person.2", "terminal", "cpu",
        "display", "laptopcomputer", "headphones", "play", "pause", "cloud", "function", "gamecontroller", "checklist", "alarm",
        "hourglass", "repeat", "sparkles", "wifi", "battery.100", "brain", "paintbrush", "wrench", "gift", "film",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Иконка пресета").font(.system(size: 18, weight: .semibold))
            Text("Выбери значок, который будет рядом с названием.").foregroundStyle(Color.steveMuted)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        Button {
                            selection = symbol
                            dismiss()
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 17))
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .glassControl(cornerRadius: 12, highlighted: symbol == selection)
                                .overlay {
                                    if symbol == selection {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.steveAccent, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 250)
        }
        .padding(22)
        .frame(width: 440)
        .foregroundStyle(Color.steveText)
    }
}
