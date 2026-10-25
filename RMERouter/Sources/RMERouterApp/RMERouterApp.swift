import AppKit
import SwiftUI
import RMEApp

/// 单窗口工具：关掉窗口即退出，不留一个没有窗口的后台进程（看起来像 App 消失了）。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RMERouterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(linkStore: .standard, sceneStore: .standard)

    init() {
        // swift run 启动的可执行文件没有 .app 包：手动设为普通前台应用，窗口才会出现在前面。
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        // 只有一个主窗口（Window 而不是 WindowGroup）：Cmd+N 不会再开出共享同一模型的第二个窗口。
        Window("RME Router", id: "main") {
            RootView(model: model)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
