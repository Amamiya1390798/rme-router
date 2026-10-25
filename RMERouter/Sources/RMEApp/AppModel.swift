import Foundation
import Observation
import RMECore
import RMEEngine
import RMEAdapters

/// TotalMix Global OSC 连接设置（与 TotalMix Settings → OSC 对应）。
public struct OSCSettings: Codable, Equatable, Sendable {
    public var host = "127.0.0.1"
    public var port = 7011        // TotalMix “Port (incoming)”
    public var listenPort = 9011  // TotalMix “Port (outgoing)”
    public init() {}
}

public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case outputs, signalFlow, preamps, clock, checkup, connection
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .outputs: return "输出"
        case .signalFlow: return "信号流"
        case .preamps: return "前级"
        case .clock: return "时钟"
        case .checkup: return "体检"
        case .connection: return "连接"
        }
    }
    public var symbol: String {
        switch self {
        case .outputs: return "speaker.wave.2"
        case .signalFlow: return "point.3.connected.trianglepath.dotted"
        case .preamps: return "mic"
        case .clock: return "clock"
        case .checkup: return "stethoscope"
        case .connection: return "cable.connector"
        }
    }
}

public enum XTStatus: Equatable, Sendable {
    case notLoaded
    case loading
    case live                 // TotalMix 回话，设备已连接
    case offlineSaved         // TotalMix 回话，设备未连接：显示保存的配置
    case unreachable(String)  // TotalMix 没回话
}

/// 写入的确认方式（文档第 7.4 节）。
public enum ConfirmMode: String, CaseIterable, Identifiable, Sendable {
    case always   // 每次确认：进待应用栏，确认框里确认才发送
    case quick    // 快速：点下即发送；打开 48V、大幅抬高仍弹确认框
    public var id: String { rawValue }
    public var title: String { self == .always ? "每次确认" : "快速" }
    public static let defaultsKey = "confirm.mode"
}

/// 12Mic 读取状态。读不到时“输出”等视图继续显示演示数据并注明。
public enum TwelveMicStatus: Equatable, Sendable {
    case notLoaded
    case loading
    case live
    case unreachable(String)
}

/// App 的全部状态。只读：不向任何设备发送写入类消息（写入在“待应用”栏完成后再接）。
@MainActor
@Observable
public final class AppModel {
    /// 侧边栏选中的视图（List 单选要求可选值；nil 按“输出”显示）。
    public var section: AppSection? = .outputs
    public var settings: OSCSettings {
        didSet {
            saveSettings()
            // 端口变了：旧监听端口要先释放，下次 refresh() 时停掉旧客户端再建新的。
            if let old = adapter { retired.append(old) }
            adapter = nil
        }
    }
    public private(set) var snapshot: SystemSnapshot
    public private(set) var xtStatus: XTStatus = .notLoaded
    public private(set) var lastLoaded: Date?
    /// 12Mic HTTP 地址（文档第 6.2 节）：网络 http://12mic.local，USB 直连 http://172.20.0.1。
    public var twelveMicURL: String { didSet { defaults.set(twelveMicURL, forKey: Self.twelveMicKey) } }
    public private(set) var twelveMicStatus: TwelveMicStatus = .notLoaded
    /// 信号流视图当前查看的通道。
    public var traceTarget: ChannelRef?

    // 写入（文档第 7.1 节）：待应用的改动、应用历史、确认框状态。
    public internal(set) var pending: [PendingChange] = []
    public internal(set) var pendingPreamps: [PendingPreampChange] = []
    public internal(set) var pendingRoutes: [PendingRouteChange] = []
    /// 需要在设备上手动完成的步骤（跨设备“送一路声音”里的 XTC 等，第 7.5 节）。
    public internal(set) var manualTasks: [ManualTask] = []
    public internal(set) var history: [AppliedBatch] = []
    public var showConfirm = false
    /// 确认方式（第 7.4 节）。
    public var confirmMode: ConfirmMode { didSet { defaults.set(confirmMode.rawValue, forKey: ConfirmMode.defaultsKey) } }
    public internal(set) var isApplying = false
    /// 最近一次从 TotalMix 读回的原始状态与对照表（写入时用来反查 TotalMix 通道）。
    public internal(set) var tmState = TotalMixState()
    public internal(set) var xtMap = TotalMixChannelMap()

    @ObservationIgnored var adapter: TotalMixOSCAdapter?
    @ObservationIgnored private var retired: [TotalMixOSCAdapter] = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeAdapter: (OSCSettings) -> TotalMixOSCAdapter
    @ObservationIgnored let makeTwelveMic: (URL) -> TwelveMicJSONAdapter
    private static let settingsKey = "osc.settings"
    private static let twelveMicKey = "12mic.url"

