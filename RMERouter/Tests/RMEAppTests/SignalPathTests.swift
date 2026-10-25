import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 设备页的“线”（文档第 6.4.4 节）：看路径、在面板上找位置、拖线的含义。用默认接线与演示数据。
@MainActor
final class SignalPathTests: XCTestCase {
    func model() -> AppModel { AppModel(defaults: UserDefaults(suiteName: "path-\(UUID())")!) }
    func conn(_ id: String) -> PanelConnector { PanelLayout.all.flatMap(\.connectors).first { $0.id == id }! }

    func testPathOfTwelveMicMic() {
        let m = model()
        let p = m.signalPath(for: ChannelRef("12mic.analog.in", 3))
        // 12Mic 路由（演示）→ 接线 L1 → XT MADI 1 输入 11 → 录音
        XCTAssertTrue(p.segments.contains { $0.kind == .route("3 → 11") && $0.verified == false })
        XCTAssertTrue(p.segments.contains { $0.kind == .cable(linkID: "L1") && $0.verified == false })
        XCTAssertTrue(p.segments.contains { if case .recording = $0.kind { return $0.from == ChannelRef("xt.madi1.in", 11) }; return false })
        XCTAssertTrue(p.text.hasPrefix("12Mic Mic 3 → "), p.text)
        XCTAssertTrue(p.text.contains("电脑录音"))
    }

    func testPathFromMiddleIncludesUpstream() {
        let p = model().signalPath(for: ChannelRef("xt.madi1.in", 11))
        XCTAssertTrue(p.text.hasPrefix("12Mic Mic 3 → MADIface XT"), p.text)
    }

    func testAnchorOnOtherFaceBecomesTag() {
        let m = model()
        XCTAssertEqual(m.pathAnchor(ChannelRef("12mic.analog.in", 3), face: .front)?.key, "conn:12mic.mic.3")
        let rear = m.pathAnchor(ChannelRef("12mic.analog.in", 3), face: .rear)
        XCTAssertEqual(rear?.key, "edge:12mic")
        XCTAssertEqual(rear?.offFace, "前 · Mic/Line 3（可接乐器 Hi-Z）")
        XCTAssertEqual(m.pathAnchor(ChannelRef("p16i.adat_a.in", 1), face: .rear)?.key, "node:p16i")
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
