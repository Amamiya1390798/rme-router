// swift-tools-version:5.9
// RME 跨设备路由管理器 —— 核心逻辑包（无 UI、无硬件依赖，可在 CI 中测试）。
// SwiftUI App 目标放在 Xcode 工程 App/ 中，依赖本包。
import PackageDescription

let package = Package(
    name: "RMERouter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RMECore", targets: ["RMECore"]),
        .library(name: "RMEEngine", targets: ["RMEEngine"]),
        .library(name: "RMEAdapters", targets: ["RMEAdapters"]),
        .executable(name: "rme-probe", targets: ["rme-probe"]),
        .library(name: "RMEApp", targets: ["RMEApp"]),
        .executable(name: "RMERouterApp", targets: ["RMERouterApp"]),
    ],
    targets: [
        // 纯数据模型：证据、流格式、拓扑、路由、时钟、快照
        .target(name: "RMECore"),
        // 体检规则引擎 + 路径搜索 + 计划生成（只计划，不执行）
        .target(name: "RMEEngine", dependencies: ["RMECore"]),
        // 设备适配器：协议、12Mic JSON、TotalMix OSC、XTC MIDI、Mock
        .target(name: "RMEAdapters", dependencies: ["RMECore"]),
        // 只读命令行工具：检查 TotalMix Global OSC 读回结果
        .executableTarget(name: "rme-probe", dependencies: ["RMECore", "RMEAdapters"]),
        // SwiftUI 界面：模型、设计 token、视图（库，便于测试与出图）
        .target(name: "RMEApp", dependencies: ["RMECore", "RMEEngine", "RMEAdapters"]),
        // App 入口：swift run RMERouterApp
        .executableTarget(name: "RMERouterApp", dependencies: ["RMECore", "RMEEngine", "RMEApp"]),
        .testTarget(name: "RMEAppTests", dependencies: ["RMECore", "RMEEngine", "RMEAdapters", "RMEApp"]),
        .testTarget(name: "RMEEngineTests", dependencies: ["RMECore", "RMEEngine", "RMEAdapters"]),
    ]
)
