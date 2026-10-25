import Foundation
import RMECore

/// 本工作室的拓扑与约束（文档第 6.1 节端口登记表）。接头类型是占位，按实物改。
/// 12Mic 与 XTC 的客户端接入前，用 `demoDevices()` 占位，路由一律标 unknown，界面明示“演示数据”。
public enum StudioSetup {
    static func port(_ id: String, _ name: String, _ type: PortType, _ dir: Direction, _ conn: Connector, _ n: Int) -> RMECore.Port {
        RMECore.Port(id: id, deviceID: String(id.split(separator: ".")[0]), name: name, type: type, direction: dir,
             connector: conn, singleSpeedChannels: n)
    }

    public static func topology() -> Topology {
        let xt = Device(id: "xt", model: .madifaceXT, name: "MADIface XT", ports: [
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
        let mic12 = Device(id: "12mic", model: .twelveMic, name: "12Mic", ports: [
            port("12mic.analog.in", "Mic 1–12", .analog, .input, .combo, 12),
            port("12mic.madi_optical.in", "MADI 光口输入", .madiOptical, .input, .sfp, 64),
            port("12mic.madi_coaxial.in", "MADI 同轴输入", .madiCoaxial, .input, .bnc, 64),
            port("12mic.madi_optical.out", "MADI 光口输出", .madiOptical, .output, .sfp, 64),
            port("12mic.madi_coaxial.out", "MADI 同轴输出", .madiCoaxial, .output, .bnc, 64),
            port("12mic.phones.out", "耳机", .analog, .output, .trs, 2),
        ])
        let xtc = Device(id: "xtc", model: .octamicXTC, name: "OctaMic XTC", ports: [
            port("xtc.mic.in", "Mic 1–8", .analog, .input, .combo, 8),
            port("xtc.madi.in", "MADI 输入", .madiOptical, .input, .sc, 64),
            port("xtc.madi.out", "MADI 输出", .madiOptical, .output, .sc, 64),
            port("xtc.adat1.out", "ADAT 1 输出", .adat, .output, .toslink, 8),
            port("xtc.adat2.out", "ADAT 2 输出", .adat, .output, .toslink, 8),
        ])
        let p16 = Device(id: "p16i", model: .p16i, name: "POWERPLAY P16-I", ports: [
            port("p16i.adat_a.in", "ADAT A", .adat, .input, .toslink, 8),
            port("p16i.adat_b.in", "ADAT B", .adat, .input, .toslink, 8),
        ])
        return Topology(devices: [xt, mic12, xtc, p16], links: [
            Link(id: "L1", from: "12mic.madi_optical.out", to: "xt.madi1.in"),
            Link(id: "L2", from: "xt.madi1.out", to: "12mic.madi_optical.in"),
            Link(id: "L3", from: "xt.madi2.out", to: "xtc.madi.in"),
            Link(id: "L4", from: "xtc.madi.out", to: "xt.madi2.in"),
            Link(id: "L5", from: "xtc.adat1.out", to: "p16i.adat_a.in"),
        ])
    }

    /// 各设备能做的内部路由（文档第 7.5 节），路径搜索据此生成候选边。
    public static let capabilities = [
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

    public static let terminals = [
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
        return ["12mic": mic12, "xtc": xtc]
    }

    /// XT 读取前的占位快照（无路由）。
    public static func emptyXT(reason: String) -> DeviceSnapshot {
        let src = FactSource(deviceID: "xt", interface: "totalmix-osc", reference: reason)
        return DeviceSnapshot(deviceID: "xt", reachable: false,
                              clock: ClockState(configuredRate: .unknown(src), source: .unknown(src)))
    }

    public static func snapshot(xt: DeviceSnapshot, others: [String: DeviceSnapshot] = demoDevices()) -> SystemSnapshot {
        var devices = others
        devices["xt"] = xt
        return SystemSnapshot(topology: topology(), devices: devices, capabilities: capabilities, terminals: terminals,
                              concurrency: concurrency)
    }
}
