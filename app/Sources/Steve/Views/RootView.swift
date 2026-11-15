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
            .ignoresSafeArea(edges: .top) // шапки у окна нет: Стив поднят к верхнему краю

            SidebarView()
                .padding(.leading, 4)
                .padding(.top, 4)
                .padding(.bottom, 10)
                .ignoresSafeArea(edges: .top)
        }
        .foregroundStyle(Color.steveText)
        .background { Color.steveNavy.opacity(model.settings.glassAlpha).ignoresSafeArea() }
        .preferredColorScheme(.dark)
    }
}

/// Настраивает обычное окно macOS: кнопки закрыть, свернуть и на весь экран, заголовок «Стив»,
/// за который окно можно перетаскивать, и растягивание за любой край.
private struct WindowConfigurator: NSViewRepresentable {
    @MainActor private static var shifted: [ObjectIdentifier: NSPoint] = [:]

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.title = "Стив"
        window.titleVisibility = .hidden // надписи нет, остаются системные кнопки окна
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true // окно можно двигать за любое пустое место
        window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.isOpaque = false
        window.backgroundColor = .clear
        installGlass(in: window)
        placeWindowButtons(in: window)
        // система возвращает кнопки на место при смене размера окна: ставим их заново
        for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didExitFullScreenNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { placeWindowButtons(in: window) }
            }
        }
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

    /// Опускает системные кнопки окна на 3 пункта: так вокруг них в боковой панели одинаковые отступы.
    @MainActor
    private func placeWindowButtons(in window: NSWindow) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(kind) else { continue }
            let key = ObjectIdentifier(button)
            if let done = Self.shifted[key], done == button.frame.origin { continue } // уже на своём месте
            var origin = button.frame.origin
            origin.y -= button.superview?.isFlipped == true ? -3 : 3
            button.setFrameOrigin(origin)
            Self.shifted[key] = origin
        }
    }
}
