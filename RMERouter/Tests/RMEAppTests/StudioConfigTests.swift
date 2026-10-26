import XCTest
@testable import RMECore
@testable import RMEEngine
@testable import RMEAdapters
@testable import RMEApp

/// 设备组成可选（文档第 6.4.6 节）：通用主卡、扩展设备开关。
@MainActor
final class StudioConfigTests: XCTestCase {
    var fake: ChannelStripTests.FakeTM!
    override func tearDown() { StudioConfig.current = StudioConfig() }

    func model(_ d: UserDefaults, _ config: StudioConfig? = nil) async -> AppModel {
        if let config, let data = try? JSONEncoder().encode(config) { d.set(data, forKey: StudioConfig.defaultsKey) }
        let fake = ChannelStripTests.FakeTM()
        self.fake = fake
        let m = AppModel(defaults: d,
                         makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fake.transport) },
                         makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: XTCAppTests.offlineSession) })
        await m.refresh()
        return m
    }

    /// 通用主卡：TotalMix 第 n 路 = xt.in:n / xt.out:n；发送、写入照常；没有 12Mic 时拓扑里没有它。
    func testGenericMainCard() async throws {
        let d = UserDefaults(suiteName: "cfg-\(UUID())")!
        let m = await model(d, StudioConfig(mainCard: .generic, expansions: ["xtc"]))
        XCTAssertEqual(StudioConfig.current.mainCard, .generic)
        XCTAssertNil(m.snapshot.topology.device("12mic"))
        XCTAssertNil(m.snapshot.topology.device("p16i"))
        XCTAssertNotNil(m.snapshot.topology.device("xtc"))
        XCTAssertEqual(m.snapshot.topology.device("xt")?.model, .genericTotalMix)
        XCTAssertEqual(m.xtStrips(.input).first?.ref, ChannelRef("xt.in", 1))
        XCTAssertTrue(m.snapshot.allRoutes().contains { $0.source == ChannelRef("xt.in", 1) }, "混音节点翻译成主卡路由")
        // 写入：输入 1 → 输出 5（Phones 1）发送
        XCTAssertNil(m.stageGain(source: ChannelRef("xt.in", 1), destination: ChannelRef("xt.out", 5), dB: -12))
        let applied = await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
        XCTAssertTrue(applied?.outcomes.values.allSatisfy { $0 == .verified } == true)
        // 路径搜索：主卡内部能路由
        if case .infeasible = PathFinder(snapshot: m.snapshot).find(from: ChannelRef("xt.in", 2), to: ChannelRef("xt.out", 7)) {
            XCTFail("通用主卡内部应能路由")
        }
    }

    /// 关掉的扩展设备：不读取、默认接线里连到它的线不出现；再打开恢复。
    func testToggleExpansions() async throws {
        let d = UserDefaults(suiteName: "cfg2-\(UUID())")!
        let m = await model(d)
        XCTAssertNotNil(m.snapshot.topology.device("12mic"))
        var c = m.studioConfig
        c.expansions.remove("12mic")
        m.studioConfig = c
        XCTAssertNil(m.snapshot.topology.device("12mic"))
        XCTAssertFalse(m.snapshot.topology.links.contains { $0.from.hasPrefix("12mic") || $0.to.hasPrefix("12mic") })
        XCTAssertFalse(m.snapshot.capabilities.contains { $0.deviceID == "12mic" })
        // 存进偏好
        XCTAssertEqual(AppModel(defaults: d).studioConfig.expansions, ["xtc", "p16i"])
        c.expansions.insert("12mic")
        m.studioConfig = c
        XCTAssertNotNil(m.snapshot.topology.device("12mic"))
        XCTAssertTrue(m.snapshot.topology.links.contains { $0.id == "L1" })
    }

    /// 通用主卡的接口和任何类型都能连。
    func testMixedPortConnects() {
        XCTAssertTrue(PortType.mixed.canConnect(to: .madiOptical))
        XCTAssertTrue(PortType.adat.canConnect(to: .mixed))
        XCTAssertFalse(PortType.adat.canConnect(to: .madiOptical))
    }
}
