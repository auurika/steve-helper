import SwiftUI
import SteveCore

/// Рисует Стива по готовой позе. Все координаты те же, что в SVG макета (область 128×150, начало по Y = -30).
struct SteveCanvas: View {
    let frame: SteveFrame
    /// Крупный план для значка в меню-баре: меньше запаса вокруг Стива, поэтому он выглядит больше,
    /// а эффекты (Z, мысли, восклицание) укорочены и остаются внутри рамки.
    var isTiny = false

    private var viewport: CGRect {
        isTiny ? CGRect(x: 8, y: -14, width: 112, height: 124) : CGRect(x: 0, y: -30, width: 128, height: 150)
    }

    private static let body = Color(red: 176 / 255, green: 124 / 255, blue: 217 / 255)
    private static let eyes = Color(red: 31 / 255, green: 31 / 255, blue: 31 / 255)
    private static let legs: [CGRect] = [
        CGRect(x: 28, y: 72, width: 12, height: 24),
        CGRect(x: 48, y: 72, width: 12, height: 32),
        CGRect(x: 68, y: 72, width: 12, height: 26),
        CGRect(x: 88, y: 72, width: 12, height: 28),
    ]
    private static let eyeRects = [CGRect(x: 46, y: 50, width: 8, height: 12), CGRect(x: 74, y: 50, width: 8, height: 12)]
    private static let bodyPivot = CGPoint(x: 64, y: 104)

