import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 核对机制（文档第 6.5 节）：信号核对、线缆状态、核对结果存盘。电平用 MeterStore 直接模拟。
@MainActor
final class IdentifyTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() { defaults = UserDefaults(suiteName: "identify-\(UUID())")! }

    func model() -> AppModel {
        let m = AppModel(defaults: defaults)
        m.meters.deviceLive = true
        return m
    }

    let mic3 = ChannelRef("12mic.analog.in", 3)
    let expected = ChannelRef("xt.madi1.in", 11)   // 演示路由 Mic 3 → MADI 光口输出 11，接线 L1 → XT MADI 1 输入 11

    func testExpectedFollowsWiringAndRouting() {
        let m = model()
        let e = m.expectedXTInputs(from: mic3)
        XCTAssertEqual(Array(e.keys), [expected])
        XCTAssertEqual(e[expected]?.map(\.from), ["12mic.madi_optical.out"])
        XCTAssertEqual(e[expected]?.map(\.to), ["xt.madi1.in"])
        XCTAssertEqual(Array(m.expectedXTInputs(from: ChannelRef("xt.mic.in", 1)).keys), [ChannelRef("xt.mic.in", 1)])
        XCTAssertTrue(m.expectedXTInputs(from: ChannelRef("12mic.analog.in", 12)).isEmpty == false)
    }

    func testNeedsLevels() {
        let m = AppModel(defaults: defaults)     // 没有电平
        XCTAssertEqual(m.startIdentify(source: mic3), .noLevels)
    }

    func testMatchMarksCableVerified() throws {
        let m = model()
        let t0 = Date()
        m.meters.update([expected: -80, ChannelRef("xt.madi1.in", 12): -75], now: t0)
        XCTAssertNil(m.startIdentify(source: mic3, now: t0))
        m.meters.update([expected: -18, ChannelRef("xt.madi1.in", 12): -74], now: t0.addingTimeInterval(1))
        m.identifySample(now: t0.addingTimeInterval(1))
        m.finishIdentify(now: t0.addingTimeInterval(2))
        XCTAssertEqual(m.identify?.outcome, .match(expected))
        let l1 = try XCTUnwrap(m.links.first { $0.id == "L1" })
        guard case let .verified(v) = m.cableStatus(l1) else { return XCTFail("\(m.cableStatus(l1))") }
        XCTAssertEqual(v.method, .signal)
        XCTAssertEqual(v.detail, "12Mic Mic 3 → MADIface XT MADI 1 输入 11")
        // 存盘：重新打开还在
        XCTAssertEqual(AppModel(defaults: defaults).cableStatus(l1), .verified(v))
    }

    func testElsewhereReportsWhereItArrived() {
        let m = model()
        let t0 = Date()
        let wrong = ChannelRef("xt.madi2.in", 11)
        m.meters.update([expected: -90, wrong: -90], now: t0)
        m.startIdentify(source: mic3, now: t0)
        m.meters.update([expected: -90, wrong: -12], now: t0.addingTimeInterval(1))
        m.identifySample(now: t0.addingTimeInterval(1))
        m.finishIdentify()
        XCTAssertEqual(m.identify?.outcome, .elsewhere(found: wrong, expected: [expected]))
        XCTAssertTrue(m.linkVerifications.isEmpty, "对不上不能记为已核对")
    }

    func testNothingArrivedAndTimeout() {
        let m = model()
        let t0 = Date()
        m.meters.update([expected: -60], now: t0)
        m.startIdentify(source: mic3, now: t0)
        m.meters.update([expected: -45], now: t0.addingTimeInterval(1))   // 只升了 15 dB：不算
        m.identifySample(now: t0.addingTimeInterval(1))
        m.meters.update([expected: -46], now: t0.addingTimeInterval(11))
        m.identifySample(now: t0.addingTimeInterval(11))                  // 到 10 秒自动结束
        XCTAssertEqual(m.identify?.outcome, IdentifyTest.Outcome.none)
    }

    func testLockSeenAndDeclared() throws {
        let m = model()
        let l1 = try XCTUnwrap(m.links.first { $0.id == "L1" }), l2 = try XCTUnwrap(m.links.first { $0.id == "L2" })
        XCTAssertEqual(m.cableStatus(l2), .declared)
        // 12Mic 报告它的光口输入已锁定（L2：XT MADI 1 输出 → 12Mic 光口输入）
        let src = FactSource(deviceID: "12mic", interface: "12mic-json")
        m.apply(twelveMic: DeviceSnapshot(deviceID: "12mic", reachable: true,
                                          clock: ClockState(configuredRate: .confirmed(48_000, src), source: .confirmed(.internal, src),
                                                            lock: ["12mic.madi_optical.in": .confirmed(true, src)])))
        XCTAssertEqual(m.cableStatus(l2), .lockSeen)
        XCTAssertEqual(m.cableStatus(l1), .declared)
        m.confirmLinkByUser(l1)
        if case .verified(let v) = m.cableStatus(l1) { XCTAssertEqual(v.method, .user) } else { XCTFail() }
    }
}
