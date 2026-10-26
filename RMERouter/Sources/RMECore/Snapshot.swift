import Foundation

public enum ClockSource: Codable, Sendable, Hashable {
    case `internal`
    case wordClock
    case port(String)   // 锁在某个输入端口上
}

/// 一台设备的时钟状态。Lock = 有有效信号；Sync = 与当前时钟同步（R5）。
public struct ClockState: Codable, Sendable, Equatable {
    public var configuredRate: Fact<Int>     // 设备上设置的采样率（从机也要设，见 XTC/S/MUX）
    public var source: Fact<ClockSource>
    public var lock: [String: Fact<Bool>]    // 输入端口 → Lock
    public var sync: [String: Fact<Bool>]    // 输入端口 → Sync

    public init(configuredRate: Fact<Int>, source: Fact<ClockSource>,
                lock: [String: Fact<Bool>] = [:], sync: [String: Fact<Bool>] = [:]) {
        self.configuredRate = configuredRate
        self.source = source
        self.lock = lock
        self.sync = sync
    }

    public var isMaster: Bool? {
        guard let s = source.knownValue else { return nil }
        if case .port = s { return false }
        return true
    }
}

public enum Transport: Codable, Sendable, Hashable {
    case osc(host: String, port: Int)
    case http(baseURL: String)
    case coreMIDI(endpoint: String)
    case midiOverMadi(viaPort: String)
    case dinMIDI
    case manualOnly
}

public enum OnlineState: String, Codable, Sendable { case online, offline, notProbed }

/// 一条控制路径（谁在用什么方式遥控这台设备）。
public struct ControlPath: Codable, Sendable, Hashable {
    public var controller: String   // "this-app" / "totalmix-aux" / "rme-connector" / "midi-remote" / "browser"
    public var transport: Transport
    public var state: OnlineState
    public var active: Bool

    public init(controller: String, transport: Transport, state: OnlineState, active: Bool) {
        self.controller = controller
        self.transport = transport
        self.state = state
        self.active = active
    }
}

/// 可写的前级字段（文档第 7.2 节）。只有这三个，其余一律拦截。
public enum PreampField: String, Codable, Sendable, CaseIterable {
    case gain, phantom, phase

    /// TotalMix Global OSC 的参数名（/input/<N>/<key>）。
    public var totalMixKey: String {
        switch self { case .gain: return "gain"; case .phantom: return "48v"; case .phase: return "phase" }
    }
    /// 12Mic JSON 的字段名（input/analog/<n>/<key>）。
    public var twelveMicKey: String {
        switch self { case .gain: return "gain"; case .phantom: return "p48"; case .phase: return "phase" }
    }
    public var label: String {
        switch self { case .gain: return "增益"; case .phantom: return "48V"; case .phase: return "相位" }
    }
    /// 增益可写范围（第 7.2 节：先限定 0–60 dB）。
    public static let gainRange: ClosedRange<Double> = 0 ... 60
    /// TotalMix 主卡话放的增益上限：XT 60 dB，UFX III 75 dB（手册 p.42）；随设备组成改（文档第 6.4.6 节）。
    nonisolated(unsafe) public static var totalMixGainMax: Double = 60
    public static var totalMixGainRange: ClosedRange<Double> { 0 ... totalMixGainMax }
    /// 某台设备的话放增益范围。
    public static func gainRange(device: String) -> ClosedRange<Double> { device == "xt" ? totalMixGainRange : gainRange }
}

/// 前级字段的值。
public enum PreampValue: Codable, Sendable, Equatable {
    case gain(Double)
    case flag(Bool)

    public var text: String {
        switch self {
        case let .gain(g): return String(format: "%.1f dB", g)
        case let .flag(b): return b ? "开" : "关"
        }
    }
}

/// 一路话放（前级）的状态（文档第 6.2 节）。读不到的字段为 unknown，不猜默认值。
public struct PreampChannel: Codable, Sendable, Equatable, Identifiable {
    public var input: ChannelRef          // 例如 12mic.analog.in:1
    public var label: Fact<String>
    public var gainDB: Fact<Double>
    public var phantom: Fact<Bool>        // 48V
    public var phase: Fact<Bool>          // 相位反转
    public var hiZ: Fact<Bool>            // 乐器输入
    public var autoGain: Fact<Bool>       // AutoSet
    public var gainGroup: Fact<String>

    public var id: ChannelRef { input }

    /// 某个可写字段的当前值；读不到为 nil。
    public func value(_ field: PreampField) -> PreampValue? {
        switch field {
        case .gain: return gainDB.knownValue.map(PreampValue.gain)
        case .phantom: return phantom.knownValue.map(PreampValue.flag)
        case .phase: return phase.knownValue.map(PreampValue.flag)
        }
    }

