import Foundation
import Observation
import SteveCore

/// Жизнь Стива: какая анимация играет, спит ли он, куда смотрит.
/// В покое он моргает раз в 3–6 секунд, раз в 40 секунд делает что-нибудь ещё и засыпает после 5 минут без запросов.
/// Для проверки время можно сократить переменными окружения STEVE_SLEEP_SECONDS и STEVE_IDLE_SECONDS.
@MainActor
@Observable
final class CharacterController {
    private(set) var animation: SteveAnimation?
    private(set) var startedAt = Date()
    private(set) var isAsleep = false
    var followX = 0.0

    private var clearTask: Task<Void, Never>?
    private var lastActivity = Date()
    private var isBusy: () -> Bool = { false }

    private let sleepAfter: TimeInterval
    private let idleEvery: TimeInterval
    private static let idleAnimations: [SteveAnimation] = [
        .lookLeft, .lookLeft, .lookRight, .lookRight, .lookAround, .lookAround, .hop, .hop, .wiggle, .wiggle, .wave, .yawn,
    ]

    init() {
        let env = ProcessInfo.processInfo.environment
        sleepAfter = env["STEVE_SLEEP_SECONDS"].flatMap(Double.init) ?? 300
        idleEvery = env["STEVE_IDLE_SECONDS"].flatMap(Double.init) ?? 40
    }

    /// Кадр в момент `date`: поза Стива для рисования.
    func frame(at date: Date) -> SteveFrame {
        SteveAnimator.frame(
            animation: animation,
            asleep: isAsleep,
            elapsed: date.timeIntervalSince(startedAt),
            clock: date.timeIntervalSinceReferenceDate,
            followX: followX
        )
    }

    // MARK: - Управление анимациями

    /// Играет одиночную анимацию или держит состояние, если у анимации нет длительности.
    func play(_ next: SteveAnimation) {
        clearTask?.cancel()
        animation = next
        startedAt = Date()
        guard let duration = next.duration else { return }
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.06))
            guard !Task.isCancelled else { return }
            self?.animation = nil
        }
    }

    func clear() {
        clearTask?.cancel()
        animation = nil
    }

    /// Поза, соответствующая состоянию ассистента.
    func apply(status: AssistantStatus) {
        switch status {
        case .idle:
            if animation?.duration == nil { clear() }
        case .listening: hold(.listen)
        case .thinking: play(.think)
        case .working: hold(.work)
        case .speaking: hold(.talk)
        }
    }

    private func hold(_ state: SteveAnimation) {
        wake(stretch: false)
        play(state)
    }

    /// Глаза следят за кареткой: вниз и слева направо вдоль строки.
    func follow(column: Int) {
        followX = -6 + 12 * min(1, Double(column) / 36)
        if animation != .follow { play(.follow) }
    }

    func stopFollowing() {
        if animation == .follow { clear() }
    }

    // MARK: - Сон

    func sleep() {
        clear()
        isAsleep = true
    }

    func wake(stretch: Bool = true) {
        lastActivity = Date()
        guard isAsleep else { return }
        isAsleep = false
        if stretch { play(.stretch) }
    }

    /// Любой запрос к Стиву: будит его и сбрасывает таймер сна.
    func touch() {
        wake()
        lastActivity = Date()
    }

    // MARK: - Жизнь в покое

    func startIdleLife(isBusy: @escaping () -> Bool) {
        self.isBusy = isBusy
        Task { [weak self] in await self?.blinkLoop() }
        Task { [weak self] in await self?.directorLoop() }
        Task { [weak self] in await self?.sleepWatcher() }
    }

    private var canPlayIdle: Bool { !isAsleep && animation == nil && !isBusy() }

    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 3...6)))
            if canPlayIdle { play(.blink) }
        }
    }

    private func directorLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(idleEvery))
            guard canPlayIdle else { continue }
            let untilSleep = sleepAfter - Date().timeIntervalSince(lastActivity)
            let yawnNow = untilSleep < 60 && Bool.random()
            play(yawnNow ? .yawn : (Self.idleAnimations.randomElement() ?? .blink))
        }
    }

    private func sleepWatcher() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            let holding = animation != nil && animation?.duration == nil
            if !isAsleep, !holding, !isBusy(), Date().timeIntervalSince(lastActivity) > sleepAfter {
                sleep()
            }
        }
    }
}

enum AssistantStatus: Equatable {
    case idle, listening, thinking, working, speaking

    /// Подписи те же, что в макете: «Отвечает» нет, пока ответ отправляется, статус «Выполняет».
    var label: String {
        switch self {
        case .idle: return "Готов"
        case .listening: return "Слушает"
        case .thinking: return "Думает"
        case .working, .speaking: return "Выполняет"
        }
    }
}
