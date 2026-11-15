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
        VStack(alignment: .leading, spacing: 6) {
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
        .background {
            // в покое: светлое стекло поверх окна, как в макете; при раскрытии плотнее, чтобы подписи читались
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            ZStack {
                if isExpanded { shape.fill(.ultraThinMaterial) }
                shape.fill(isExpanded
                           ? AnyShapeStyle(Color(red: 26 / 255, green: 30 / 255, blue: 60 / 255).opacity(0.92))
                           : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.1), .white.opacity(0.2)],
                                                          startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
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
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                if isExpanded {
                    Text(item.title)
                        .lineLimit(1)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected || isHovered ? Color.white : Color.steveMuted)
            .padding(11)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(isHovered ? 0.46 : (isSelected ? 0.32 : 0)), Color.white.opacity(isHovered ? 0.2 : (isSelected ? 0.12 : 0))],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5)
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

