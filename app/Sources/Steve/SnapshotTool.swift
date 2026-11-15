import AppKit
import SwiftUI
import SteveCore

/// Служебный режим для разработки: `Steve --snapshot <папка>` рисует окна приложения в PNG и закрывается.
/// Нужен, чтобы проверять внешний вид без записи экрана (например, в автоматических проверках).
/// Окно создаётся за пределами видимой области, поэтому на экране ничего не мигает.
@MainActor
enum SnapshotTool {
    static var isRequested: Bool { CommandLine.arguments.contains("--snapshot") || CommandLine.arguments.contains("--snapshot-window") }

    /// `--snapshot-window <папка>`: снимает настоящее окно приложения (с заголовком и кнопками) в нескольких размерах.
    static func runWindowCaptureIfRequested(model: AppModel) {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot-window"), arguments.indices.contains(index + 1) else { return }
        let folder = URL(fileURLWithPath: arguments[index + 1])
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard let window = NSApp.windows.first(where: { $0.title == "Стив" }) else {
                FileHandle.standardError.write(Data("main window not found: \(NSApp.windows.map(\.title))\n".utf8))
                NSApp.terminate(nil)
                return
            }
            for (width, height) in [(960.0, 640.0), (560.0, 700.0), (420.0, 460.0)] {
                for section in [AppSection.chat, .presets, .settings] {
                    model.section = section
                    window.setContentSize(CGSize(width: width, height: height))
                    try? await Task.sleep(for: .milliseconds(400))
                    let name = "window-\(Int(width))x\(Int(height))-\(section)"
                    if let frame = window.contentView?.superview, let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
                        frame.cacheDisplay(in: frame.bounds, to: bitmap)
                        try? bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(name).png"))
                    }
                    FileHandle.standardError.write(Data("\(name): window frame \(window.frame.size), content \(window.contentLayoutRect.size)\n".utf8))
                }
            }
            NSApp.terminate(nil)
        }
    }

    static func runIfRequested(model: AppModel) {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) else { return }
        let folder = URL(fileURLWithPath: arguments[index + 1])
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        Task {
            try? await Task.sleep(for: .milliseconds(600))
            model.prepareDemo()
            for (section, name) in [(AppSection.chat, "chat"), (.presets, "presets"), (.settings, "settings")] {
                model.section = section
                await capture(RootContent().environment(model), size: CGSize(width: 960, height: 640), to: folder.appendingPathComponent("\(name).png"))
            }
            model.section = .chat
            model.previewSidebarExpanded = true
            await capture(RootContent().environment(model), size: CGSize(width: 960, height: 640), to: folder.appendingPathComponent("sidebar-expanded.png"))
            model.previewSidebarExpanded = false
            model.character.play(.happy)
            await capture(PopoverView().environment(model), size: CGSize(width: 340, height: 330), to: folder.appendingPathComponent("popover.png"))
            await capture(iconSheet, size: CGSize(width: 720, height: 150), to: folder.appendingPathComponent("menubar-icon.png"))
            NSApp.terminate(nil)
        }
    }

    /// Значок для меню-бара в разных состояниях, увеличенный в 6 раз: проверка, что ничего не обрезается.
    private static var iconSheet: some View {
        let frames: [SteveFrame] = [
            SteveAnimator.frame(animation: nil, asleep: false, elapsed: 0, clock: 0),
            SteveAnimator.frame(animation: nil, asleep: true, elapsed: 0, clock: 4),
            SteveAnimator.frame(animation: .surprise, asleep: false, elapsed: 0.5, clock: 0),
            SteveAnimator.frame(animation: .hop, asleep: false, elapsed: 0.4, clock: 0),
            SteveAnimator.frame(animation: .think, asleep: false, elapsed: 2.0, clock: 0),
            SteveAnimator.frame(animation: .dance, asleep: false, elapsed: 0.5, clock: 0),
        ]
        return HStack(spacing: 18) {
            ForEach(0..<frames.count, id: \.self) { index in
                SteveCanvas(frame: frames[index], isTiny: true)
                    .frame(width: 21 * 5, height: 23 * 5)
                    .border(Color.white.opacity(0.4)) // граница показывает, где обрезается
            }
        }
    }

    /// Рисует настоящий NSHostingView, поэтому в снимок попадают и поля ввода, и прокрутка.
    private static func capture(_ view: some View, size: CGSize, to url: URL) async {
        let content = ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.55, green: 0.3, blue: 0.7), Color(red: 0.2, green: 0.3, blue: 0.7), Color(red: 0.15, green: 0.6, blue: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            view
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)

        let hosting = NSHostingView(rootView: content)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(x: -3000, y: -3000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(500)) // даём SwiftUI дорисовать

        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            do { try png.write(to: url) } catch { FileHandle.standardError.write(Data("write failed: \(error)\n".utf8)) }
        }
        window.orderOut(nil)
    }
}
