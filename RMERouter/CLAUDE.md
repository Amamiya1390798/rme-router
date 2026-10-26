# RME Router — 给 AI 助手的项目说明

先读 `docs/v3-需求与设计.md`，尤其第 2 节（分工与交接）、第 6.1 节（链路表示法）和第 7 节（Global OSC 安全规则）。

## 项目是什么

macOS 原生 SwiftUI 应用，在 TotalMix FX 2.1 之上管理 MADIface XT、12Mic、OctaMic XTC 之间的路由，并整合 RME Connector 的前级控制。TotalMix 必须在后台运行。

## 目录

- `Package.swift`、`Sources/`、`Tests/`：核心 Swift 包（无 UI）。已在 Mac 上编译，`swift test` 全绿（231/231）。
- `docs/`：需求与设计文档。
- App：`Sources/RMEApp`（界面库）+ `Sources/RMERouterApp`（入口），`swift run RMERouterApp` 启动；`--render <目录>` 把视图渲染成 PNG 检查；`scripts/make-app.sh` 打包成 `.build/RMERouter.app`。量切页卡顿：`RME_PERF=1 RME_PERF_OUT=结果.txt` 启动 App 可执行文件（可加 `RME_PERF_FOCUS=1`），跑完自动退出；先关掉正在运行的 App（端口会冲突）。Xcode 工程尚未创建。

## 硬性规则

1. 不修改 RME 驱动；不编造设备 API，没有出处的能力一律按“未知”处理。
2. 未经用户明确同意，不向任何真实设备发送写入类消息。
3. Global OSC：永远不要发送不带值的地址；通道从 0 编号只在适配器里换算。
4. 所有地址用 `设备.接口.方向:通道`（见 docs 第 6.1 节），名字只是别名。
5. 改数据模型或安全规则，先改文档再改代码。
6. 每次结束工作，更新 docs 第 2 节的“当前状态”。
