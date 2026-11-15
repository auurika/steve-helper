import SwiftUI

/// Экран диалога: Стив, статус, сообщения и строка ввода.
struct ChatView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            hero
            MessageList(messages: model.messages, showCommands: model.settings.showCommands, compact: false)
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
        }
        .padding(.top, 22)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

/// Список сообщений. Пузырь по ширине текста, длинное переносится.
struct MessageList: View {
    let messages: [ChatMessage]
    let showCommands: Bool
    let compact: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: compact ? 6 : 10) {
                    ForEach(messages) { message in
                        bubble(message).id(message.id)
                    }
                }
                .padding(compact ? 10 : 22)
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack(spacing: 0) {
            if isUser { Spacer(minLength: 40) }
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
            .frame(maxWidth: 520, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous)
                    .fill(isUser ? Color.steveAccent.opacity(0.38) : Color.white.opacity(0.14))
            }
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
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
        HStack(alignment: .bottom, spacing: 8) {
            TextField(compact ? "Сообщение…" : "Или напиши сообщение…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .font(.system(size: compact ? 13 : 14))
                .foregroundStyle(Color.steveText)
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 8 : 11)
                .frame(minHeight: compact ? 38 : 42)
                .glassControl(cornerRadius: compact ? 12 : 14)
                .focused($focused)
                .onKeyPress(keys: [.return], phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        text += "\n"
                    } else {
                        send()
                    }
                    return .handled
                }
                .onChange(of: text) { model.typingChanged(text) }
                .onChange(of: focused) {
                    if !focused { model.typingChanged(text.isEmpty ? "" : text); if text.isEmpty { model.character.stopFollowing() } }
                }

            if !compact {
                GlassIconButton(symbol: "return") { send() }
                    .help("Отправить (Enter)")
                GlassIconButton(symbol: "mic") { model.toggleVoiceCapture() }
                    .help("Сказать голосом")
            }
        }
        .padding(.horizontal, compact ? 0 : 14)
        .padding(.top, compact ? 0 : 10)
        .padding(.bottom, compact ? 0 : 14)
    }

    private func send() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        text = ""
        Task { await model.ask(message, typed: true) }
    }
}
