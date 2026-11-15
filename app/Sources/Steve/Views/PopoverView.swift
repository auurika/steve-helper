import SwiftUI

/// Всплывающее окно из значка в меню-баре: Стив, статус, четыре быстрые команды, компактный диалог.
struct PopoverView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SteveView(controller: model.character)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .onTapGesture { model.toggleVoiceCapture() }
                    .help("Нажми, чтобы говорить")

                VStack(alignment: .leading, spacing: 0) {
                    Text("Стив").fontWeight(.semibold)
                    Text(model.status.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.steveMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    ForEach(model.quickPresets) { preset in
                        GlassIconButton(symbol: preset.symbol, size: 28) { model.runPreset(preset) }
                            .help(preset.name)
                    }
                }
            }

            MessageList(messages: Array(model.messages.suffix(30)), showCommands: model.settings.showCommands, compact: true)
                .frame(height: 168)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))

            ComposerView(compact: true)
        }
        .padding(16)
        .frame(width: 340)
        .foregroundStyle(Color.steveText)
        .glassSurface(alpha: model.settings.glassAlpha)
        .environment(\.colorScheme, .dark)
    }
}
