import Foundation
import RMECore

/// 实机星形拓扑的夹具（阶段 0“黄金配置”的代码形态）。
/// 接头类型是占位，按实物修改；端口名按设备面板。
enum Fixture {
    static let m = FactSource(interface: "fixture")

    static func port(_ id: String, _ dev: String, _ type: PortType, _ dir: Direction, _ conn: Connector, _ n: Int) -> RMECore.Port {
        RMECore.Port(id: id, deviceID: dev, name: id, type: type, direction: dir, connector: conn, singleSpeedChannels: n)
    }

    static func topology() -> Topology {
        let xt = Device(id: "xt", model: .madifaceXT, name: "MADIface XT", ports: [
            port("xt.madi1.in", "xt", .madiOptical, .input, .sc, 64),
            port("xt.madi1.out", "xt", .madiOptical, .output, .sc, 64),
            port("xt.madi2.in", "xt", .madiOptical, .input, .sc, 64),
            port("xt.madi2.out", "xt", .madiOptical, .output, .sc, 64),
            port("xt.madi3.in", "xt", .madiCoaxial, .input, .bnc, 64),
            port("xt.madi3.out", "xt", .madiCoaxial, .output, .bnc, 64),
            // TotalMix 读回的其余硬件口（2026-10-25）；回放 198 路与 TotalMix 输出数一致
            port("xt.mic.in", "xt", .analog, .input, .xlr, 2),
            port("xt.aes.in", "xt", .aes, .input, .xlr, 2),
            port("xt.aes.out", "xt", .aes, .output, .xlr, 2),
            port("xt.an.out", "xt", .analog, .output, .trs, 2),
            port("xt.phones.out", "xt", .analog, .output, .trs, 2),
            port("xt.playback.in", "xt", .usb, .input, .usbC, 198),
        ])
        let mic12 = Device(id: "12mic", model: .twelveMic, name: "12Mic", ports: [
            port("12mic.analog.in", "12mic", .analog, .input, .combo, 12),
            port("12mic.madi_optical.in", "12mic", .madiOptical, .input, .sfp, 64),
            port("12mic.madi_optical.out", "12mic", .madiOptical, .output, .sfp, 64),
            port("12mic.madi_coaxial.in", "12mic", .madiCoaxial, .input, .bnc, 64),
            port("12mic.madi_coaxial.out", "12mic", .madiCoaxial, .output, .bnc, 64),
            port("12mic.phones.out", "12mic", .analog, .output, .trs, 2),
        ])
        let xtc = Device(id: "xtc", model: .octamicXTC, name: "OctaMic XTC", ports: [
            port("xtc.mic.in", "xtc", .analog, .input, .combo, 8),
            port("xtc.madi.in", "xtc", .madiOptical, .input, .sc, 64),
            port("xtc.madi.out", "xtc", .madiOptical, .output, .sc, 64),
            port("xtc.adat1.out", "xtc", .adat, .output, .toslink, 8),
            port("xtc.adat2.out", "xtc", .adat, .output, .toslink, 8),
        ])
        let p16 = Device(id: "p16i", model: .p16i, name: "POWERPLAY P16-I", ports: [
            port("p16i.adat_a.in", "p16i", .adat, .input, .toslink, 8),
            port("p16i.adat_b.in", "p16i", .adat, .input, .toslink, 8),
        ])
        return Topology(devices: [xt, mic12, xtc, p16], links: [
            Link(id: "L1", from: "12mic.madi_optical.out", to: "xt.madi1.in"),
            Link(id: "L2", from: "xt.madi1.out", to: "12mic.madi_optical.in"),
            Link(id: "L3", from: "xt.madi2.out", to: "xtc.madi.in"),
            Link(id: "L4", from: "xtc.madi.out", to: "xt.madi2.in"),
            Link(id: "L5", from: "xtc.adat1.out", to: "p16i.adat_a.in"),
        ])
    }

    static func madi(_ rate: Int, _ frame: MadiFrame = .frame48k) -> Fact<StreamFormat> {
        .confirmed(StreamFormat(sampleRate: rate, madiFrame: frame, channelMode: .ch64), m)
    }

    static func adat(_ rate: Int) -> Fact<StreamFormat> {
        .confirmed(StreamFormat(sampleRate: rate), m)
    }

