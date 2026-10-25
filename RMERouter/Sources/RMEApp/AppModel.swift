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

/// 侧边栏的页（第 6.8 节：6 页，部分页内再分栏）。
public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case devices, outputs, preamps, checkup, scenes, settings
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .devices: return "设备"
        case .outputs: return "输出"
        case .preamps: return "前级"
        case .checkup: return "体检"
        case .scenes: return "场景"
        case .settings: return "设置"
        }
    }
    public var symbol: String {
        switch self {
        case .devices: return "rectangle.stack"
        case .outputs: return "speaker.wave.2"
        case .preamps: return "mic"
        case .checkup: return "stethoscope"
        case .scenes: return "square.stack.3d.up"
        case .settings: return "gearshape"
        }
    }
}

/// 设备页右栏：通道条或信号流。
public enum DevicesPane: String, CaseIterable, Identifiable, Sendable {
    case strips, signalFlow
    public var id: String { rawValue }
    public var title: String { self == .strips ? "通道条" : "信号流" }
}

/// 体检页的分栏。
public enum CheckupTab: String, CaseIterable, Identifiable, Sendable {
    case checkup, clock
    public var id: String { rawValue }
    public var title: String { self == .checkup ? "体检" : "时钟" }
}

/// 设置页的分栏。
public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case connection, wiring
    public var id: String { rawValue }
    public var title: String { self == .connection ? "连接" : "接线" }
}

public enum XTStatus: Equatable, Sendable {
    case notLoaded
    case loading
    case live                 // TotalMix 回话，设备已连接
    case offlineSaved         // TotalMix 回话，设备未连接：显示保存的配置
    case unreachable(String)  // TotalMix 没回话
}

extension AppModel {
    /// 跳到设备页的信号流，追这一路。
    public func showTrace(_ ref: ChannelRef) {
        traceTarget = ref
        devicesPane = .signalFlow
        section = .devices
    }

    public func showWiring() {
        settingsTab = .wiring
        section = .settings
    }
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
    public var section: AppSection? = .devices
    public var devicesPane: DevicesPane = .strips
    public var checkupTab: CheckupTab = .checkup
    public var settingsTab: SettingsTab = .connection
    /// 设备页面板上选中的接口（PanelConnector.id）；接口详情显示在检查器里。
    public var panelSelection: String?
    /// 选中接口后在通道格里点的那一路；nil = 整个接口。
    public var panelChannel: Int?
    public var settings: OSCSettings {
        didSet {
            saveSettings()
            // 端口变了：旧监听端口要先释放，下次 refresh() 时停掉旧客户端再建新的。
            if let old = adapter { retired.append(old) }
            adapter = nil
        }
    }
    public internal(set) var snapshot: SystemSnapshot { didSet { snapshotVersion += 1 } }
    /// 快照每变一次加 1；派生数据（源头标签）按它缓存。
    @ObservationIgnored var snapshotVersion = 0
    @ObservationIgnored var originCache: (version: Int, labels: [ChannelRef: OriginLabel])?
    /// 选接口看链路的结果缓存（第 6.4.4 节）：快照、TotalMix 状态、有信号的通道都没变就不重算。
    /// 屏蔽的通道条（第 6.4.5 节）：只影响显示，存在本机偏好里。
    public internal(set) var hiddenStrips: Set<TotalMixChannel> = [] {
        didSet { if let d = try? JSONEncoder().encode(hiddenStrips) { defaults.set(d, forKey: Self.hiddenStripsKey) } }
    }
    static let hiddenStripsKey = "strips.hidden"
    @ObservationIgnored var outputsCache: (key: [Int], groups: [DeviceOutputs])?
    @ObservationIgnored var checkupCache: (version: Int, results: [RuleResult])?
    @ObservationIgnored var loopbackCache: (revision: Int, version: Int, map: [Int: XTStrip])?
    @ObservationIgnored var focusCache: (key: [AnyHashable], focus: StripFocus)?
    /// 线缆核对结果（第 6.5 节），按两端端口记，存在 UserDefaults。
    public internal(set) var linkVerifications: [String: LinkVerification] = [:] {
        didSet {
            if let d = try? JSONEncoder().encode(linkVerifications) { defaults.set(d, forKey: Self.verificationsKey) }
            originCache = nil   // 源头标签要按新的核对结果重算
        }
    }
    /// 正在进行或刚结束的信号核对。
    public internal(set) var identify: IdentifyTest?
    /// Core Audio 读到的 XT（第 6.6 节）；nil = 没找到（XT 没接）。
    public internal(set) var xtAudio: AudioDeviceInfo?
    public internal(set) var audioChecked = false
    /// Logic 设定的音频设备（第 6.7 节）；没装 Logic 为 nil。
    public internal(set) var logicSettings: LogicAudioSettings?
    @ObservationIgnored public var logicPrefsURL = LogicAudioSettings.defaultURL
    /// Logic 偏好文件上次读取时的修改时间：没变就不重读（文件约 0.5 MB，每 2 秒在主线程读一次会让界面周期性顿一下）。
    @ObservationIgnored var logicPrefsReadAt: Date?
    @ObservationIgnored let audioSystem: AudioSystem
    public private(set) var xtStatus: XTStatus = .notLoaded
    public private(set) var lastLoaded: Date?
    /// 12Mic HTTP 地址（文档第 6.2 节）：网络 http://12mic.local，USB 直连 http://172.20.0.1。
    public var twelveMicURL: String { didSet { defaults.set(twelveMicURL, forKey: Self.twelveMicKey) } }
    public private(set) var twelveMicStatus: TwelveMicStatus = .notLoaded
    /// 信号流视图当前查看的通道。
    public var traceTarget: ChannelRef?
    /// 检查器（阶段 B2）：显式选中的通道与是否显示。
    public var inspected: ChannelRef?
    public var showInspector = false

