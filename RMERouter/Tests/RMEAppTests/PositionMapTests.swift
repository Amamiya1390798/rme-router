import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 2026-10-26 实机测试发现的问题（文档第 7 节规则 7、第 2 节）：按位置映射、没名字的通道、电平格。
@MainActor
final class PositionMapTests: XCTestCase {

    /// 按朋友那台 TotalMix FX 2.10 的实测：MADI 通道名是连续数字（1、2、5/6 … 191/192）。
    func numericNamedState(aesStereo: Bool = true) -> TotalMixState {
        var s = TotalMixState()
        func ch(_ bus: String, _ n: Int, _ name: String?, stereo: Bool) {
            if let name { s.apply(OSCMessage("/\(bus)/\(n - 1)/name", [.string(name)])) }
            s.apply(OSCMessage("/\(bus)/\(n - 1)/stereo", [.float(stereo ? 1 : 0)]))
        }
        ch("input", 1, "Mic 1", stereo: false); ch("input", 2, "Mic 2", stereo: false)
        ch("input", 3, "AES", stereo: aesStereo); ch("input", 4, nil, stereo: false)
        for n in 5 ... 196 { ch("input", n, "\(n - 4)", stereo: false) }
        ch("output", 1, "Main", stereo: true); ch("output", 2, nil, stereo: false)
        ch("output", 3, "AES", stereo: true); ch("output", 4, nil, stereo: false)
        ch("output", 5, "Phones 1", stereo: true); ch("output", 6, nil, stereo: false)
        for n in 7 ... 198 { ch("output", n, "\(n - 6)", stereo: false) }
        return s
    }

    func testLayoutSingleAndDoubleSpeed() throws {
        let inputs = try XCTUnwrap(TotalMixChannelMap.layout(bus: .input, maxNumber: 196))
        XCTAssertEqual(inputs.count, 196)
        XCTAssertEqual(inputs[0], ChannelRef("xt.mic.in", 1))
        XCTAssertEqual(inputs[3], ChannelRef("xt.aes.in", 2))
        XCTAssertEqual(inputs[4], ChannelRef("xt.madi1.in", 1))      // TotalMix 输入 5
        XCTAssertEqual(inputs[68], ChannelRef("xt.madi2.in", 1))     // 69（离线时实测 M2-1 在 69）
        XCTAssertEqual(inputs[132], ChannelRef("xt.madi3.in", 1))    // 133
        let outputs = try XCTUnwrap(TotalMixChannelMap.layout(bus: .output, maxNumber: 198))
        XCTAssertEqual(outputs[4], ChannelRef("xt.phones.out", 1))   // 5 = Phones
        XCTAssertEqual(outputs[6], ChannelRef("xt.madi1.out", 1))    // 7（离线时实测 M1-1 在 7）
        XCTAssertEqual(outputs[134], ChannelRef("xt.madi3.out", 1))  // 135
        XCTAssertEqual(TotalMixChannelMap.layout(bus: .input, maxNumber: 100)?[68], ChannelRef("xt.madi3.in", 1))   // 双速 32 路
        XCTAssertNil(TotalMixChannelMap.layout(bus: .input, maxNumber: 70), "推不出路数时不按位置映射")
    }

    func testNumericNamesMapByPosition() {
        var map = TotalMixChannelMap()
        map.infer(from: numericNamedState())
        XCTAssertEqual(map[TotalMixChannel(.input, 5)]?.ref, ChannelRef("xt.madi1.in", 1))
        XCTAssertEqual(map[TotalMixChannel(.input, 5)]?.evidence, .inferred)
        XCTAssertEqual(map[TotalMixChannel(.input, 196)]?.ref, ChannelRef("xt.madi3.in", 64))
        XCTAssertEqual(map[TotalMixChannel(.output, 198)]?.ref, ChannelRef("xt.madi3.out", 64))
        XCTAssertEqual(map[TotalMixChannel(.input, 1)]?.evidence, .confirmed, "名字 Mic 1 与位置一致")
        XCTAssertEqual(map[TotalMixChannel(.input, 4)]?.ref, ChannelRef("xt.aes.in", 2))
        // 实测的 80 条发送都应能映射：每个输出、输入都有接口
        XCTAssertEqual((1 ... 196).filter { map[TotalMixChannel(.input, $0)] == nil }.count, 0)
        XCTAssertEqual((1 ... 198).filter { map[TotalMixChannel(.output, $0)] == nil }.count, 0)
    }

    func testNameContradictingPositionIsConflict() {
        var s = numericNamedState()
        s.apply(OSCMessage("/input/4/name", [.string("M2-1")]))     // 位置是 MADI 1 第 1 路，名字却说 MADI 2
        var map = TotalMixChannelMap()
        map.infer(from: s)
        XCTAssertEqual(map[TotalMixChannel(.input, 5)]?.ref, ChannelRef("xt.madi1.in", 1))
        XCTAssertEqual(map[TotalMixChannel(.input, 5)]?.evidence, .conflict)
    }

    /// 拆开 AES：右声道 TotalMix 不发名字，也要列出来（实测缺 AES R）。
    func testSplitPairShowsRightChannel() {
        let m = AppModel(defaults: UserDefaults(suiteName: "pos-\(UUID())")!)
        m.tmState = numericNamedState(aesStereo: false)
        var map = TotalMixChannelMap()
        map.infer(from: m.tmState)
        m.xtMap = map
        let names = m.xtStrips(.input).prefix(5).map(\.name)
        XCTAssertEqual(names, ["Mic 1", "Mic 2", "AES", "AES 2", "1"])
        XCTAssertEqual(m.xtStrips(.input)[3].ref, ChannelRef("xt.aes.in", 2))
        // 合回立体声：只剩一条
        m.tmState = numericNamedState(aesStereo: true)
        XCTAssertEqual(m.xtStrips(.input).prefix(4).map(\.name), ["Mic 1", "Mic 2", "AES", "1"])
    }

    /// 电平格：只有值变了的格被改动。
    func testMeterCellsUpdateOnlyChanged() {
        let store = MeterStore()
        let a = ChannelRef("xt.mic.in", 1), b = ChannelRef("xt.mic.in", 2)
        let ca = store.cell(a), cb = store.cell(b)
        store.update([a: -20, b: -30])
        XCTAssertEqual(ca.dB, -20); XCTAssertEqual(cb.dB, -30)
        final class Flag: @unchecked Sendable { var on = false }
        let bChanged = Flag()
        withObservationTracking { _ = cb.dB } onChange: { bChanged.on = true }
        store.update([a: -10, b: -30])
        XCTAssertEqual(ca.dB, -10)
        XCTAssertFalse(bChanged.on, "b 没变，它的电平条不该重画")
    }
}
