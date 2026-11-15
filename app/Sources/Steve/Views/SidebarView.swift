import SwiftUI

/// Боковая панель: парящая стеклянная плашка. В покое видны только значки, при наведении она выезжает.
/// После выбора пункта остаётся раскрытой и сворачивается, только когда курсор уходит с панели.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var isHovering = false
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

    private var isExpanded: Bool { isHovering || model.previewSidebarExpanded }

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            // кнопки окна привязаны к левому краю панели и не двигаются, когда она раскрывается
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 12)
                .overlay(alignment: .leading) {
                    WindowButtons().fixedSize().offset(x: -4)
                }
                .padding(.bottom, 12)
            ForEach(items) { item in
                row(for: item)
            }
            Spacer(minLength: 0)
            networkStatus
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(width: isExpanded ? 190 : 68)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous)) // размытие: текст под панелью не просвечивает
        .glassControl(cornerRadius: 22) // тот же цвет и рамка, что у поля ввода
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
        .animation(.easeInOut(duration: 0.22), value: isExpanded)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func row(for item: Item) -> some View {
        let isSelected = model.section == item.section
        let isHovered = hoveredItem == item.section
        return Button {
            model.section = item.section
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
        // индикатор привязан к левому краю: при раскрытии панели он остаётся на месте, добавляется только подпись
        return Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 8)
            .overlay(alignment: .leading) {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 8, height: 8)
                        .shadow(color: color.opacity(0.5), radius: 3)
                    if isExpanded {
                        Text(online ? "Работает онлайн" : "Работает офлайн")
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                .fixedSize()
                .foregroundStyle(color)
                .padding(.leading, 16)
            }
            .padding(.vertical, 9)
    }
}

/// Кнопки окна: закрыть, свернуть, на весь экран. Нарисованы в панели, поэтому всегда лежат под курсором.
private struct WindowButtons: View {
    @State private var hovering = false

    private struct Item: Identifiable {
        let id: String
        let color: Color
        let glyph: String
        let label: String
        let action: (NSWindow) -> Void
    }

    private let items = [
        Item(id: "close", color: Color(red: 1, green: 0.37, blue: 0.34), glyph: "xmark", label: "Закрыть") { $0.performClose(nil) },
        Item(id: "min", color: Color(red: 1, green: 0.74, blue: 0.18), glyph: "minus", label: "Свернуть") { $0.miniaturize(nil) },
        Item(id: "zoom", color: Color(red: 0.16, green: 0.78, blue: 0.25), glyph: "arrow.up.left.and.arrow.down.right", label: "На весь экран") { $0.toggleFullScreen(nil) },
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    // окно приложения: то, где лежит эта панель, а не окно меню-бара
                    let window = NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) && !String(describing: type(of: $0)).contains("MenuBarExtra") }
                    if let window = window ?? NSApp.keyWindow { item.action(window) }
                } label: {
                    Circle()
                        .fill(item.color)
                        .frame(width: 12, height: 12)
                        .overlay {
                            Image(systemName: item.glyph)
                                .font(.system(size: 6, weight: .heavy))
                                .foregroundStyle(Color.black.opacity(0.55))
                                .opacity(hovering ? 1 : 0)
                        }
                        .padding(3) // зона нажатия больше самого кружка
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
            }
        }
        .padding(-3)
        .onHover { hovering = $0 }
    }
}