    // 写入（文档第 7.1 节）：待应用的改动、应用历史、确认框状态。
    public internal(set) var pending: [PendingChange] = []
    public internal(set) var pendingPreamps: [PendingPreampChange] = []
    public internal(set) var pendingRoutes: [PendingRouteChange] = []
    public internal(set) var pendingXTCRoutes: [PendingXTCRouteChange] = []
    /// TotalMix 通道条改动（第 7.8 节）。
    public internal(set) var pendingStrips: [PendingStripChange] = []
    /// 控制室 / 全局静音 / 快照改动（第 7.9 节）。
    public internal(set) var pendingGlobals: [PendingGlobalChange] = []
    /// XTC（文档第 6.3 节）：设置全部默认关。
    public var xtcSettings: XTCSettings {
        didSet {
            // 前提没了，“允许改动”一并关掉，不留一个显示为开、实际无效的开关。
            if xtcSettings.writeEnabled, !xtcSettings.readEnabled || !xtcSettings.auxDeviceOff {
                xtcSettings.writeEnabled = false
                return
            }
            if let data = try? JSONEncoder().encode(xtcSettings) { defaults.set(data, forKey: Self.xtcKey) }
            if oldValue.sourceName != xtcSettings.sourceName || oldValue.destinationName != xtcSettings.destinationName
                || oldValue.midiDeviceID != xtcSettings.midiDeviceID || oldValue.canWrite != xtcSettings.canWrite {
                dropXTCAdapter()
                if xtcStatus == .live { xtcStatus = .unreachable("XTC 设置已改，请重新读取") }
            }
            if !xtcSettings.readEnabled, oldValue.readEnabled { xtcStatus = .off; restoreXTCDemo() }
            syncXTCCapability()
        }
    }
    public internal(set) var xtcStatus: XTCStatus = .off
    /// 需要在设备上手动完成的步骤（跨设备“送一路声音”里的 XTC 等，第 7.5 节）。
    public internal(set) var manualTasks: [ManualTask] = []
    /// 已保存的场景（第 7.6 节），新的在前。
    public internal(set) var scenes: [StudioScene] = []
    public internal(set) var history: [AppliedBatch] = []
    public var showConfirm = false
    /// 首次使用向导（阶段 D2）：没走完过就在启动时打开。
    public var showOnboarding = false
    public var onboardingDone: Bool {
        get { defaults.bool(forKey: "onboarding.done") }
        set { defaults.set(newValue, forKey: "onboarding.done") }
    }
    /// 确认方式（第 7.4 节）。
    public var confirmMode: ConfirmMode { didSet { defaults.set(confirmMode.rawValue, forKey: ConfirmMode.defaultsKey) } }
    public internal(set) var isApplying = false
    /// 最近一次从 TotalMix 读回的原始状态与对照表（写入时用来反查 TotalMix 通道）。
    public internal(set) var tmState = TotalMixState() { didSet { outputsCache = nil; focusCache = nil; loopbackCache = nil } }
    public internal(set) var xtMap = TotalMixChannelMap()

