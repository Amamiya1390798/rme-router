import XCTest
@testable import RMECore
@testable import RMEEngine
@testable import RMEApp

/// 时钟页数据：读到的显示，读不到的给人工确认方法，摘要与体检同源。
final class ClockReportTests: XCTestCase {
    func snapshotWithLive12Mic() -> SystemSnapshot {
        let src = FactSource(deviceID: "12mic", interface: "test")
        let mic = DeviceSnapshot(
            deviceID: "12mic", reachable: true,
            clock: ClockState(configuredRate: .confirmed(48000, src), source: .confirmed(.port("12mic.madi_optical.in"), src),
                              lock: ["12mic.madi_optical.in": .confirmed(true, src), "12mic.madi_coaxial.in": .confirmed(false, src)],
                              sync: ["12mic.madi_optical.in": .confirmed(true, src)]),
            settings: ["12mic.clock.soundness": .confirmed("Good", src)])
        var others = StudioSetup.demoDevices()
        others["12mic"] = mic
        return StudioSetup.snapshot(xt: StudioSetup.emptyXT(reason: "test"), others: others)
    }

    func testRows() {
        let rows = ClockReport.build(snapshotWithLive12Mic())
        XCTAssertEqual(rows.map(\.deviceID), ["xt", "12mic", "xtc"])      // P16 不参与

        let mic = rows[1]
        XCTAssertEqual(mic.rate?.knownValue, 48000)
        XCTAssertEqual(mic.isMaster, false)
        XCTAssertEqual(mic.sourceText, "跟随MADI 光口输入（来自 MADIface XT 的 MADI 2 输出）")
        XCTAssertEqual(mic.soundness, "Good")
        let optical = mic.inputs.first { $0.portID == "12mic.madi_optical.in" }
        XCTAssertEqual(optical?.lock?.knownValue, true)
        XCTAssertEqual(optical?.sync?.knownValue, true)
        XCTAssertEqual(optical?.upstream, "MADIface XT 的 MADI 2 输出")
        XCTAssertEqual(mic.inputs.first { $0.portID == "12mic.madi_coaxial.in" }?.lock?.knownValue, false)

        let xt = rows[0]
        XCTAssertNil(xt.rate)                                               // Global OSC 没有时钟地址
        XCTAssertNil(xt.sourceText)
        XCTAssertTrue(xt.manualHint.contains("TotalMix"))
        XCTAssertNil(rows[2].rate, "演示数据不显示时钟")
    }

    func testSummaryUsesCheckupRules() {
        let s = ClockReport.summary(snapshotWithLive12Mic())
        XCTAssertEqual(s.map(\.id), ["R1", "R2", "R4", "R5"])
        XCTAssertNotEqual(s[0].status, .pass)                               // XT、XTC 读不到 → 不能判主时钟唯一
    }
}
