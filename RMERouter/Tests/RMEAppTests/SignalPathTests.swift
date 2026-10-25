import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 设备页的“线”（文档第 6.4.4 节）：看路径、在面板上找位置、拖线的含义。用默认接线与演示数据。
@MainActor
final class SignalPathTests: XCTestCase {
    func model() -> AppModel { AppModel(defaults: UserDefaults(suiteName: "path-\(UUID())")!) }
    func conn(_ id: String) -> PanelConnector { PanelLayout.all.flatMap(\.connectors).first { $0.id == id }! }

    var fake: ChannelStripTests.FakeTM!

    func loaded() async -> AppModel {
        let fake = ChannelStripTests.FakeTM()
        self.fake = fake
        let m = AppModel(defaults: UserDefaults(suiteName: "focus-\(UUID())")!,
                         makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fake.transport) },
                         makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: XTCAppTests.offlineSession) })
        await m.refresh()
        return m
    }

    /// 选 XT Mic 1：高亮 Mic 1 与它送达的耳机，画一条线。
    func testFocusMic() async {
        let m = await loaded()
        let f = m.stripFocus(connector: conn("xt.mic.1"))
        XCTAssertEqual(f.inputs, [TotalMixChannel(.input, 1)])
        XCTAssertEqual(f.outputs, [TotalMixChannel(.output, 5)])
        XCTAssertEqual(f.edges.map(\.to), [TotalMixChannel(.output, 5)])
        XCTAssertEqual(f.edges.first?.dB ?? 0, -6.9, accuracy: 0.01)
    }

    /// 选耳机输出口：往上游找到两条来源（Mic 1、M2-1/2 立体声并成一条）。
    func testFocusOutputFindsSources() async {
        let m = await loaded()
        let f = m.stripFocus(connector: conn("xt.phones"))
        XCTAssertEqual(f.inputs, [TotalMixChannel(.input, 1), TotalMixChannel(.input, 69)])
        XCTAssertEqual(f.edges.count, 2)
    }

    /// 选整个 MADI 2 输入口：高亮它的通道条，面板上只亮接进来的线（XTC → XT，L4）。
    func testFocusWholeMadiPort() async {
        let m = await loaded()
        let f = m.stripFocus(connector: conn("xt.madi2.in"))
        XCTAssertTrue(f.inputs.contains(TotalMixChannel(.input, 69)))
        XCTAssertFalse(f.inputs.contains(TotalMixChannel(.input, 70)), "立体声右声道并进左声道")
        XCTAssertTrue(f.links.contains("L4"))
        // 只选其中第 1 路
        XCTAssertEqual(m.stripFocus(connector: conn("xt.madi2.in"), channel: 1).inputs, [TotalMixChannel(.input, 69)])
    }

    /// 整个 MADI 口超过 8 路：默认只看有发送的通道条；要全部时照旧。
    func testFocusActiveOnly() async {
        let m = await loaded()
        let all = m.stripFocus(connector: conn("xt.madi2.in"), activeOnly: false)
        let auto = m.stripFocus(connector: conn("xt.madi2.in"))
        XCTAssertFalse(all.activeOnly)
        XCTAssertTrue(auto.activeOnly)
        XCTAssertEqual(auto.total, all.stripCount)
        XCTAssertLessThanOrEqual(auto.stripCount, all.stripCount)
        XCTAssertEqual(auto.edges, all.edges, "线不受影响")
        for e in auto.edges {
            XCTAssertTrue(auto.inputs.contains(e.from) || auto.playbacks.contains(e.from))
            XCTAssertTrue(auto.outputs.contains(e.to))
        }
        // 单个麦克风只有 1 路：不过滤
        XCTAssertFalse(m.stripFocus(connector: conn("xt.mic.1")).activeOnly)
        // 一路都不在用（Mic 2 没有发送、没有信号）：强制只看在用的也照旧显示全部
        let idle = m.stripFocus(connector: conn("xt.mic.2"), activeOnly: true)
        XCTAssertTrue(idle.edges.isEmpty)
        XCTAssertFalse(idle.activeOnly)
        XCTAssertEqual(idle.stripCount, idle.total)
    }

    func testDragIntents() {
        let m = model()
        // 输出口 → 另一台设备的输入口 = 接线（已有的拒绝）
        XCTAssertEqual(m.dragIntent(from: conn("12mic.coax.out"), to: conn("xt.madi3.in")),
                       .addLink(from: "12mic.madi_coaxial.out", to: "xt.madi3.in"))
        XCTAssertEqual(m.dragIntent(from: conn("xt.madi1.out"), to: conn("12mic.sfp")), .rejected("这根线已经有了"))
        // 麦克风 → 输出口 = 送一路声音
        XCTAssertEqual(m.dragIntent(from: conn("12mic.mic.3"), to: conn("xt.phones")),
                       .send(from: ChannelRef("12mic.analog.in", 3), to: ChannelRef("xt.phones.out", 1)))
        XCTAssertEqual(m.dragIntent(from: conn("xt.mic.1"), to: conn("xt.an.out.2")),
                       .send(from: ChannelRef("xt.mic.in", 1), to: ChannelRef("xt.an.out", 2)))
        // 不合法
        XCTAssertEqual(m.dragIntent(from: conn("xt.mic.1"), to: conn("xt.mic.1")), .rejected("同一个接口"))
        if case .rejected = m.dragIntent(from: conn("xt.dc"), to: conn("xt.madi1.out")) {} else { XCTFail() }
        if case .rejected = m.dragIntent(from: conn("xt.mic.1"), to: conn("xt.mic.2")) {} else { XCTFail("输入拖到输入不接受") }
    }
}
