import SwiftUI

/// Экран диалога: Стив, статус, сообщения и строка ввода.
struct ChatView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            // сообщения идут на всю высоту и уходят вверх прямо за Стива: там они размываются и бледнеют
            ZStack(alignment: .top) {
                MessageList(messages: model.messages, showCommands: model.settings.showCommands, compact: false,
                            isThinking: model.status == .thinking || model.status == .working, topInset: heroHeight)
                hero
                    .background(GeometryReader { proxy in Color.clear.preference(key: HeroHeightKey.self, value: proxy.size.height) })
            }
            .onPreferenceChange(HeroHeightKey.self) { heroHeight = max(Self.minHeroHeight, $0) }
            AttachmentsBar()
            ComposerView(compact: false)
        }
        // файлы можно просто перетащить в окно
        .dropDestination(for: URL.self) { urls, _ in
            model.attach(urls.filter(\.isFileURL))
            return true
        }
    }

    /// Высота Стива со статусом и панелями: с неё начинаются сообщения, чтобы панели не лежали поверх текста.
    /// Выше этой линии сообщения при прокрутке уходят за Стива и размываются.
    static let minHeroHeight: CGFloat = 164
    @State private var heroHeight: CGFloat = 164

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

            PanelsView(compact: false)
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
    /// Отступ сверху под Стива: сообщения начинаются ниже, а при прокрутке уходят за него и размываются.
    var topInset: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: compact ? 6 : 10) {
                    ForEach(messages) { message in
                        // плавное появление: пузырь вырастает из угла, откуда он «отправлен»
                        bubble(message).id(message.id)
                            .visualEffect { content, proxy in
                                let blurred = topInset > 0 ? min(1, max(0, (topInset - proxy.frame(in: .named("msgScroll")).minY) / topInset)) : 0
                                return content.blur(radius: blurred * 9).opacity(1 - blurred * 0.6)
                            }
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
                .padding(.top, compact ? 0 : max(12, topInset))
                .padding(.bottom, compact ? 0 : 12)
                Color.clear.frame(height: 1).id("end")
            }
            .defaultScrollAnchor(.bottom)
            .coordinateSpace(name: "msgScroll")
            // сообщения, уходящие вверх за Стива, плавно растворяются, а не обрезаются жёсткой линией
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: compact ? 18 : (topInset > 0 ? 10 : 36))
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: compact ? 8 : 12)
                }
            )
            .onChange(of: messages.count) { scrollToEnd(proxy) }
            .onChange(of: messages.last?.text) { scrollToEnd(proxy) }
            .onAppear { scrollToEnd(proxy) }
            .onChange(of: isThinking) { scrollToEnd(proxy) }
        }
    }

    /// Прокручивает чат к последнему сообщению. Ждём кадр, пока новый пузырь встанет в список, иначе прокрутка промахивается.
    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        for delay in [0.0, 0.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
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
                GlassIconButton(symbol: "paperclip") { chooseFiles() }
                    .help("Прикрепить файлы: потом скажи, в какую папку их положить")
                MicButton()
                    .help("Сказать голосом")
            }
        }
        .padding(.top, compact ? 0 : 10)
        .padding(.bottom, compact ? 0 : 10) // единый отступ 10 до края окна, как у боковой панели
    }

    /// Выбор файлов и папок: они появляются над строкой ввода, дальше можно сказать «положи их в папку Работа».
    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Прикрепить файлы"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return }
        model.attach(panel.urls)
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


/// Таймеры и секундомер под Стивом: если помещаются, стоят в одну строку по центру, иначе переносятся на следующую.
struct PanelsView: View {
    let compact: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        CenteredFlow(spacing: 8) {
            ForEach(model.activeTimers) { timer in
                TimerRow(timer: timer, compact: compact)
            }
            if model.stopwatch != nil {
                StopwatchRow(compact: compact)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.activeTimers.count)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.stopwatch != nil)
    }
}