    @ObservationIgnored var adapter: TotalMixOSCAdapter?
    /// 电平（第 7.7 节）：单独的可观察对象，只让电平条重绘。
    @ObservationIgnored public let meters = MeterStore()
    @ObservationIgnored var meterTask: Task<Void, Never>?
    @ObservationIgnored private var retired: [TotalMixOSCAdapter] = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeAdapter: (OSCSettings) -> TotalMixOSCAdapter
    /// 读取成功后自动开始电平轮询（App 里开；测试里关，测试直接调 pollMetersOnce）。
    @ObservationIgnored public var startsMeters = false
    @ObservationIgnored let makeTwelveMic: (URL) -> TwelveMicJSONAdapter
    @ObservationIgnored let makeXTC: (XTCSettings) -> XTCMIDIAdapter
    @ObservationIgnored var xtcAdapter: XTCMIDIAdapter?
    /// 设置变了换下来的 XTC 连接：下次读取前先停掉（与 TotalMix 的 retired 同理）。
    @ObservationIgnored var xtcRetired: [XTCMIDIAdapter] = []
    @ObservationIgnored let linkStore: LinkStore
    @ObservationIgnored let sceneStore: SceneStore
    private static let settingsKey = "osc.settings"
    private static let twelveMicKey = "12mic.url"
    static let xtcKey = "xtc.settings"
    /// 一次抬高超过这么多 dB，快速方式下也要确认（第 7.4 节）。
    nonisolated public static let largeJumpDB = 20.0

