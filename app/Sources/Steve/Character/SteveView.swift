import SwiftUI
import SteveCore

/// Стив, который живёт: перерисовывается 12 раз в секунду (ступенчато, как пиксельная графика).
struct SteveView: View {
    let controller: CharacterController

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            SteveCanvas(frame: controller.frame(at: timeline.date))
        }
    }
}

/// Квадратное кольцо, которое расходится от Стива, пока он слушает. Стартует снаружи от Стива и не заходит на него.
struct ListeningRing: View {
    var isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: !isActive)) { timeline in
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                // 6 ступеней за 1.2 с: кольцо растёт от 1 до 1.55 и гаснет
                let step = Double(Int(timeline.date.timeIntervalSinceReferenceDate / 0.2) % 6)
                let progress = step / 5
                Rectangle()
                    .stroke(Color(red: 196 / 255, green: 160 / 255, blue: 1), lineWidth: 2)
                    .frame(width: side * 0.76, height: side * 0.76)
                    .scaleEffect(1 + 0.55 * progress)
                    .opacity(isActive ? 0.8 * (1 - progress) : 0)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.61) // центр тела Стива
            }
        }
        .allowsHitTesting(false)
    }
}
