import SwiftUI

/// Экран диалога: Стив, статус, сообщения и строка ввода.
struct ChatView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            hero
            MessageList(messages: model.messages, showCommands: model.settings.showCommands, compact: false, isThinking: model.status == .thinking || model.status == .working)
            ComposerView(compact: false)
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                SteveView(controller: model.character)
                ListeningRing(isActive: model.status == .listening)
            }
            .frame(width: 112, height: 112)
            .contentShape(Rectangle())
            .onTapGesture { model.toggleVoiceCapture() }
            .help("Нажми, чтобы говорить")

            Text(model.status.label)
                .font(.system(size: 13))
                .foregroundStyle(Color.steveMuted)
                .frame(height: 18)

            TimerPanel(compact: false)
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

/// Список сообщений. Пузырь по ширине текста, длинное переносится.
struct MessageList: View {
    let messages: [ChatMessage]
    let showCommands: Bool
    let compact: Bool
    /// Стив думает или выполняет: в конце списка показываются бегущие точки.
    var isThinking = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: compact ? 6 : 10) {
                    ForEach(messages) { message in
                        // плавное появление: пузырь вырастает из угла, откуда он «отправлен»
                        bubble(message).id(message.id)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.88, anchor: message.role == .user ? .bottomTrailing : .bottomLeading)
                                    .combined(with: .opacity).combined(with: .offset(y: 14)),
                                removal: .opacity))
                    }
                    if isThinking {
                        ThinkingBubble(compact: compact).id("thinking")
                            .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: messages.count)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isThinking)
                .padding(compact ? 10 : 0)
                .padding(.vertical, compact ? 0 : 12)
            }
            // сообщения, уходящие вверх за Стива, плавно растворяются, а не обрезаются жёсткой линией
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: compact ? 18 : 36)
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: compact ? 8 : 12)
                }
            )
            .onChange(of: messages.count) { scrollToEnd(proxy) }
            .onChange(of: isThinking) { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        let target: AnyHashable? = isThinking ? AnyHashable("thinking") : messages.last.map { AnyHashable($0.id) }
        guard let target else { return }
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .bottom) }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack(spacing: 0) {
            if isUser { Spacer(minLength: 40) }
            WidthLimited(maxWidth: 520) {
            VStack(alignment: .leading, spacing: 6) {
                Text(message.text)
                    .font(.system(size: compact ? 12.5 : 14))
                    .textSelection(.enabled)
                if showCommands, let tool = message.tool {
                    Text("tool · \(tool)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.steveOK)
                        .textSelection(.enabled)
                }
            }
            .foregroundStyle(Color.steveText)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 6 : 10)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous)
                    .fill(isUser ? Color.steveAccent.opacity(0.38) : Color.white.opacity(0.14))
            }
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            }
            }
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

/// Строка ввода: высота растёт только вместе с текстом, Enter отправляет, Shift+Enter переносит строку.
struct ComposerView: View {
    let compact: Bool
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: compact ? 8 : 10) {
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .font(.system(size: compact ? 13 : 14))
                .foregroundStyle(Color.steveText)
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 8 : 11)
                .frame(minHeight: compact ? 38 : 42, alignment: .leading) // текст по центру поля по вертикали
                .glassControl(cornerRadius: compact ? 12 : 14)
                .overlay(alignment: .leading) {
                    // своя подсказка: системная подсказка поля на тёмном стекле почти не видна
                    if text.isEmpty {
                        Text("Сообщение…")
                            .font(.system(size: compact ? 13 : 14))
                            .foregroundStyle(Color.steveMuted)
                            .padding(.horizontal, compact ? 10 : 12)
                            .allowsHitTesting(false)
                    }
                }
                .focused($focused)
                .onKeyPress(keys: [.return], phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        text += "\n"
                    } else {
                        send()
                    }
                    return .handled
                }
                .onSubmit { send() } // запасной путь: Return отправляет, даже если поле не отдало клавишу
                .onChange(of: model.voiceDraft) { if text != model.voiceDraft { text = model.voiceDraft } }
                .onChange(of: text) {
                    if model.voiceDraft != text { model.voiceDraft = text } // строка и черновик голоса всегда совпадают
                    model.typingChanged(text)
                }
                .onChange(of: focused) {
                    if !focused { model.typingChanged(text.isEmpty ? "" : text); if text.isEmpty { model.character.stopFollowing() } }
                }

            if compact {
                MicButton(size: 34)
            } else {
                GlassIconButton(symbol: "return") { send() }
                    .help("Отправить (Enter)")
                MicButton()
                    .help("Сказать голосом")
            }
        }
        .padding(.top, compact ? 0 : 10)
        .padding(.bottom, compact ? 0 : 10) // единый отступ 10 до края окна, как у боковой панели
    }

    private func send() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        text = ""
        Task { await model.ask(message, typed: true) }
    }
}

