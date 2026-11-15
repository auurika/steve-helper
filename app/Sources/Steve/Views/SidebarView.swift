import SwiftUI

/// Боковая панель: парящая стеклянная плашка. В покое видны только значки, при наведении она выезжает.
/// После выбора пункта сразу сворачивается и раскрывается снова, когда курсор уйдёт и вернётся.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var isHovering = false
    @State private var isLocked = false
    @State private var hoveredItem: AppSection?

    private struct Item: Identifiable {
        let section: AppSection
        let symbol: String
        let title: String
        var id: String { title }
    }

    private let items = [
        Item(section: .chat, symbol: "bubble.left", title: "Диалог"),
        Item(section: .presets, symbol: "puzzlepiece", title: "Пресеты"),
        Item(section: .settings, symbol: "gearshape", title: "Настройки"),
    ]

    private var isExpanded: Bool { (isHovering && !isLocked) || model.previewSidebarExpanded }

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            WindowButtons()
                .padding(.top, 6)
                .padding(.bottom, 8)
            ForEach(items) { item in
                row(for: item)
            }
            Spacer(minLength: 0)
            networkStatus
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(width: isExpanded ? 180 : 56)
        .frame(maxHeight: .infinity)
        .glassControl(cornerRadius: 18) // тот же цвет и рамка, что у поля ввода
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
        .animation(.easeInOut(duration: 0.22), value: isExpanded)
        .onHover { hovering in
            isHovering = hovering
            if !hovering { isLocked = false }
        }
    }

    private func row(for item: Item) -> some View {
        let isSelected = model.section == item.section
        let isHovered = hoveredItem == item.section
        return Button {
            model.section = item.section
            isLocked = true // после выбора панель сразу сворачивается
        } label: {
            // выделяется вся строка: в покое это квадрат 40 на 40, у раскрытой панели квадрат с подписью
            HStack(spacing: 0) {
                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 40, height: 40)
                if isExpanded {
                    Text(item.title)
                        .lineLimit(1)
                        .padding(.trailing, 14)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: isExpanded ? .infinity : 40, alignment: .leading)
            .frame(height: 40)
            .foregroundStyle(isSelected || isHovered ? Color.white : Color.steveMuted)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(isHovered ? 0.46 : (isSelected ? 0.32 : 0)), Color.white.opacity(isHovered ? 0.2 : (isSelected ? 0.12 : 0))],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredItem = hovering ? item.section : (hoveredItem == item.section ? nil : hoveredItem) }
        .help(item.title)
    }

    /// Офлайн жёлтый, онлайн зелёный. Стив работает без сети в любом случае.
    private var networkStatus: some View {
        let online = model.network.isOnline
        let color = online ? Color.steveOK : Color.steveWarn
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.5), radius: 3)
            if isExpanded {
                Text(online ? "Работает онлайн" : "Работает офлайн")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

/// Кнопки окна в боковой панели: закрыть, свернуть, на весь экран. Расстояния такие же, как у остальных значков.
private struct WindowButtons: View {
    @State private var hovering = false

    private struct Button: Identifiable {
        let id: String
        let color: Color
        let glyph: String
        let action: (NSWindow) -> Void
    }

    private let buttons = [
        Button(id: "close", color: Color(red: 1, green: 0.37, blue: 0.34), glyph: "xmark") { $0.performClose(nil) },
        Button(id: "min", color: Color(red: 1, green: 0.74, blue: 0.18), glyph: "minus") { $0.miniaturize(nil) },
        Button(id: "zoom", color: Color(red: 0.16, green: 0.78, blue: 0.25), glyph: "arrow.up.left.and.arrow.down.right") { $0.toggleFullScreen(nil) },
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(buttons) { button in
                SwiftUI.Button {
                    if let window = NSApp.keyWindow ?? NSApp.mainWindow { button.action(window) }
                } label: {
                    Circle()
                        .fill(button.color)
                        .frame(width: 12, height: 12)
                        .overlay {
                            Image(systemName: button.glyph)
                                .font(.system(size: 6, weight: .heavy))
                                .foregroundStyle(Color.black.opacity(0.55))
                                .opacity(hovering ? 1 : 0)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(button.id == "close" ? "Закрыть" : (button.id == "min" ? "Свернуть" : "На весь экран"))
            }
        }
        .onHover { hovering = $0 }
    }
}