    /// makeAdapter / makeTwelveMic：测试时注入假设备；默认走 UDP / HTTP。
    public init(defaults: UserDefaults = .standard, snapshot: SystemSnapshot? = nil,
                makeAdapter: @escaping (OSCSettings) -> TotalMixOSCAdapter = {
                    TotalMixOSCAdapter(host: $0.host, port: $0.port, localPort: $0.listenPort)
                },
                makeTwelveMic: @escaping (URL) -> TwelveMicJSONAdapter = { TwelveMicJSONAdapter(baseURL: $0) },
                makeXTC: @escaping (XTCSettings) -> XTCMIDIAdapter = AppModel.coreMIDIXTC,
                audioSystem: AudioSystem = CoreAudioSystem(),
                linkStore: LinkStore = .none, sceneStore: SceneStore = .none) {
        self.defaults = defaults
        self.linkStore = linkStore
        self.sceneStore = sceneStore
        self.scenes = sceneStore.load()
        self.makeAdapter = makeAdapter
        self.makeTwelveMic = makeTwelveMic
        self.makeXTC = makeXTC
        self.audioSystem = audioSystem
        linkVerifications = defaults.data(forKey: Self.verificationsKey)
            .flatMap { try? JSONDecoder().decode([String: LinkVerification].self, from: $0) } ?? [:]
        xtcSettings = defaults.data(forKey: Self.xtcKey).flatMap { try? JSONDecoder().decode(XTCSettings.self, from: $0) }
            ?? XTCSettings()
        twelveMicURL = defaults.string(forKey: Self.twelveMicKey) ?? "http://12mic.local"
        hiddenStrips = defaults.data(forKey: Self.hiddenStripsKey)
            .flatMap { try? JSONDecoder().decode(Set<TotalMixChannel>.self, from: $0) } ?? []
        confirmMode = defaults.string(forKey: ConfirmMode.defaultsKey).flatMap(ConfirmMode.init(rawValue:)) ?? .always
        if let data = defaults.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(OSCSettings.self, from: data) {
            settings = saved
        } else {
            settings = OSCSettings()
        }
        self.snapshot = snapshot ?? StudioSetup.snapshot(xt: StudioSetup.emptyXT(reason: "尚未读取"), links: linkStore.load())
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.settingsKey) }
    }

    /// 真实 XTC：CoreMIDI 端点。
    nonisolated public static func coreMIDIXTC(_ s: XTCSettings) -> XTCMIDIAdapter {
        let t = CoreMIDIXTCTransport(sourceName: s.sourceName, destinationName: s.destinationName)
        return XTCMIDIAdapter(client: XTCClient(transport: t, midiDeviceID: s.midiDeviceID),
                              endpointName: s.destinationName, controlEnabled: s.canWrite)
    }

    /// 读取全部设备（只读）：TotalMix、12Mic、XTC（打开“读取 XTC”时）同时进行。
    public func refresh() async {
        refreshAudio()
        async let mic: Void = refreshTwelveMic()
        async let xtc: Void = refreshXTC()
        await refreshTotalMix()
        await mic
        await xtc
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
            if startsMeters { startMeterLoop() }
        } catch {
            stopMeterLoop()
            await adapter.client.stop()
            self.adapter = nil
            xtStatus = .unreachable(Self.describe(error))
        }
    }

    /// 用读到的 XT 快照更新（测试与预览也走这里）。
    public func apply(xt: DeviceSnapshot) {
        snapshot = StudioSetup.snapshot(xt: xt, others: snapshot.devices.filter { $0.key != "xt" }, links: snapshot.topology.links)
        syncXTCCapability()
        xtStatus = xt.reachable ? .live : .offlineSaved
        lastLoaded = Date()
        mergeAudioIntoXT()
        if traceTarget == nil { traceTarget = traceCandidates.first }
    }

    /// 与 TotalMix 同步（第 6.4.3 节）：客户端收到的状态有变化（不算电平）就重建对照表与 XT 快照，所有页面一起更新。
    /// 返回是否有变化。
    @discardableResult
    public func syncFromTotalMix() async -> Bool {
        guard let adapter, lastLoaded != nil else { return false }
        let state = await adapter.client.state
        guard state.revision != tmState.revision else { return false }
        // 立体声配对变了：TotalMix 不一定重发名字，主动把这一对读回来（只读请求）
        let changed = state.channels.keys.filter { ch in
            ch.number % 2 == 1 && state.isStereo(ch) != tmState.isStereo(ch) && tmState.isStereo(ch) != nil
        }
        if !changed.isEmpty {
            _ = try? await adapter.client.refreshChannels(changed.flatMap { [$0, TotalMixChannel($0.bus, $0.number + 1)] })
        }
        await captureTotalMixState(from: adapter)
        apply(xt: TotalMixOSCAdapter.makeSnapshot(
            deviceID: "xt", state: tmState, map: adapter.channelMap,
            controlPath: ControlPath(controller: "this-app", transport: .osc(host: settings.host, port: settings.port),
                                     state: .online, active: true),
            observedAt: Date()))
        return true
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
    /// 输出页“只看有信号”（第 8.2 节 E1）。收不到电平时界面把开关灰掉。
    public var outputsOnlySignal = false

    public var outputs: [DeviceOutputs] {
        // 按快照、TotalMix 状态、是否显示回放缓存：每次重绘都重建全部输出卡太慢
        let key = [snapshotVersion, tmState.revision, showPlayback ? 1 : 0]
        let all: [DeviceOutputs]
        if let c = outputsCache, c.key == key { all = c.groups } else {
            all = OutputCards.build(snapshot, showPlayback: showPlayback) { [self] ref in
                guard deviceID(of: ref) == "xt", let tm = tmChannel(for: ref) else { return nil }
                return tmState.isStereo(tm)
            }
            outputsCache = (key, all)
        }
        return outputsOnlySignal ? Self.onlyWithSignal(all, active: meters.active) : all
    }

    /// “只看有信号”（第 8.2 节 E1）：每张卡只留有电平的来源，没有来源的卡去掉。只在收得到电平时生效。
    static func onlyWithSignal(_ groups: [DeviceOutputs], active: Set<ChannelRef>) -> [DeviceOutputs] {
        groups.compactMap { g in
            var g = g
            g.cards = g.cards.compactMap { c in
                var c = c
                c.sources = c.sources.filter { $0.refs.contains(where: active.contains) }
                return c.sources.isEmpty ? nil : c
            }
            return g.cards.isEmpty ? nil : g
        }
    }

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
