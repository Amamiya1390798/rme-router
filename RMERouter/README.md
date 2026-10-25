# RMERouter（v3 复核配套代码）

使用说明见 [docs/使用手册.md](docs/使用手册.md)。

> 已在 Mac（Swift 6.2.3）上编译，测试全绿。修改后请运行
> `swift build && swift test`。

## 目录与模块依赖

```
RMERouter/                     Swift Package（无 UI，可在 CI 里测）
├─ Package.swift
├─ Sources/
│  ├─ RMECore/                 纯数据模型，无依赖
│  │  ├─ Evidence.swift        Fact<T>、Evidence、Access、SourceGrade(A/A2/B/C/D)、Capability
│  │  ├─ StreamFormat.swift    StreamFormat、SpeedMode、FormatCheck（含“Lock 但速度解读错”）
│  │  ├─ Topology.swift        Port、Link（单向）、ChannelRef、Topology.validate()
│  │  ├─ Routing.swift         ControlDomain、Route、RouteKind、RoutingCapability、RouteChange
│  │  └─ Snapshot.swift        ClockState、ControlPath、DeviceSnapshot、SystemSnapshot、TerminalConstraint
│  ├─ RMEEngine/               依赖 RMECore
│  │  ├─ Diagnostics.swift     体检规则 R1–R14
│  │  └─ PathFinder.swift      约束 Dijkstra + 计划生成（只计划，不执行）
│  └─ RMEAdapters/             依赖 RMECore
│     ├─ DeviceAdapter.swift   协议、UserConfirmation（H8 类型级保证）
│     ├─ TwelveMicJSONAdapter.swift   官方 JSON(OSC) 接口，可读写
│     ├─ TotalMixOSCAdapter.swift      TotalMix Global OSC 只读快照（写入在第 6 步）
│     ├─ GlobalOSC/                    OSC 编解码、地址层、发送白名单、UDP 传输、只读客户端
│     ├─ XTCMIDIAdapter.swift          骨架：协议未证实部分一律 manual/unknown
│     └─ MockDevice.swift      Mock + PlanExecutor（回滚）
├─ Sources/rme-probe/          只读命令行：swift run rme-probe --port <TotalMix 接收端口> --listen <发送端口>
├─ Sources/RMEApp/             SwiftUI 界面：AppModel、设计 token、StudioSetup（本工作室拓扑）、视图
├─ Sources/RMERouterApp/       App 入口：swift run RMERouterApp（--render <目录> 出图）
├─ scripts/make-app.sh         打包成 .build/RMERouter.app：`scripts/make-app.sh release --install` 装到 ~/Applications
├─ scripts/make-icon.swift     生成 Resources/AppIcon.icns
├─ VERSION                     版本号
├─ Tests/RMEAppTests/          界面数据层测试
└─ Tests/RMEEngineTests/       夹具 + T1–T10 + GlobalOSCTests + SignalTraceTests

App/（Xcode 工程，另建）        SwiftUI，依赖 RMEEngine + RMEAdapters
  Topology/  拓扑编辑与连接校验
  Checkup/   体检报告
  Trace/     路径追踪（按控制域分层显示）
  Plan/      预览与确认（唯一调用 ConfirmationGate 的地方）
```

依赖方向：`App → RMEEngine → RMECore`，`App → RMEAdapters → RMECore`。
Engine 与 Adapters 互不依赖：引擎只吃 `SystemSnapshot`，所以 Mock 与真机走同一套规则。

## 路径搜索伪代码

```
find(source, target):
  dist[(source, nil)] = 0; push heap
  while heap 非空:
    (d, node, lastDomain) = pop 最小
    if node == target: return 计划(回溯 prev)
    for edge in edges(node):              # 约束在这里过滤
      cost = edge.cost
      if edge 属于控制域 D:
        if lastDomain 存在且 ≠ D: cost += 3
        lastDomain' = D
      relax((edge.to, lastDomain'), d + cost)
  return 无解(被拦下的约束原因列表)

edges(node):
  node 在输出口:                         # 线缆边
    对每条 Link(node.port → to):
      类型不符                    → 拦下“接口类型不符”
      node.channel > 当前格式通道数 → 拦下“该采样率下只有 N 路”
      FormatCheck(发送格式, 接收格式或终端约束) 有错误 → 拦下并记录原因
      否则 → 边(to#同通道, 代价 0；格式未知则证据=unknown)
  node 在输入口:                         # 设备内部边
    已有路由 source==node             → 边(代价 0)
    对每个能力 cap(含该输入口):
      逐通道: 所有输出口的所有可用通道
      8 通道块: 每个输出块中与 node 同块内偏移的通道，额外 +7
      代价 = 1 + (cap 不可写 ? 10 : 0) + (目标被他人占用 ? 100 : 0)
      记录将被覆盖/混入的旧路由

计划: 只读与核对步骤在前；需改动的步骤从下游到上游；不可远程写的列为人工步骤。
```

## 场景与测试

| 场景 | 测试 | 覆盖 |
|---|---|---|
| T1 采样率不一致 | testT1_SampleRateMismatch | R2、R3、FormatCheck |
| T2 映射位置 | testT2_MappingOffset | 路径起点、R11 |
| T3 终端采样率 | testT3_TerminalRate | R7、无解原因 |
| T4 ADAT 源不符 | testT4_AdatSourceMismatch | R12 |
| T5 控制路径并行 | testT5_ParallelControl | R9 按设备策略 |
| T6 设备离线 | testT6_Offline | R10、R11、R2 无法判断 |
| T7 接口类型不符 | testT7_MediumMismatch | Topology.validate |
| T8 占用冲突 | testT8_Override | 计划列出被覆盖路由 |
| T9 写入部分失败 | testT9_PartialWriteRollback | PlanExecutor 回滚 |
| T10 ADAT A 无输入 | testT10_NoAdatA | R8 |
