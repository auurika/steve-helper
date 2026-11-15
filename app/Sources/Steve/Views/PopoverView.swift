import AppKit
import SteveCore
import SwiftUI

/// Всплывающее окно из значка в меню-баре: Стив, статус, четыре быстрые команды, компактный диалог.
struct PopoverView: View {
    @Environment(AppModel.self) private var model
    /// Окно меню-бара выезжает пружиной сверху, как `popover-in` в макете, и закрывается быстрее.
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.steveBody)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    // всегда четыре места: пустые ведут в настройки, где их можно заполнить
                    ForEach(0..<Preset.quickCount, id: \.self) { slot in
                        if model.quickPresets.indices.contains(slot) {
                            let preset = model.quickPresets[slot]
                            GlassIconButton(symbol: preset.symbol, size: 28) { model.runPreset(preset) }
                                .help(preset.name)
                        } else {
                            GlassIconButton(symbol: "plus", size: 28) {
                                model.section = .settings
                                model.openMainWindow?()
                            }
                            .opacity(0.45)
                            .help("Свободное место: выбери команду в настройках")
                        }
                    }
                }
            }

            PanelsView(compact: true)

            MessageList(messages: Array(model.messages.suffix(30)), showCommands: model.settings.showCommands, compact: true, isThinking: model.status == .thinking || model.status == .working)
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
        .modifier(Materialize(isActive: !shown, anchor: .top, scale: 0.84, blur: 10))
        .offset(y: shown || reduceMotion ? 0 : -14)
        .onAppear {
            DispatchQueue.main.async { Self.roundWindow() }
            present()
        }
        // окно остаётся живым между открытиями: показываем анимацию каждый раз, когда оно снова становится главным
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let window = note.object as? NSWindow, String(describing: type(of: window)).contains("MenuBarExtra") else { return }
            shown = false
            DispatchQueue.main.async { present() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            guard let window = note.object as? NSWindow, String(describing: type(of: window)).contains("MenuBarExtra") else { return }
            withAnimation(Motion.close) { shown = false }
        }
    }

    private func present() {
        withAnimation(Motion.open) { shown = true }
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
