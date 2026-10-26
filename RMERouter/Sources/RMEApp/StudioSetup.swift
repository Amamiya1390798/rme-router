import Foundation
import RMECore

/// 接线表的存取（阶段 A4）：JSON 文件，默认在 ~/Library/Application Support/RME Router/links.json。
public struct LinkStore: Sendable {
    public var url: URL?

    public init(url: URL?) { self.url = url }

    public static var standard: LinkStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return LinkStore(url: base?.appendingPathComponent("RME Router/links.json"))
    }

    /// 不读写任何文件（测试与出图用）。
    public static let none = LinkStore(url: nil)

    public func load() -> [Link]? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Link].self, from: data)
    }

    public func save(_ links: [Link]?) {
        guard let url else { return }
        if let links {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? enc.encode(links).write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// 本工作室的拓扑与约束（文档第 6.1 节端口登记表）。接头类型是占位，按实物改。
/// 12Mic 与 XTC 的客户端接入前，用 `demoDevices()` 占位，路由一律标 unknown，界面明示“演示数据”。
public enum StudioSetup {
    static func port(_ id: String, _ name: String, _ type: PortType, _ dir: Direction, _ conn: Connector, _ n: Int) -> RMECore.Port {
        RMECore.Port(id: id, deviceID: String(id.split(separator: ".")[0]), name: name, type: type, direction: dir,
             connector: conn, singleSpeedChannels: n)
    }

    /// 按设备组成（第 6.4.6 节）建拓扑：主卡型号决定接口；关掉的扩展设备和连到它的线不出现。
    public static func topology(_ config: StudioConfig = .current) -> Topology {
        var t = fullTopology(mainCard: config.mainCard)
        t.devices = t.devices.filter { config.has($0.id) }
        let ports = Set(t.devices.flatMap(\.ports).map(\.id))
        t.links = t.links.filter { ports.contains($0.from) && ports.contains($0.to) }
        return t
    }

    /// 通用主卡的接口：TotalMix 第 n 路 = 主卡输入 / 输出第 n 路。路数上限按 TotalMix 最大通道数留足。
    static let genericChannels = 256

    static func mainDevice(_ card: MainCard) -> Device {
        switch card {
        case .madifaceXT: return xtDevice
        case .generic:
            return Device(id: "xt", model: .genericTotalMix, name: card.deviceName, ports: [
                port("xt.in", "主卡输入", .mixed, .input, .unspecified, genericChannels),
                port("xt.playback.in", "电脑回放", .usb, .input, .usbC, genericChannels),
                port("xt.out", "主卡输出", .mixed, .output, .unspecified, genericChannels),
            ])
        }
    }

    static func fullTopology(mainCard: MainCard) -> Topology {
        let xt = mainDevice(mainCard)
        return Topology(devices: [xt] + expansionDevices, links: defaultLinks)
    }

    static let xtDevice = Device(id: "xt", model: .madifaceXT, name: "MADIface XT", ports: [
            port("xt.mic.in", "Mic 1–2", .analog, .input, .xlr, 2),
            port("xt.aes.in", "AES 输入", .aes, .input, .xlr, 2),
            port("xt.madi1.in", "MADI 1 输入", .madiOptical, .input, .sc, 64),
            port("xt.madi2.in", "MADI 2 输入", .madiOptical, .input, .sc, 64),
            port("xt.madi3.in", "MADI 3 输入", .madiCoaxial, .input, .bnc, 64),
            port("xt.playback.in", "电脑回放", .usb, .input, .usbC, 198),
            port("xt.an.out", "AN 1/2", .analog, .output, .trs, 2),
            port("xt.aes.out", "AES 输出", .aes, .output, .xlr, 2),
            port("xt.phones.out", "耳机", .analog, .output, .trs, 2),
            port("xt.madi1.out", "MADI 1 输出", .madiOptical, .output, .sc, 64),
            port("xt.madi2.out", "MADI 2 输出", .madiOptical, .output, .sc, 64),
            port("xt.madi3.out", "MADI 3 输出", .madiCoaxial, .output, .bnc, 64),
        ])

    static var expansionDevices: [Device] {
        let mic12 = Device(id: "12mic", model: .twelveMic, name: "12Mic", ports: [
            port("12mic.analog.in", "Mic 1–12", .analog, .input, .combo, 12),
            port("12mic.madi_optical.in", "MADI 光口输入", .madiOptical, .input, .sfp, 64),
            port("12mic.madi_coaxial.in", "MADI 同轴输入", .madiCoaxial, .input, .bnc, 64),
            port("12mic.madi_optical.out", "MADI 光口输出", .madiOptical, .output, .sfp, 64),
            port("12mic.madi_coaxial.out", "MADI 同轴输出", .madiCoaxial, .output, .bnc, 64),
            port("12mic.phones.out", "耳机", .analog, .output, .trs, 2),
            // 第 6.4.1 节补登：后面板 ADAT 输出 ×3
            port("12mic.adat1.out", "ADAT 1 输出", .adat, .output, .toslink, 8),
            port("12mic.adat2.out", "ADAT 2 输出", .adat, .output, .toslink, 8),
            port("12mic.adat3.out", "ADAT 3 输出", .adat, .output, .toslink, 8),
        ])
        let xtc = Device(id: "xtc", model: .octamicXTC, name: "OctaMic XTC", ports: [
            port("xtc.mic.in", "Mic 1–8", .analog, .input, .combo, 8),
            port("xtc.madi.in", "MADI 输入", .madiOptical, .input, .sc, 64),
            port("xtc.madi.out", "MADI 输出", .madiOptical, .output, .sc, 64),
            port("xtc.adat1.out", "ADAT 1 输出", .adat, .output, .toslink, 8),
            port("xtc.adat2.out", "ADAT 2 输出", .adat, .output, .toslink, 8),
            // 第 6.4.1 节补登：ADAT 输入、AES 4 入 4 出（D-sub 25）、前面板耳机 1–2
            port("xtc.adat.in", "ADAT 输入", .adat, .input, .toslink, 8),
            port("xtc.aes.in", "AES 输入 1–4", .aes, .input, .dsub, 8),
            port("xtc.aes.out", "AES 输出 1–4", .aes, .output, .dsub, 8),
            port("xtc.phones.out", "耳机 1–2", .analog, .output, .trs, 4),
        ])
        let p16 = Device(id: "p16i", model: .p16i, name: "POWERPLAY P16-I", ports: [
            port("p16i.adat_a.in", "ADAT A", .adat, .input, .toslink, 8),
            port("p16i.adat_b.in", "ADAT B", .adat, .input, .toslink, 8),
        ])
        return [mic12, xtc, p16]
    }

    /// 默认接线（XT 档案下）；通用主卡没有具体接口，连到主卡的线不出现，在接线页自己加。
    static let defaultLinks = [
        Link(id: "L1", from: "12mic.madi_optical.out", to: "xt.madi1.in"),
        Link(id: "L2", from: "xt.madi1.out", to: "12mic.madi_optical.in"),
        Link(id: "L3", from: "xt.madi2.out", to: "xtc.madi.in"),
        Link(id: "L4", from: "xtc.madi.out", to: "xt.madi2.in"),
        Link(id: "L5", from: "xtc.adat1.out", to: "p16i.adat_a.in"),
    ]

    /// 各设备能做的内部路由（文档第 7.5 节），路径搜索据此生成候选边。
    /// 按设备组成过滤：关掉的设备没有路由能力；主卡能力按型号。
    public static var capabilities: [RoutingCapability] {
        let config = StudioConfig.current
        var caps = allCapabilities.filter { config.has($0.deviceID) && $0.deviceID != "xt" }
        if config.mainCard == .generic {
            caps.insert(RoutingCapability(deviceID: "xt", domain: .totalMix, inputPorts: ["xt.in", "xt.playback.in"], outputPorts: ["xt.out"],
                                          granularity: .channel, kindIsMix: true, access: .readWrite, grade: .a,
                                          reference: "TotalMix Global OSC /mix/…/fader（第 7.1 节），通用主卡"), at: 0)
        } else {
            caps.insert(allCapabilities[0], at: 0)
        }
        return caps
    }

    static let allCapabilities = [
        RoutingCapability(deviceID: "xt", domain: .totalMix,
                          inputPorts: ["xt.mic.in", "xt.aes.in", "xt.madi1.in", "xt.madi2.in", "xt.madi3.in"],
                          outputPorts: ["xt.an.out", "xt.aes.out", "xt.phones.out", "xt.madi1.out", "xt.madi2.out", "xt.madi3.out"],
                          granularity: .channel, kindIsMix: true, access: .readWrite, grade: .a,
                          reference: "TotalMix Global OSC /mix/…/fader（第 7.1 节）"),
        RoutingCapability(deviceID: "12mic", domain: .twelveMic,
                          inputPorts: ["12mic.analog.in", "12mic.madi_optical.in", "12mic.madi_coaxial.in"],
                          outputPorts: ["12mic.madi_optical.out", "12mic.madi_coaxial.out", "12mic.phones.out"],
                          granularity: .channel, kindIsMix: false, access: .readWrite, grade: .a,
                          reference: "12Mic JSON /routing（第 7.3 节）"),
        RoutingCapability(deviceID: "xtc", domain: .xtc,
                          inputPorts: ["xtc.mic.in", "xtc.madi.in"],
                          outputPorts: ["xtc.adat1.out", "xtc.adat2.out", "xtc.madi.out"],
                          granularity: .block(size: 8), kindIsMix: false, access: .manual, grade: .a2,
                          reference: "XTC Digital Routing，协议编号未知：只能在面板上设置"),
    ]

    public static var terminals: [TerminalConstraint] { allTerminals.filter { StudioConfig.current.has($0.deviceID) } }

    static let allTerminals = [
        TerminalConstraint(deviceID: "p16i", allowedSampleRates: [44_100, 48_000], clockInputPort: "p16i.adat_a.in",
                           grade: .a, reference: "Behringer P16-I 产品资料"),
    ]

    public static let concurrency: [String: ControlConcurrencyPolicy] = [
        "12mic": .parallelAllowed, "xtc": .singleControlInput, "xt": .unknown,
    ]

    /// 占位用的 12Mic / XTC 快照：路由取自文档里的已知现象（Mic n → MADI 8+n；XTC ADAT 1 = MADI 输入 1–8），
    /// 证据一律 unknown，直到各自的只读客户端读回真实值。
    public static func demoDevices() -> [String: DeviceSnapshot] {
        let demo = FactSource(interface: "demo", reference: "演示数据")
        let unknownClock = ClockState(configuredRate: .unknown(demo), source: .unknown(demo))
        let mic12 = DeviceSnapshot(
            deviceID: "12mic", reachable: false, clock: unknownClock,
            routes: (1...12).map {
                Route(domain: .twelveMic, source: ChannelRef("12mic.analog.in", $0),
                      destination: ChannelRef("12mic.madi_optical.out", 8 + $0), kind: .passthrough, evidence: .unknown)
            },
            controlPaths: [ControlPath(controller: "this-app", transport: .http(baseURL: "http://12mic.local"),
                                       state: .notProbed, active: false)])
        let xtc = DeviceSnapshot(
            deviceID: "xtc", reachable: false, clock: unknownClock,
            routes: (1...8).map {
                Route(domain: .xtc, source: ChannelRef("xtc.madi.in", $0), destination: ChannelRef("xtc.adat1.out", $0),
                      kind: .blockAssign(size: 8), evidence: .unknown)
            },
            controlPaths: [ControlPath(controller: "totalmix-aux", transport: .midiOverMadi(viaPort: "xtc.madi.in"),
                                       state: .notProbed, active: false)])
        return ["12mic": mic12, "xtc": xtc].filter { StudioConfig.current.has($0.key) }
    }

    /// XT 读取前的占位快照（无路由）。
    public static func emptyXT(reason: String) -> DeviceSnapshot {
        let src = FactSource(deviceID: "xt", interface: "totalmix-osc", reference: reason)
        return DeviceSnapshot(deviceID: "xt", reachable: false,
                              clock: ClockState(configuredRate: .unknown(src), source: .unknown(src)))
    }

    /// links 为 nil 时用默认接线；用户在“接线”页改过的接线由 AppModel 传入（阶段 A4）。
    public static func snapshot(xt: DeviceSnapshot, others: [String: DeviceSnapshot] = demoDevices(),
                                links: [Link]? = nil) -> SystemSnapshot {
        var devices = others
        devices["xt"] = xt
        var topo = topology()
        if let links { topo.links = links }
        return SystemSnapshot(topology: topo, devices: devices, capabilities: capabilities, terminals: terminals,
                              concurrency: concurrency)
    }
}
