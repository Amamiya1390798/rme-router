import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// “设备”页（文档第 6.4 节）：接口清单与拓扑自洽、线缆两端、TotalMix 式通道条。
@MainActor
final class DeviceViewTests: XCTestCase {
    let topo = StudioSetup.topology()
    let panelDevices = ["xt", "12mic", "xtc"]

    /// 面板上的每个音频接口都指向拓扑里存在的端口；坐标在图内。
    func testConnectorsPointToRealPorts() {
        for p in PanelLayout.all {
            for c in p.connectors {
                XCTAssertTrue((0 ... 1).contains(c.x) && (0 ... 1).contains(c.y) && c.size > 0 && c.size < 0.2, c.id)
                for port in c.ports {
                    XCTAssertNotNil(topo.port(port), "\(c.id) → \(port) 不在拓扑里")
                    XCTAssertEqual(topo.port(port)?.deviceID, p.deviceID, c.id)
                }
                if c.kind == .audio { XCTAssertFalse(c.ports.isEmpty, "\(c.id) 是音频接口却没有端口") }
                if let ch = c.channel, let port = c.ports.first { XCTAssertTrue((1 ... (topo.port(port)?.singleSpeedChannels ?? 0)).contains(ch), c.id) }
            }
        }
        XCTAssertEqual(Set(PanelLayout.all.flatMap(\.connectors).map(\.id)).count, PanelLayout.all.flatMap(\.connectors).count, "接口 id 重复")
    }

    /// 每个实物音频端口在面板上有且只有一个位置：整口一个，或按通道各一个且覆盖全部通道。
    func testEveryPhysicalPortHasExactlyOnePlace() {
        for d in topo.devices where panelDevices.contains(d.id) {
            for port in d.ports where port.type != .usb {     // xt.playback.in 是电脑回放，不是实物接口
                let cs = PanelLayout.all.flatMap(\.connectors).filter { $0.ports.contains(port.id) }
                let whole = cs.filter { $0.channel == nil }
                let perChannel = cs.compactMap(\.channel)
                if whole.isEmpty {
                    XCTAssertEqual(Set(perChannel).count, perChannel.count, "\(port.id) 通道重复")
                    XCTAssertFalse(perChannel.isEmpty, "\(port.id) 在面板上没有位置")
                } else {
                    XCTAssertEqual(whole.count, 1, "\(port.id) 在面板上出现 \(whole.count) 次")
                    XCTAssertTrue(perChannel.isEmpty, "\(port.id) 既有整口又有单通道")
                }
            }
        }
        // 单通道接口覆盖全部通道
        for (port, n) in [("xt.mic.in", 2), ("12mic.analog.in", 12), ("xtc.mic.in", 8), ("xt.an.out", 2)] {
            let chans = Set(PanelLayout.all.flatMap(\.connectors).filter { $0.ports == [port] }.compactMap(\.channel))
            XCTAssertEqual(chans, Set(1 ... n), port)
        }
    }

    func testPanelImagesExist() {
        for p in PanelLayout.all { XCTAssertNotNil(PanelLayout.image(p.image), p.image) }
    }

    func testCablesForDefaultWiring() {
        let m = AppModel(defaults: UserDefaults(suiteName: "dv-\(UUID())")!)
        let rear = m.cables(face: .rear)
        XCTAssertEqual(rear.count, m.links.count + 1)            // 每根线 + XT 到 Mac 的 USB
        XCTAssertEqual(rear.first { $0.id == "L1" }?.from, "conn:12mic.sfp")
        XCTAssertEqual(rear.first { $0.id == "L1" }?.to, "conn:xt.madi2.in")
        XCTAssertEqual(rear.first { $0.to == "node:p16i" }?.from, "conn:xtc.adat1.out")
        XCTAssertEqual(rear.first { $0.id == "usb" }?.to, "node:mac")
        XCTAssertFalse(rear.first { $0.id == "L1" }?.issues.isEmpty ?? true, "SFP(LC) 对 SC 应提示转接")
        XCTAssertTrue(m.cables(face: .front).isEmpty)
    }

    func testChannelRefText() {
        let r = ChannelRef("xt.madi2.in", 9)
        XCTAssertEqual(ChannelRef(text: r.description), r)
        XCTAssertNil(ChannelRef(text: "xt.madi2.in"))
    }

    /// TotalMix 式通道条：立体声并成一条，回放映射到 xt.playback.in，读回送到某输出的电平。
    func testStripsFromTotalMix() async {
        let fake = ChannelStripTests.FakeTM()
        let m = AppModel(defaults: UserDefaults(suiteName: "dv-\(UUID())")!,
                         makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fake.transport) },
                         makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: XTCAppTests.offlineSession) })
        await m.refresh()
        let inputs = m.xtStrips(.input)
        XCTAssertEqual(inputs.map(\.name), ["Mic 1", "M2-1/2"])
        XCTAssertEqual(inputs.last?.stereo, true)
        XCTAssertEqual(inputs.last?.ref, ChannelRef("xt.madi2.in", 1))
        XCTAssertEqual(m.xtStrips(.playback).first?.ref, ChannelRef("xt.playback.in", 5))
        let phones = TotalMixChannel(.output, 5)
        XCTAssertEqual(m.xtStrips(.output).map(\.name), ["Phones 1", "M1-1"])
        XCTAssertEqual(m.xtSend(from: TotalMixChannel(.input, 1), to: phones) ?? 0, -6.9, accuracy: 0.01)
        XCTAssertNil(m.xtSend(from: TotalMixChannel(.input, 1), to: TotalMixChannel(.output, 7)))
        XCTAssertNil(m.hasSignal(port: "xt.mic.in"))             // 收不到电平：无法判断，不说“没信号”
    }
}
