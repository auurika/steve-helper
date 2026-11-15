import Foundation

/// Анимации Стива. Те же, что в макете (mockup/styles/steve.css).
public enum SteveAnimation: String, CaseIterable {
    case blink, lookLeft, lookRight, lookAround, hop, wiggle, wave, yawn
    case think, happy, surprise, dance, stretch
    case listen, work, talk, follow

    /// Длительность одиночной анимации. Nil — состояние, которое держится, пока его не отменят.
    public var duration: TimeInterval? {
        switch self {
        case .blink: return 0.3
        case .lookLeft, .lookRight: return 1.8
        case .lookAround: return 3.6
        case .hop: return 1.0
        case .wiggle: return 1.4
        case .wave: return 2.2
        case .yawn: return 2.6
        case .think: return 2.8
        case .happy: return 2.0
        case .surprise: return 1.8
        case .dance: return 3.2
        case .stretch: return 2.2
        case .listen, .work, .talk, .follow: return nil
        }
    }
}

/// Поза Стива в один момент времени. Рисует её интерфейс, а считает этот файл, поэтому поза проверяется тестами.
public struct SteveFrame: Equatable {
    public var rootOffsetY = 0.0
    public var bodyScaleX = 1.0
    public var bodyScaleY = 1.0
    public var bodyRotation = 0.0           // градусы, вокруг основания тела
    public var eyeScaleX = 1.0
    public var eyeScaleY = 1.0
    public var eyeOffsetX = 0.0
    public var eyeOffsetY = 0.0
    public var legAngles = [0.0, 0.0, 0.0, 0.0]
    public var mouthScaleY = 0.0            // 0 — рот закрыт
    public var thoughtDots = 0              // 0...3
    public var showBang = false
    public var showSparkles = false
    public var notes: [Note] = []
    public var letters: [FloatingLetter] = [] // буквы Z во сне

    public struct Note: Equatable {
        public var progress: Double          // 0...1: взлёт ноты
        public var anchor: Int               // 0 — справа, 1 — слева
    }

    public struct FloatingLetter: Equatable {
        public var progress: Double          // 0...1: от головы вверх и вправо
    }

    public init() {}
}

public enum SteveAnimator {
    private static let bobPeriod = 0.9       // покачивание в покое: шаг раз в 0.9 с
    private static let zPeriod = 3.6