    /// 黄金配置：全系统 48 kHz，XT 内部时钟为主；12Mic Mic n → MADI 8+n（与实机现象一致）；
    /// XTC 的 ADAT 1 输出 = MADI In 1-8。
    static func golden(rate: Int = 48_000, xtcRate: Int? = nil) -> SystemSnapshot {
        let xtcR = xtcRate ?? rate
        let xt = DeviceSnapshot(
            deviceID: "xt", reachable: true,
            clock: ClockState(configuredRate: .confirmed(rate, m), source: .confirmed(.internal, m)),
            portFormats: ["xt.madi1.out": madi(rate), "xt.madi1.in": madi(rate),
                          "xt.madi2.out": madi(rate), "xt.madi2.in": madi(rate)],
            controlPaths: [ControlPath(controller: "this-app", transport: .osc(host: "127.0.0.1", port: 7001),
                                       state: .online, active: true)])
        let mic12Routes = (1...12).map {
            Route(domain: .twelveMic, source: ChannelRef("12mic.analog.in", $0),
                  destination: ChannelRef("12mic.madi_optical.out", 8 + $0), kind: .passthrough, evidence: .confirmed)
        }
        let mic12 = DeviceSnapshot(
            deviceID: "12mic", reachable: true,
            clock: ClockState(configuredRate: .confirmed(rate, m), source: .confirmed(.port("12mic.madi_optical.in"), m),
                              lock: ["12mic.madi_optical.in": .confirmed(true, m)],
                              sync: ["12mic.madi_optical.in": .confirmed(true, m)]),
            portFormats: ["12mic.madi_optical.out": madi(rate), "12mic.madi_optical.in": madi(rate)],
            routes: mic12Routes,
            controlPaths: [ControlPath(controller: "this-app", transport: .http(baseURL: "http://12mic.local"),
                                       state: .online, active: true)])
        let xtcRoutes = (1...8).map {
            Route(domain: .xtc, source: ChannelRef("xtc.madi.in", $0), destination: ChannelRef("xtc.adat1.out", $0),
                  kind: .blockAssign(size: 8), evidence: .confirmed)
        }
        let xtc = DeviceSnapshot(
            deviceID: "xtc", reachable: true,
            clock: ClockState(configuredRate: .confirmed(xtcR, m), source: .confirmed(.port("xtc.madi.in"), m),
                              lock: ["xtc.madi.in": .confirmed(true, m)], sync: ["xtc.madi.in": .confirmed(true, m)]),
            portFormats: ["xtc.madi.in": madi(xtcR), "xtc.madi.out": madi(xtcR), "xtc.adat1.out": adat(xtcR)],
            routes: xtcRoutes,
            controlPaths: [ControlPath(controller: "totalmix-aux", transport: .midiOverMadi(viaPort: "xtc.madi.in"),
                                       state: .online, active: true)],
            settings: ["xtc.adatOut1.source": .confirmed("madiIn.1-8", m)])

        let caps = [
            RoutingCapability(deviceID: "xt", domain: .totalMix,
                              inputPorts: ["xt.madi1.in", "xt.madi2.in", "xt.madi3.in"],
                              outputPorts: ["xt.madi1.out", "xt.madi2.out", "xt.madi3.out"],
                              granularity: .channel, kindIsMix: true, access: .unknown, grade: .d,
                              reference: "TotalMix OSC 矩阵写入未证实"),
            RoutingCapability(deviceID: "12mic", domain: .twelveMic,
                              inputPorts: ["12mic.analog.in", "12mic.madi_optical.in"],
                              outputPorts: ["12mic.madi_optical.out", "12mic.madi_coaxial.out"],
                              granularity: .channel, kindIsMix: false, access: .readWrite, grade: .a,
                              reference: "12Mic JSON /routing"),
            RoutingCapability(deviceID: "xtc", domain: .xtc,
                              inputPorts: ["xtc.madi.in", "xtc.mic.in"],
                              outputPorts: ["xtc.adat1.out", "xtc.adat2.out", "xtc.madi.out"],
                              granularity: .block(size: 8), kindIsMix: false, access: .manual, grade: .a2,
                              reference: "XTC Digital Routing，协议编号未知"),
        ]
        return SystemSnapshot(
            topology: topology(),
            devices: ["xt": xt, "12mic": mic12, "xtc": xtc],
            capabilities: caps,
            terminals: [TerminalConstraint(deviceID: "p16i", allowedSampleRates: [44_100, 48_000],
                                           clockInputPort: "p16i.adat_a.in", grade: .a,
                                           reference: "Behringer P16-I 产品资料")],
            concurrency: ["12mic": .parallelAllowed, "xtc": .singleControlInput, "xt": .unknown],
            expectations: ["xtc.adatOut1.source": "madiIn.1-8"],
            auxDeviceFirstChannel: ["12mic": ChannelRef("xt.madi1.in", 9)])
    }
}