    /// makeAdapter / makeTwelveMic：测试时注入假设备；默认走 UDP / HTTP。
    public init(defaults: UserDefaults = .standard, snapshot: SystemSnapshot? = nil,
                makeAdapter: @escaping (OSCSettings) -> TotalMixOSCAdapter = {
                    TotalMixOSCAdapter(host: $0.host, port: $0.port, localPort: $0.listenPort)
                },
                makeTwelveMic: @escaping (URL) -> TwelveMicJSONAdapter = { TwelveMicJSONAdapter(baseURL: $0) }) {
        self.defaults = defaults
        self.makeAdapter = makeAdapter
        self.makeTwelveMic = makeTwelveMic
        twelveMicURL = defaults.string(forKey: Self.twelveMicKey) ?? "http://12mic.local"
        confirmMode = defaults.string(forKey: ConfirmMode.defaultsKey).flatMap(ConfirmMode.init(rawValue:)) ?? .always
        if let data = defaults.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(OSCSettings.self, from: data) {
            settings = saved
        } else {
            settings = OSCSettings()
        }
        self.snapshot = snapshot ?? StudioSetup.snapshot(xt: StudioSetup.emptyXT(reason: "尚未读取"))
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.settingsKey) }
    }

    /// 读取全部设备（只读）：TotalMix 与 12Mic 同时进行。
    public func refresh() async {
        async let mic: Void = refreshTwelveMic()
        await refreshTotalMix()
        await mic
    }

    /// 从 12Mic 读取一次（JSON，请求体全为 null）。读不到时保留演示数据。
    public func refreshTwelveMic() async {
        guard let url = URL(string: twelveMicURL.trimmingCharacters(in: .whitespaces)), url.host != nil else {
            twelveMicStatus = .unreachable("12Mic 地址无效：\(twelveMicURL)")
            return
        }
        twelveMicStatus = .loading
        do {
            let snap = try await makeTwelveMic(url).snapshot()
            apply(twelveMic: snap)
        } catch {
            twelveMicStatus = .unreachable("12Mic（\(url.absoluteString)）没有回应：检查网线或 USB、地址，以及设备 STATE → remote 的 HTTP Remote 是否打开。")
        }
    }

    /// 用读到的 12Mic 快照替换演示数据。
    public func apply(twelveMic: DeviceSnapshot) {
        var devices = snapshot.devices
        devices["12mic"] = twelveMic
        replaceDevices(devices)
        twelveMicStatus = .live
    }

    /// 只换设备快照，其余（拓扑、约束）不变。
    func replaceDevices(_ devices: [String: DeviceSnapshot]) {
        snapshot = SystemSnapshot(topology: snapshot.topology, devices: devices, capabilities: snapshot.capabilities,
                                  terminals: snapshot.terminals, concurrency: snapshot.concurrency,
                                  expectations: snapshot.expectations, auxDeviceFirstChannel: snapshot.auxDeviceFirstChannel)
    }

    /// 从 TotalMix 读取一次（/sendstate + /sendall 2，只读请求）。
    public func refreshTotalMix() async {
        xtStatus = .loading
        for old in retired { await old.client.stop() }
        retired = []
        if adapter == nil { adapter = makeAdapter(settings) }
        guard let adapter else { return }
        do {
            let xt = try await adapter.snapshot()
            await captureTotalMixState(from: adapter)
            apply(xt: xt)
        } catch {
            await adapter.client.stop()
            self.adapter = nil
            xtStatus = .unreachable(Self.describe(error))
        }
    }

    /// 用读到的 XT 快照更新（测试与预览也走这里）。
    public func apply(xt: DeviceSnapshot) {
        snapshot = StudioSetup.snapshot(xt: xt, others: snapshot.devices.filter { $0.key != "xt" })
        xtStatus = xt.reachable ? .live : .offlineSaved
        lastLoaded = Date()
        if traceTarget == nil { traceTarget = traceCandidates.first }
    }

    /// 记下 TotalMix 原始状态与推断后的对照表。
    func captureTotalMixState(from adapter: TotalMixOSCAdapter) async {
        tmState = await adapter.client.state
        var map = adapter.channelMap
        map.infer(from: tmState)
        xtMap = map
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case AdapterError.unreachable: return "TotalMix 没有回应。检查 Global OSC 是否打开、端口是否一致。"
        case let e as OSCTransportError: return "网络错误：\(e)"
        default: return "\(error)"
        }
    }

    // MARK: 派生数据

    /// “输出”视图是否列出电脑回放来源（默认不列）。
    public var showPlayback = false

    public var outputs: [DeviceOutputs] { OutputCards.build(snapshot, showPlayback: showPlayback) }

    /// 可以追踪的起点：有路由送出的输入通道，按拓扑设备顺序。
    public var traceCandidates: [ChannelRef] {
        let sources = Set(snapshot.allRoutes().map(\.source))
        let order = Dictionary(uniqueKeysWithValues: snapshot.topology.devices.enumerated().map { ($1.id, $0) })
        return sources.sorted { a, b in
            let da = order[deviceID(of: a)] ?? 99, db = order[deviceID(of: b)] ?? 99
            return da != db ? da < db : a < b
        }
    }

    public func deviceID(of ref: ChannelRef) -> String {
        snapshot.topology.port(ref.portID)?.deviceID ?? String(ref.portID.split(separator: ".").first ?? "")
    }

    public func deviceName(of ref: ChannelRef) -> String {
        snapshot.topology.device(deviceID(of: ref))?.name ?? deviceID(of: ref)
    }

    /// 某设备的数据是否只是演示占位。
    public func isDemo(_ deviceID: String) -> Bool {
        snapshot.devices[deviceID]?.controlPaths.allSatisfy { $0.state == .notProbed } ?? true
    }
}