    /// Поза в момент `elapsed` секунд от старта анимации. Движение ступенчатое, как у пиксельной графики.
    public static func frame(animation: SteveAnimation?, asleep: Bool, elapsed: Double, clock: Double, followX: Double = 0) -> SteveFrame {
        var frame = SteveFrame()

        if asleep {
            return sleepingFrame(clock: clock)
        }

        frame.rootOffsetY = Int(clock / bobPeriod) % 2 == 0 ? 0 : -4
        guard let animation else { return frame }

        let duration = animation.duration ?? 1
        let phase = animation.duration == nil ? elapsed : min(elapsed, duration)
        let p = animation.duration == nil ? 0 : phase / duration // 0...1 для одиночных
        let beat = { (period: Double) in Int(elapsed / period) % 2 == 0 } // чётная половина периода

        switch animation {
        case .blink:
            frame.eyeScaleY = (0.35..<0.7).contains(p) ? 0.1 : 1

        case .lookLeft:
            frame.eyeOffsetX = (0.15..<0.8).contains(p) ? -7 : 0
        case .lookRight:
            frame.eyeOffsetX = (0.15..<0.8).contains(p) ? 7 : 0
        case .lookAround:
            switch p {
            case 0.10..<0.38: frame.eyeOffsetX = -7
            case 0.38..<0.66: frame.eyeOffsetX = 7
            case 0.66..<0.84: frame.eyeOffsetY = -6
            default: break
            }

        case .hop:
            applyHop(to: &frame, p: p)

        case .wiggle:
            let slot = Int(p * 8)
            frame.bodyRotation = [0, -5, 5, -5, 5, -5, 5, -5, 0][min(slot, 8)]

        case .wave:
            frame.eyeScaleY = 0.55
            let slot = Int(p * 12)
            frame.legAngles[3] = slot % 4 == 0 ? -70 : (slot % 4 == 2 ? -35 : (slot % 2 == 1 ? -70 : 0))
            if p > 0.95 { frame.legAngles[3] = 0 }

        case .yawn:
            if (0.2..<0.8).contains(p) { frame.eyeScaleY = 0.15 }
            switch p {
            case 0.2..<0.35: frame.mouthScaleY = 1.2; frame.bodyScaleY = 1.03
            case 0.35..<0.6: frame.mouthScaleY = 3.4; frame.bodyScaleX = 1.03; frame.bodyScaleY = 1.08
            case 0.6..<0.75: frame.mouthScaleY = 3.4; frame.bodyScaleY = 1.08
            case 0.75..<0.85: frame.mouthScaleY = 1.2; frame.bodyScaleY = 1.02
            default: break
            }

        case .think:
            if (0.12..<0.88).contains(p) {
                frame.eyeOffsetX = -6
                frame.eyeOffsetY = -7
                frame.bodyRotation = -3
            }
            frame.thoughtDots = p < 0.13 ? 0 : (p < 0.33 ? 1 : (p < 0.53 ? 2 : (p < 0.93 ? 3 : 0)))

        case .happy:
            frame.eyeScaleY = 0.3
            applyHop(to: &frame, p: (p * 2).truncatingRemainder(dividingBy: 1))
            frame.showSparkles = Int(elapsed / 0.25) % 2 == 0

        case .surprise:
            frame.eyeScaleX = 1.35
            frame.eyeScaleY = 1.35
            frame.legAngles[0] = -8
            frame.legAngles[3] = 8
            frame.showBang = (0.05..<0.85).contains(p)
            switch p {
            case 0.06..<0.25: frame.rootOffsetY = -12
            case 0.25..<0.40: frame.rootOffsetY = -4
            default: frame.rootOffsetY = 0
            }

        case .dance:
            let swing = beat(0.4)
            frame.bodyRotation = swing ? -5 : 5
            frame.rootOffsetY = Int(elapsed / 0.2) % 2 == 0 ? -8 : 0
            frame.legAngles = swing ? [14, -14, 14, -14] : [-14, 14, -14, 14]
            frame.notes = [
                .init(progress: elapsed.truncatingRemainder(dividingBy: 1.6) / 1.6, anchor: 0),
                .init(progress: (elapsed + 0.8).truncatingRemainder(dividingBy: 1.6) / 1.6, anchor: 1),
            ]

        case .stretch:
            switch p {
            case 0.10..<0.45: frame.bodyScaleX = 0.9; frame.bodyScaleY = 1.16; frame.legAngles[0] = -16; frame.legAngles[3] = 16
            case 0.45..<0.55: frame.bodyScaleX = 0.9; frame.bodyScaleY = 1.16
            case 0.55..<0.70: frame.bodyScaleX = 1.06; frame.bodyScaleY = 0.96
            default: break
            }
            if (0.45..<0.65).contains(p) { frame.mouthScaleY = 2.2 }

        case .listen:
            frame.eyeScaleX = 1.2
            frame.eyeScaleY = 1.2
            frame.bodyRotation = beat(0.8) ? -2.5 : 2.5

        case .work:
            frame.eyeScaleY = 0.6
            frame.rootOffsetY = Int(elapsed / 0.2) % 2 == 0 ? 0 : -3
            let odd = Int(elapsed / 0.2) % 2 == 0
            frame.legAngles = odd ? [14, -14, 14, -14] : [-14, 14, -14, 14]

        case .talk:
            frame.mouthScaleY = Int(elapsed / 0.18) % 2 == 0 ? 1.2 : 3

        case .follow:
            frame.eyeScaleX = 1.1
            frame.eyeScaleY = 1.1
            frame.eyeOffsetX = followX
            frame.eyeOffsetY = 4
        }
        return frame
    }

    private static func applyHop(to frame: inout SteveFrame, p: Double) {
        switch p {
        case 0.20..<0.35: frame.rootOffsetY = -10
        case 0.35..<0.50: frame.rootOffsetY = -22
        case 0.50..<0.65: frame.rootOffsetY = -10
        case 0.90...: frame.rootOffsetY = -5
        default: frame.rootOffsetY = 0
        }
        switch p {
        case 0.17..<0.20, 0.65..<0.79:
            frame.bodyScaleX = 1.1
            frame.bodyScaleY = 0.88
        case 0.20..<0.65:
            frame.bodyScaleX = 0.95
            frame.bodyScaleY = 1.06
        default: break
        }
    }

    /// Сон: глаза-черточки, лапки опущены, медленное дыхание и три буквы Z, поднимающиеся одна за другой.
    private static func sleepingFrame(clock: Double) -> SteveFrame {
        var frame = SteveFrame()
        frame.rootOffsetY = Int(clock / 1.6) % 2 == 0 ? 9 : 11
        frame.bodyScaleY = 0.95
        frame.eyeScaleY = 0.14
        frame.legAngles = [9, 3, -3, -9]
        frame.letters = (0..<3).compactMap { index in
            let local = (clock - Double(index) * 1.2).truncatingRemainder(dividingBy: zPeriod)
            let shifted = local < 0 ? local + zPeriod : local
            return clock >= Double(index) * 1.2 ? .init(progress: shifted / zPeriod) : nil
        }
        return frame
    }
}
