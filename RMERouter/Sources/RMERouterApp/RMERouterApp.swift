import AppKit
import SwiftUI
import RMEApp

struct RMERouterApp: App {
    @State private var model = AppModel()

    init() {
        // swift run 启动的可执行文件没有 .app 包：手动设为普通前台应用，窗口才会出现在前面。
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("RME Router") {
            RootView(model: model)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
