import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEEngine
@testable import RMEApp

/// 通道条上调增益（文档第 6.4.3 节）：输入条追到源头话放。
@MainActor
final class StripPreampTests: XCTestCase {
    var fake: ChannelStripTests.FakeTM!

    func model() async -> AppModel {
        let fake = ChannelStripTests.FakeTM()
        self.fake = fake
        let m = AppModel(defaults: UserDefaults(suiteName: "spre-\(UUID())")!,
                         makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fake.transport) },
                         makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: XTCAppTests.offlineSession) })
        await m.refresh()
        return m
    }

    /// XT 自己的 Mic 1：就是 XT 的话放。
    func testXTMicIsItsOwnPreamp() async throws {
        let m = await model()
        let p = try XCTUnwrap(m.stripPreamp(ChannelRef("xt.mic.in", 1)))
        XCTAssertEqual(p.deviceID, "xt")
        XCTAssertEqual(p.preamp.input, ChannelRef("xt.mic.in", 1))
    }

    /// MADI 输入沿接线和路由追到唯一一个外部源头：在那个源头放一路话放，通道条就对应到它。
    func testMadiInputTracesToExternalPreamp() async throws {
        let m = await model()
        let strip = ChannelRef("xt.madi2.in", 1)
        let origins = Set(SignalTrace(snapshot: m.snapshot).upstream(to: strip).compactMap { $0.first?.hop.from })
        let origin = try XCTUnwrap(origins.first)
        XCTAssertEqual(origins.count, 1)
        let dev = try XCTUnwrap(m.snapshot.topology.port(origin.portID)?.deviceID)
        XCTAssertNotEqual(dev, "xt")
        XCTAssertNil(m.stripPreamp(strip), "源头没有话放时不显示")

        var devices = m.snapshot.devices
        let fact = { (v: Double) in Fact<Double>.confirmed(v, FactSource(deviceID: dev, interface: "test", reference: "", observedAt: Date())) }
        devices[dev]!.preamps = [PreampChannel(input: origin, label: .unknown(), gainDB: fact(42), phantom: .unknown(), phase: .unknown(),
                                               hiZ: .unknown(), autoGain: .unknown(), gainGroup: .unknown())]
        m.replaceDevices(devices)
        let p = try XCTUnwrap(m.stripPreamp(strip))
        XCTAssertEqual(p.deviceID, dev)
        XCTAssertEqual(p.preamp.gainDB.knownValue, 42)
    }
}