/// Раскладка: элементы по строкам, каждая строка по центру. Высота растёт только когда строка не помещается.
struct CenteredFlow: Layout {
    var spacing: CGFloat = 8

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var used: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if used > 0, used + spacing + size.width > width { rows.append([]); used = 0 }
            rows[rows.count - 1].append(index)
            used += (used > 0 ? spacing : 0) + size.width
        }
        return rows.filter { !$0.isEmpty }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        let laid = rows(subviews, width: width)
        let heights = laid.map { row in row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0 }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, laid.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
            let total = sizes.map(\.width).reduce(0, +) + spacing * CGFloat(row.count - 1)
            var x = bounds.minX + (bounds.width - total) / 2
            for (offset, index) in row.enumerated() {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += sizes[offset].width + spacing
            }
            y += (sizes.map(\.height).max() ?? 0) + spacing
        }
    }
}

/// Один таймер: обратный отсчёт, полоса и две кнопки.
struct TimerRow: View {
    let timer: ActiveTimer
    let compact: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
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
                .frame(width: compact ? 40 : 90, height: 6)
                // две кнопки: пауза или продолжение, и остановка
                PanelButton(symbol: paused ? "play.fill" : "pause.fill", help: paused ? "Продолжить" : "Пауза") { model.pauseTimer(timer.id) }
                PanelButton(symbol: "stop.fill", help: "Остановить") { model.stopTimer(timer.id) }
            }
            .panelBackground()
        }
        .fixedSize()
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// Секундомер как в «Часах» на Mac: время с сотыми долями, кнопка круга, пауза и стоп.
/// Под временем видны три круга: текущий и два предыдущих, без цветовых отметок.
struct StopwatchRow: View {
    let compact: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        if let stopwatch = model.stopwatch {
            TimelineView(.periodic(from: .now, by: 0.05)) { context in
                let paused = stopwatch.pausedElapsed != nil
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "stopwatch").font(.system(size: 13))
                        Text(ActiveStopwatch.format(stopwatch.elapsed(at: context.date)))
                            .font(.system(size: compact ? 15 : 18, weight: .semibold).monospacedDigit())
                            .opacity(paused ? 0.6 : 1)
                        PanelButton(symbol: "flag.fill", help: "Засечь круг") { model.lapStopwatch() }
                            .opacity(paused ? 0.4 : 1)
                            .disabled(paused)
                        PanelButton(symbol: paused ? "play.fill" : "pause.fill", help: paused ? "Продолжить" : "Пауза") { model.pauseStopwatch() }
                        PanelButton(symbol: "stop.fill", help: "Остановить") { model.stopStopwatch() }
                    }
                    laps(stopwatch, now: context.date)
                }
                .panelBackground()
            }
            .fixedSize()
        }
    }

    /// Три последних круга: текущий идёт первой строкой, между строками тонкие линии.
    @ViewBuilder
    private func laps(_ stopwatch: ActiveStopwatch, now: Date) -> some View {
        if !stopwatch.laps.isEmpty {
            let splits = stopwatch.splits
            let current = stopwatch.elapsed(at: now) - (stopwatch.laps.last ?? 0)
            let previous = Array(splits.enumerated().reversed().prefix(2))
            VStack(spacing: 0) {
                row(number: splits.count + 1, time: current)
                ForEach(previous, id: \.offset) { index, split in
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                    row(number: index + 1, time: split)
                }
            }
            .frame(width: 230)
        }
    }

    private func row(number: Int, time: TimeInterval) -> some View {
        HStack {
            Text("Круг \(number)")
            Spacer(minLength: 8)
            Text(ActiveStopwatch.format(time)).monospacedDigit()
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.steveText)
        .frame(height: 26)
    }
}

private struct PanelButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.16)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private extension View {
    /// Плотная стеклянная плашка: сообщения за ней не просвечивают.
    func panelBackground() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .glassControl(cornerRadius: 14)
    }
}

private struct HeroHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
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





/// Прикреплённые файлы над строкой ввода: значок, имя и крестик, чтобы убрать.
struct AttachmentsBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.attachments, id: \.self) { url in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                            Text(url.lastPathComponent).font(.system(size: 12.5)).lineLimit(1).frame(maxWidth: 180)
                            Button { model.removeAttachment(url) } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18)
                                    .background(Circle().fill(Color.white.opacity(0.16)))
                            }
                            .buttonStyle(.plain)
                            .help("Открепить")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassControl(cornerRadius: 12)
                    }
                }
            }
            .padding(.top, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