    public init(input: ChannelRef, label: Fact<String>, gainDB: Fact<Double>, phantom: Fact<Bool>, phase: Fact<Bool>,
                hiZ: Fact<Bool>, autoGain: Fact<Bool>, gainGroup: Fact<String>) {
        self.input = input
        self.label = label
        self.gainDB = gainDB
        self.phantom = phantom
        self.phase = phase
        self.hiZ = hiZ
        self.autoGain = autoGain
        self.gainGroup = gainGroup
    }
}

/// 每台设备一份只读快照。
public struct DeviceSnapshot: Codable, Sendable {
    public var deviceID: String
    public var reachable: Bool
    public var clock: ClockState
    /// 每个 MADI/ADAT 端口上配置的格式（发送端看输出口，接收端看输入口）。
    public var portFormats: [String: Fact<StreamFormat>]
    public var routes: [Route]
    public var controlPaths: [ControlPath]
    /// 设备专有的单项设置，例如 "xtc.adatOut.1-8.source" = "madiIn.1-8"。
    public var settings: [String: Fact<String>]
    /// 目标输出的静音/电平（R13），键为输出通道描述。
    public var outputMuted: [ChannelRef: Fact<Bool>]
    /// 话放（前级），按输入通道排序。
    public var preamps: [PreampChannel]

    public init(deviceID: String, reachable: Bool, clock: ClockState,
                portFormats: [String: Fact<StreamFormat>] = [:], routes: [Route] = [],
                controlPaths: [ControlPath] = [], settings: [String: Fact<String>] = [:],
                outputMuted: [ChannelRef: Fact<Bool>] = [:], preamps: [PreampChannel] = []) {
        self.deviceID = deviceID
        self.reachable = reachable
        self.clock = clock
        self.portFormats = portFormats
        self.routes = routes
        self.controlPaths = controlPaths
        self.settings = settings
        self.outputMuted = outputMuted
        self.preamps = preamps
    }
}

/// 终端设备约束（H2），例如 P16-I。
public struct TerminalConstraint: Codable, Sendable {
    public var deviceID: String
    public var allowedSampleRates: Set<Int>
    public var clockInputPort: String?   // P16-I 只从 ADAT A 取时钟
    public var grade: SourceGrade
    public var reference: String

    public init(deviceID: String, allowedSampleRates: Set<Int>, clockInputPort: String?,
                grade: SourceGrade, reference: String) {
        self.deviceID = deviceID
        self.allowedSampleRates = allowedSampleRates
        self.clockInputPort = clockInputPort
        self.grade = grade
        self.reference = reference
    }
}

/// 每台设备的控制并行策略（替代 v2 的全局 H5，见复核意见）。
public enum ControlConcurrencyPolicy: String, Codable, Sendable {
    case parallelAllowed      // 12Mic：官方手册称网络与 MIDI 可同时使用
    case singleControlInput   // XTC：MIDI 控制输入只选一个来源；MIDI Remote 与 Aux Device 不能并用
    case unknown
}

/// 整套系统在某一时刻的视图：拓扑 + 快照 + 能力 + 约束 + 用户期望。
public struct SystemSnapshot: Codable, Sendable {
    public var topology: Topology
    public var devices: [String: DeviceSnapshot]
    public var capabilities: [RoutingCapability]
    public var terminals: [TerminalConstraint]
    public var concurrency: [String: ControlConcurrencyPolicy]
    /// 用户声明的期望设置（R12 等“是否符合预期”的检查用），键同 DeviceSnapshot.settings。
    public var expectations: [String: String]
    /// TotalMix Aux Device 配置：设备 ID → 它在 XT 某 MADI 输入上占用的首通道（R11）。
    public var auxDeviceFirstChannel: [String: ChannelRef]

    public init(topology: Topology, devices: [String: DeviceSnapshot], capabilities: [RoutingCapability],
                terminals: [TerminalConstraint], concurrency: [String: ControlConcurrencyPolicy] = [:],
                expectations: [String: String] = [:], auxDeviceFirstChannel: [String: ChannelRef] = [:]) {
        self.topology = topology
        self.devices = devices
        self.capabilities = capabilities
        self.terminals = terminals
        self.concurrency = concurrency
        self.expectations = expectations
        self.auxDeviceFirstChannel = auxDeviceFirstChannel
    }

    public func format(of portID: String) -> Fact<StreamFormat>? {
        guard let p = topology.port(portID) else { return nil }
        return devices[p.deviceID]?.portFormats[portID]
    }

    public func allRoutes() -> [Route] { devices.values.flatMap(\.routes) }
}