/// Ограничивает ширину содержимого, но не растягивает его: пузырь с короткой фразой остаётся коротким.
private struct WidthLimited: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let width = min(proposal.width ?? maxWidth, maxWidth)
        return subview.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}


/// Кнопка микрофона: во время записи краснеет, значок меняется, а кольцо вокруг пульсирует в такт голосу.
struct MicButton: View {
    var size: CGFloat = 42
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        let recording = model.isRecordingVoice
        Button { model.toggleVoiceCapture() } label: {
            ZStack {
                if recording {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.steveDanger.opacity(0.7), lineWidth: 2)
                        .scaleEffect(1 + CGFloat(model.voiceLevel) * 0.35)
                        .opacity(0.9 - Double(model.voiceLevel) * 0.4)
                        .animation(.easeOut(duration: 0.1), value: model.voiceLevel)
                }
                Image(systemName: recording ? "stop.fill" : "mic")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(recording ? Color.white : Color.steveText)
                    .frame(width: size, height: size)
                    .background {
                        if recording { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.steveDanger.opacity(0.75)) }
                    }
                    .glassControl(cornerRadius: 14, highlighted: hovering || recording)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(recording ? "Остановить запись" : "Сказать голосом")
    }
}


/// Идущие таймеры с обратным отсчётом и кнопкой отмены. Так таймер работает у любого пользователя,
/// даже если приложение «Часы» не удалось настроить.
struct TimerPanel: View {
    let compact: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.activeTimers.isEmpty {
            VStack(spacing: 6) {
                ForEach(model.activeTimers) { timer in
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        let paused = timer.pausedLeft != nil
                        let left = max(0, timer.pausedLeft ?? timer.end.timeIntervalSince(context.date))
                        HStack(spacing: 10) {
                            Image(systemName: "timer").font(.system(size: 13))
                            Text(Self.format(left))
                                .font(.system(size: compact ? 15 : 18, weight: .semibold).monospacedDigit())
                                .opacity(paused ? 0.6 : 1)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.18))
                                    Capsule().fill(Color.steveAccent)
                                        .frame(width: proxy.size.width * CGFloat(left / Double(max(1, timer.total))))
                                }
                            }
                            .frame(width: compact ? 50 : 110, height: 6)
                            // две кнопки: пауза или продолжение, и остановка с закрытием «Часов»
                            timerButton(paused ? "play.fill" : "pause.fill", help: paused ? "Продолжить" : "Пауза") { model.pauseTimer(timer.id) }
                            timerButton("stop.fill", help: "Остановить и закрыть") { model.stopTimer(timer.id) }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassControl(cornerRadius: 14)
                    }
                }
            }
        }
    }

    private func timerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.16)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}


/// Пузырь «Стив думает»: три точки по очереди набирают высоту.
struct ThinkingBubble: View {
    let compact: Bool

    var body: some View {
        HStack(spacing: 0) {
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        let wave = (sin(time * 5 - Double(index) * 0.9) + 1) / 2 // 0...1, точки сдвинуты по фазе
                        Circle()
                            .fill(Color.steveMuted)
                            .frame(width: 7, height: 7)
                            .scaleEffect(0.7 + 0.5 * wave)
                            .opacity(0.45 + 0.55 * wave)
                            .offset(y: -3 * wave)
                    }
                }
            }
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 9 : 13)
            .background(RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous).fill(Color.white.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            Spacer(minLength: 40)
        }
        .accessibilityLabel("Стив думает")
    }
}
