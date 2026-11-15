import AppKit
import SwiftUI

/// Цвета и стеклянные поверхности в стиле Liquid Glass, как в макете.
extension Color {
    static let steveText = Color(red: 244 / 255, green: 246 / 255, blue: 1)
    static let steveMuted = Color(red: 180 / 255, green: 187 / 255, blue: 214 / 255)
    static let steveAccent = Color(red: 143 / 255, green: 169 / 255, blue: 1)
    static let steveAccent2 = Color(red: 196 / 255, green: 160 / 255, blue: 1)
    static let steveOK = Color(red: 110 / 255, green: 231 / 255, blue: 160 / 255)
    static let steveWarn = Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255)
    static let steveDanger = Color(red: 1, green: 95 / 255, blue: 87 / 255)
    static let steveNavy = Color(red: 24 / 255, green: 28 / 255, blue: 52 / 255)
}

/// Блик по краю стекла: ярче сверху, мягче снизу.
private let rimGradient = LinearGradient(
    colors: [Color.white.opacity(0.55), Color.white.opacity(0.08)],
    startPoint: .top, endPoint: .bottom
)

private let controlFill = LinearGradient(
    colors: [Color.white.opacity(0.2), Color.white.opacity(0.07)],
    startPoint: .topLeading, endPoint: .bottomTrailing
)

private let plateFill = LinearGradient(
    colors: [Color.white.opacity(0.14), Color.white.opacity(0.05)],
    startPoint: .topLeading, endPoint: .bottomTrailing
)

extension View {
    /// Крупная стеклянная поверхность (окно, всплывающее окно). `alpha` задаёт ползунок прозрачности.
    func glassSurface(alpha: Double, cornerRadius: CGFloat = 22) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.steveNavy.opacity(alpha))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(rimGradient, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Кнопка, поле или плашка поверх поверхности.
    func glassControl(cornerRadius: CGFloat = 14, highlighted: Bool = false) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(controlFill)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.white.opacity(highlighted ? 0.18 : 0)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(rimGradient.opacity(0.9), lineWidth: 1)
        }
    }

    /// Плашка настройки: отдельный кусочек стекла вместо строки с разделителем.
    func glassPlate(cornerRadius: CGFloat = 16) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(plateFill))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
    }
}

/// Круглая кнопка-иконка из стекла.
struct GlassIconButton: View {
    let symbol: String
    var size: CGFloat = 42
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(Color.steveText)
                .frame(width: size, height: size)
                .glassControl(cornerRadius: size * 0.33, highlighted: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}



/// Настоящее стекло окна: размытие того, что лежит под окном на рабочем столе.
/// Окно прозрачное, поэтому стекло показывает рабочий стол, а не серую заливку.
struct WindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        return effect
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
