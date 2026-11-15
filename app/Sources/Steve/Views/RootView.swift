import AppKit
import SwiftUI

/// Окно приложения: парящая боковая панель слева и выбранный экран справа.
struct RootView: View {
    var body: some View {
        RootContent()
            .background(WindowConfigurator())
            .frame(minWidth: 420, minHeight: 460)
    }
}

/// Содержимое окна без привязки к настоящему окну macOS. Его же рисует режим снимков для проверки.
struct RootContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                switch model.section {
                case .chat: ChatView()
                case .presets: PresetsView()
                case .settings: SettingsView()
                }
            }
            .padding(.leading, 76)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // верхняя полоса окна: то же стекло и тонкая линия снизу
            VStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 28)
                Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
                Spacer(minLength: 0)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            SidebarView()
                .padding(.leading, 10)
                .padding(.top, 2)
                .padding(.bottom, 10)
        }
        .foregroundStyle(Color.steveText)
        .background { Color.steveNavy.opacity(model.settings.glassAlpha).ignoresSafeArea() }
        .preferredColorScheme(.dark)
    }
}

/// Настраивает обычное окно macOS: кнопки закрыть, свернуть и на весь экран, заголовок «Стив»,
/// за который окно можно перетаскивать, и растягивание за любой край.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.title = "Стив"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.isOpaque = false
        window.backgroundColor = .clear
        installGlass(in: window)
        window.collectionBehavior.insert(.fullScreenPrimary)
    }

    /// Размытие рабочего стола под окном. Вставляем обычное AppKit-представление под содержимое окна,
    /// а не внутрь SwiftUI: так оно не участвует в обработке кликов SwiftUI.
    private func installGlass(in window: NSWindow) {
        guard let content = window.contentView, let frameView = content.superview else { return }
        let id = NSUserInterfaceItemIdentifier("steve.window.glass")
        if frameView.subviews.contains(where: { $0.identifier == id }) { return }
        let effect = NSVisualEffectView(frame: frameView.bounds)
        effect.identifier = id
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        frameView.addSubview(effect, positioned: .below, relativeTo: content)
    }
}
