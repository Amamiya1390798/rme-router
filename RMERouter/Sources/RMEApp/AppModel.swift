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
    case outputs, signalFlow, connection
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .outputs: return "输出"
        case .signalFlow: return "信号流"
        case .connection: return "连接"
        }
    }
    public var symbol: String {
        switch self {
        case .outputs: return "speaker.wave.2"
        case .signalFlow: return "point.3.connected.trianglepath.dotted"
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
    /// 信号流视图当前查看的通道。
    public var traceTarget: ChannelRef?

    @ObservationIgnored private var adapter: TotalMixOSCAdapter?
    @ObservationIgnored private var retired: [TotalMixOSCAdapter] = []
    @ObservationIgnored private let defaults: UserDefaults
    private static let settingsKey = "osc.settings"

    public init(defaults: UserDefaults = .standard, snapshot: SystemSnapshot? = nil) {
        self.defaults = defaults
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

    /// 从 TotalMix 读取一次（/sendstate + /sendall 2，只读请求）。
    public func refresh() async {
        xtStatus = .loading
        for old in retired { await old.client.stop() }
        retired = []
        if adapter == nil {
            adapter = TotalMixOSCAdapter(host: settings.host, port: settings.port, localPort: settings.listenPort)
        }
        guard let adapter else { return }
        do {
            let xt = try await adapter.snapshot()
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
