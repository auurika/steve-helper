import AppKit
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

            TimerPanel(compact: true)

            MessageList(messages: Array(model.messages.suffix(30)), showCommands: model.settings.showCommands, compact: true)
                .frame(height: 168)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))

            ComposerView(compact: true)
        }
        .padding(16)
        .frame(width: 340)
        .foregroundStyle(Color.steveText)
        .background(Color.steveNavy.opacity(model.settings.glassAlpha)) // скругление и размытие даёт само окно меню-бара
        .environment(\.colorScheme, .dark)
        .onAppear { DispatchQueue.main.async { Self.roundWindow() } }
    }

    /// Скругляет окно из меню-бара до 22 пунктов, как боковую панель: системная форма окна у такого меню почти прямая.
    @MainActor
    private static func roundWindow() {
        for window in NSApp.windows where String(describing: type(of: window)).contains("MenuBarExtra") {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            for view in [window.contentView, window.contentView?.superview] {
                view?.wantsLayer = true
                view?.layer?.cornerRadius = 22
                view?.layer?.cornerCurve = .continuous
                view?.layer?.masksToBounds = true
            }
            // то же стекло, что у главного окна: размытие рабочего стола под окном и тонировка по ползунку прозрачности
            if let frameView = window.contentView?.superview, let content = window.contentView {
                let id = NSUserInterfaceItemIdentifier("steve.window.glass")
                if !frameView.subviews.contains(where: { $0.identifier == id }) {
                    let effect = NSVisualEffectView(frame: frameView.bounds)
                    effect.identifier = id
                    effect.material = .hudWindow
                    effect.blendingMode = .behindWindow
                    effect.state = .active
                    effect.autoresizingMask = [.width, .height]
                    frameView.addSubview(effect, positioned: .below, relativeTo: content)
                }
            }
            window.invalidateShadow()
        }
    }
}
