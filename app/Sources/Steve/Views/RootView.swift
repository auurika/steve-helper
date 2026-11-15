import AppKit
import SwiftUI

/// Окно приложения: парящая боковая панель слева и выбранный экран справа.
struct RootView: View {
    var body: some View {
        RootContent()
            .containerBackground(.ultraThinMaterial, for: .window)
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

            SidebarView()
                .padding(.leading, 10)
                .padding(.top, 2)
                .padding(.bottom, 10)
        }
        .foregroundStyle(Color.steveText)
        .background { Color.steveNavy.opacity(model.settings.glassAlpha) }
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
        window.titleVisibility = .hidden // как в макете: только кнопки окна, без надписи
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior.insert(.fullScreenPrimary)
    }
}
