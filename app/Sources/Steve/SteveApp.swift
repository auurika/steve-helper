import AppKit
import SwiftUI

@main
struct SteveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Стив", id: "main") {
            RootView()
                .environment(model)
                .onAppear { model.start() }
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            PopoverView().environment(model)
        } label: {
            MenuBarIcon().environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Значок Стива в меню-баре: тот же Стив, он моргает, смотрит по сторонам и засыпает.
private struct MenuBarIcon: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: model.menuBarImage)
            .onAppear {
                model.openMainWindow = {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                model.start()
            }
    }
}

/// Закрытие окна не завершает приложение: Стив остаётся в меню-баре и Dock.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        SnapshotTool.runIfRequested(model: AppModel.shared)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppModel.shared.openMainWindow?() }
        return true
    }
}
