import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 电平（文档第 7.7 节）：离线或过期显示“无信号”而不是 0；映射到链路地址。
@MainActor
final class MeterTests: XCTestCase {
    let mic1 = ChannelRef("xt.mic.in", 1)

    func testNoSignalUnlessLiveAndFresh() {
        let m = MeterStore()
        let t0 = Date()
        m.update([mic1: -12], now: t0)
        XCTAssertNil(m.level(mic1, now: t0), "设备离线：无信号")
        m.deviceLive = true
        XCTAssertEqual(m.level(mic1, now: t0.addingTimeInterval(1)), -12)
        XCTAssertNil(m.level(mic1, now: t0.addingTimeInterval(3)), "2 秒没有新电平：无信号")
        m.update([mic1: -12], now: t0.addingTimeInterval(4))                // 值没变：不算新数据
        XCTAssertNil(m.level(mic1, now: t0.addingTimeInterval(4)))
    }

    func testHintWhenLiveButNothingArrives() {
        let m = MeterStore()
        let t0 = Date()
        m.deviceLive = true
        m.startPolling(now: t0)
        XCTAssertFalse(m.likelyLevelSendingOff(now: t0.addingTimeInterval(1)))
        XCTAssertTrue(m.likelyLevelSendingOff(now: t0.addingTimeInterval(5)))
        m.update([mic1: -40], now: t0.addingTimeInterval(6))
        XCTAssertFalse(m.likelyLevelSendingOff(now: t0.addingTimeInterval(7)))
    }

    func testPollMapsTotalMixChannels() async throws {
        let tm = WriteTests.FakeTotalMix()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [WriteTests.No12Mic.self]
        let session = URLSession(configuration: cfg)
        let model = AppModel(defaults: UserDefaults(suiteName: "rme.meter.\(UUID())")!,
                             makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: tm.transport) },
                             makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: session) })
        await model.refresh()
        tm.transport.inject([OSCMessage("/level/in/0", [.float(-12)]), OSCMessage("/level/pb/2", [.float(-30)]),
                             OSCMessage("/level/out/4", [.float(-3)])])
        try await Task.sleep(for: .milliseconds(50))
        await model.pollMetersOnce()
        XCTAssertEqual(model.meters.levels[mic1], -12)
        XCTAssertEqual(model.meters.levels[ChannelRef("xt.playback.in", 3)], -30)
        XCTAssertEqual(model.meters.levels[ChannelRef("xt.phones.out", 1)], -3)
        XCTAssertFalse(model.meters.deviceLive, "假 TotalMix 报告 XT 未连接")
        XCTAssertNil(model.meters.level(mic1))
    }
}
