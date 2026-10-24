import Foundation
import RMECore

/// TotalMix FX 2.1 Global OSC 适配器（只读，开发顺序第 3 步）。
///
/// 已查证（A，RME 协议表 OSCProtocoll_260721.ods，见文档第 7 节）：
/// - 混音节点可直接寻址：`/mix/in|pb/<源>/<输出>/fader`（dB），`/sendall 2` 发全部打开的节点。
/// - 通道号从 0 起，只在 `TotalMixChannel` 里换算；立体声用左声道编号。
/// - 状态：`/status/device`、`/status/connection`、`/status/dsp`；`/sendstate` 触发。
///   实测（2026-10-25）：XT 未连接时 TotalMix 照常回发保存的配置，connection=0。快照的 reachable 取 connection。
/// - 协议表没有采样率与时钟地址，时钟一律 unknown。
///
/// 待核（B / D）：XT 默认通道名格式（对照表推断依赖它）、TotalMix 对“发送方”的回显行为、
/// 开 Wi-Fi 时的 IPv6 绑定。写入在第 6 步接“待应用”栏后实现，在此之前 plan() 只生成人工步骤。
public struct TotalMixOSCAdapter: DeviceAdapter {
    public static let protocolReference = "https://www.rme-audio.de/downloads/globalosc_protocol_b2.zip（OSCProtocoll_260721.ods）"

    public let deviceID: String
    public let domain = ControlDomain.totalMix
    public let host: String
    public let port: Int
    public let client: TotalMixGlobalOSCClient
    /// 用户确认过的对照表；每次读取时再用 TotalMix 回读的名字补全。
    public var channelMap: TotalMixChannelMap

    /// host/port：TotalMix 的 OSC 接收地址；localPort：本 App 监听端口（TotalMix 的发送端口）。
    public init(deviceID: String = "xt", host: String = "127.0.0.1", port: Int, localPort: Int,
                channelMap: TotalMixChannelMap? = nil) {
        self.init(deviceID: deviceID, host: host, port: port,
                  transport: UDPOSCTransport(remoteHost: host, remotePort: port, localPort: localPort),
                  channelMap: channelMap)
    }

    /// 测试或自定义传输用。
    public init(deviceID: String = "xt", host: String = "127.0.0.1", port: Int, transport: OSCTransport,
                channelMap: TotalMixChannelMap? = nil) {
        self.deviceID = deviceID
        self.host = host
        self.port = port
        self.client = TotalMixGlobalOSCClient(transport: transport)
        self.channelMap = channelMap ?? TotalMixChannelMap(deviceID: deviceID)
    }

    public var capabilities: [Capability] {
        let ref = Self.protocolReference
        return [
            Capability("mix node read (/mix/in|pb/<src>/<out>/fader)", access: .readOnly, grade: .a, reference: ref),
            Capability("mix node write (/mix/…/fader)", access: .unknown, grade: .a,
                       reference: ref + "（协议支持；本 App 第 6 步实现写入前按不可写处理）"),
            Capability("channel name/stereo/mute read", access: .readOnly, grade: .a, reference: ref),
            Capability("status device/connection/dsp", access: .readOnly, grade: .a, reference: ref),
            Capability("sample rate / clock source", access: .unknown, grade: .d, reference: ref + "（协议表无此地址）"),
            Capability("echo of changes to sender", access: .unknown, grade: .b,
                       reference: "https://forum.rme-audio.de/viewtopic.php?id=43075（部分改动不回传）"),
        ]
    }

    private var transportDescription: Transport { .osc(host: host, port: port) }

    public func probe() async -> ControlPath {
        do { try await client.start() } catch {
            return ControlPath(controller: "this-app", transport: transportDescription, state: .offline, active: false)
        }
        let ok = await client.probe()
        return ControlPath(controller: "this-app", transport: transportDescription, state: ok ? .online : .offline, active: ok)
    }

    public func snapshot() async throws -> DeviceSnapshot {
        try await client.start()
        guard try await client.refreshAll() else { throw AdapterError.unreachable }
        let state = await client.state
        return Self.makeSnapshot(deviceID: deviceID, state: state, map: channelMap,
                                 controlPath: ControlPath(controller: "this-app", transport: transportDescription,
                                                          state: .online, active: true),
                                 observedAt: Date())
    }

    /// 把收到的状态翻译成快照（纯函数，便于测试）。
    public static func makeSnapshot(deviceID: String, state: TotalMixState, map: TotalMixChannelMap,
                             controlPath: ControlPath, observedAt: Date) -> DeviceSnapshot {
        let src = { (ref: String) in
            FactSource(deviceID: deviceID, interface: "totalmix-osc", reference: ref, observedAt: observedAt)
        }
        var map = map
        map.infer(from: state)
        let (routes, unmapped) = state.routes(using: map)

        var settings: [String: Fact<String>] = [
            "totalmix.unmappedNodes": .confirmed("\(unmapped)", src("对照表缺项的混音节点数")),
        ]
        if let name = state.deviceName { settings["totalmix.device"] = .confirmed(name, src("/status/device")) }
        if let c = state.connected { settings["totalmix.connection"] = .confirmed(c ? "1" : "0", src("/status/connection")) }

        return DeviceSnapshot(
            deviceID: deviceID,
            // TotalMix 回话 ≠ 设备在线：设备未连接时 TotalMix 仍会发出它保存的配置（2026-10-25 实测，connection=0）。
            reachable: state.connected ?? true,
            clock: ClockState(configuredRate: .unknown(src("协议表无采样率地址")),
                              source: .unknown(src("协议表无时钟源地址"))),
            routes: routes.sorted { $0.destination == $1.destination ? $0.source < $1.source : $0.destination < $1.destination },
            controlPaths: [controlPath],
            settings: settings,
            outputMuted: state.outputMuted(using: map, source: src("/output/N/mute")))
    }

    public func plan(_ change: RouteChange, current: DeviceSnapshot) -> [PlannedOperation] {
        // 写入在第 6 步实现；在此之前只生成“人工步骤”，不生成可执行写入。
        [PlannedOperation(deviceID: deviceID, parameter: "TotalMix: \(change.source) → \(change.destination)",
                          oldValue: nil, newValue: "0 dB send", access: .manual)]
    }

    public func apply(_ op: PlannedOperation, confirmation: UserConfirmation) async throws {
        try precheck(op, confirmation)
        throw AdapterError.protocolUnknown("TotalMix 写入在第 6 步实现")
    }

    public func verify(_ op: PlannedOperation) async throws -> VerificationResult { .unreadable }
}