    var body: some View {
        Canvas { context, size in
            let area = viewport
            let scale = min(size.width / area.width, size.height / area.height)
            var space = context
            space.translateBy(x: (size.width - area.width * scale) / 2, y: (size.height - area.height * scale) / 2)
            space.scaleBy(x: scale, y: scale)
            space.translateBy(x: -area.minX, y: -area.minY)

            drawCharacter(in: space)
            drawEffects(in: space)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Сам Стив

    private func drawCharacter(in base: GraphicsContext) {
        var root = base
        root.translateBy(x: 0, y: frame.rootOffsetY)

        var body = root
        body.translateBy(x: Self.bodyPivot.x, y: Self.bodyPivot.y)
        body.rotate(by: .degrees(frame.bodyRotation))
        body.scaleBy(x: frame.bodyScaleX, y: frame.bodyScaleY)
        body.translateBy(x: -Self.bodyPivot.x, y: -Self.bodyPivot.y)

        for rect in [CGRect(x: 32, y: 20, width: 64, height: 8), CGRect(x: 24, y: 28, width: 80, height: 44)] {
            body.fill(Path(rect), with: .color(Self.body))
        }
        for (index, rect) in Self.legs.enumerated() {
            var leg = body
            leg.translateBy(x: rect.midX, y: rect.minY) // лапка качается от верха
            leg.rotate(by: .degrees(frame.legAngles[index]))
            leg.translateBy(x: -rect.midX, y: -rect.minY)
            leg.fill(Path(rect), with: .color(Self.body))
        }
        for rect in Self.eyeRects {
            var eye = body
            eye.translateBy(x: frame.eyeOffsetX, y: frame.eyeOffsetY)
            eye.translateBy(x: rect.midX, y: rect.midY)
            eye.scaleBy(x: frame.eyeScaleX, y: frame.eyeScaleY)
            eye.translateBy(x: -rect.midX, y: -rect.midY)
            eye.fill(Path(rect), with: .color(Self.eyes))
        }
        if frame.mouthScaleY > 0 {
            var mouth = body
            mouth.translateBy(x: 58, y: 64)
            mouth.scaleBy(x: 1, y: frame.mouthScaleY)
            mouth.fill(Path(CGRect(x: 0, y: 0, width: 12, height: 4)), with: .color(Self.eyes))
        }
    }

    // MARK: - Эффекты: мысли, восклицание, искры, ноты, буквы Z

    private func drawEffects(in context: GraphicsContext) {
        let white = Color(red: 244 / 255, green: 246 / 255, blue: 1)

        let dots = isTiny
            ? [CGRect(x: 100, y: 8, width: 4, height: 4), CGRect(x: 105, y: 0, width: 5, height: 5), CGRect(x: 111, y: -9, width: 7, height: 7)]
            : [CGRect(x: 100, y: 10, width: 4, height: 4), CGRect(x: 108, y: 0, width: 6, height: 6), CGRect(x: 118, y: -14, width: 10, height: 10)]
        for rect in dots.prefix(frame.thoughtDots) {
            context.fill(Path(rect), with: .color(white))
        }

        if frame.showBang {
            let yellow = Color(red: 1, green: 217 / 255, blue: 90 / 255)
            let stem = isTiny ? CGRect(x: 61, y: -12, width: 6, height: 13) : CGRect(x: 61, y: -22, width: 6, height: 16)
            let point = isTiny ? CGRect(x: 61, y: 4, width: 6, height: 5) : CGRect(x: 61, y: -2, width: 6, height: 6)
            context.fill(Path(stem), with: .color(yellow))
            context.fill(Path(point), with: .color(yellow))
        }

        if frame.showSparkles {
            let spark = Color(red: 1, green: 243 / 255, blue: 168 / 255)
            for center in [CGPoint(x: 17, y: 26), CGPoint(x: 111, y: 18), CGPoint(x: 115, y: 55)] {
                context.fill(Path(CGRect(x: center.x - 1, y: center.y - 4, width: 2, height: 8)), with: .color(spark))
                context.fill(Path(CGRect(x: center.x - 4, y: center.y - 1, width: 8, height: 2)), with: .color(spark))
            }
        }

        for note in frame.notes {
            let origin = note.anchor == 0 ? CGPoint(x: isTiny ? 96 : 104, y: 20) : CGPoint(x: isTiny ? 20 : 14, y: 24)
            let drift = CGPoint(x: (isTiny ? 6 : 16) * (note.anchor == 0 ? 1 : -1), y: isTiny ? 34 : 44)
            let rise = CGPoint(x: origin.x + drift.x * note.progress, y: origin.y - drift.y * note.progress)
            let alpha = note.progress < 0.15 ? note.progress / 0.15 : (note.progress > 0.85 ? (1 - note.progress) / 0.15 : 1)
            var layer = context
            layer.opacity = alpha
            for rect in [CGRect(x: 0, y: 8, width: 6, height: 6), CGRect(x: 4, y: 0, width: 2, height: 10), CGRect(x: 4, y: 0, width: 8, height: 2)] {
                layer.fill(Path(rect.offsetBy(dx: rise.x, dy: rise.y)), with: .color(white))
            }
        }

        let letterColor = Color(red: 232 / 255, green: 218 / 255, blue: 1)
        for letter in frame.letters {
            let p = letter.progress
            let size = isTiny ? 8 * (0.9 + 0.7 * p) : 10 * (0.9 + 1.6 * p)
            let alpha = p < 0.12 ? p / 0.12 : (p > 0.8 ? max(0, 1 - (p - 0.8) / 0.2) : 1)
            var layer = context
            layer.opacity = alpha
            let travel = isTiny ? CGPoint(x: 12, y: 20) : CGPoint(x: 34, y: 52)
            layer.translateBy(x: 92 + travel.x * p, y: 14 - travel.y * p - size)
            layer.scaleBy(x: size / 10, y: size / 10)
            for rect in [CGRect(x: 0, y: 0, width: 10, height: 2), CGRect(x: 6, y: 2, width: 2, height: 2), CGRect(x: 4, y: 4, width: 2, height: 2),
                         CGRect(x: 2, y: 6, width: 2, height: 2), CGRect(x: 0, y: 8, width: 10, height: 2)] {
                layer.fill(Path(rect), with: .color(letterColor))
            }
        }
    }
}
