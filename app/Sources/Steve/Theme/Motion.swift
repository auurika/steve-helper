import SwiftUI

/// Единый язык движения приложения. Основан на правилах Apple для Liquid Glass: пружины вместо фиксированных кривых,
/// короткое закрытие, появление «из материала» (размытие, масштаб, прозрачность), всё можно прервать на полпути.
/// Оттуда же значения из макета: окно меню-бара выезжает за 0,42 с с лёгким перелётом, закрывается за 0,2 с.
enum Motion {
    /// Появление окон и панелей: пружина с небольшим перелётом, как `popover-in` в макете.
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.74)
    /// Переключение экранов и раскрытие боковой панели: мягкая пружина без перелёта.
    static let smooth = Animation.smooth(duration: 0.38)
    /// Быстрый отклик на наведение и нажатие.
    static let quick = Animation.snappy(duration: 0.2)
    /// Закрытие всегда короче открытия.
    static let close = Animation.easeIn(duration: 0.2)
}

/// Материализация: элемент проявляется из размытия, чуть увеличиваясь. При включённом «Уменьшении движения» остаётся только прозрачность.
struct Materialize: ViewModifier {
    let isActive: Bool
    var anchor: UnitPoint = .center
    var scale: CGFloat = 0.92
    var blur: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive && !reduceMotion ? scale : 1, anchor: anchor)
            .blur(radius: isActive && !reduceMotion ? blur : 0)
            .opacity(isActive ? 0 : 1)
    }
}

extension AnyTransition {
    /// Появление и исчезновение «из материала».
    static func materialize(anchor: UnitPoint = .center, scale: CGFloat = 0.92, blur: CGFloat = 10) -> AnyTransition {
        .modifier(active: Materialize(isActive: true, anchor: anchor, scale: scale, blur: blur),
                  identity: Materialize(isActive: false, anchor: anchor, scale: scale, blur: blur))
    }
}

/// Кнопка слегка «вдавливается» под пальцем и упруго возвращается.
struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.93

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
