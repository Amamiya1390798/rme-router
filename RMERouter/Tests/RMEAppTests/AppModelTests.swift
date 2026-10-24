import XCTest
@testable import RMECore
@testable import RMEApp

/// 界面数据层：输出卡的分组与立体声合并、模型状态。不渲染界面、不连网络。
@MainActor
final class AppModelTests: XCTestCase {
    func route(_ src: String, _ sc: Int, _ dst: String, _ dc: Int, _ g: Double = 0, _ e: Evidence = .inferred) -> Route {
        Route(domain: .totalMix, source: ChannelRef(src, sc), destination: ChannelRef(dst, dc), kind: .mixSend(gainDB: g), evidence: e)
    }

    func xt(_ routes: [Route], reachable: Bool = false) -> DeviceSnapshot {
        var d = StudioSetup.emptyXT(reason: "test")
        d.routes = routes
        d.reachable = reachable
        return d
    }

    func testOutputCardsMergeStereoPairsAndListOnlyUsedOutputs() {
        let s = StudioSetup.snapshot(xt: xt([
            // 单声道进立体声：同一来源送左右 → 合并为一张卡，来源一行
            route("xt.mic.in", 1, "xt.phones.out", 1, -6.9), route("xt.mic.in", 1, "xt.phones.out", 2, -6.9),
            // 立体声对进立体声 → 合并，来源显示为一对
            route("xt.madi2.in", 1, "xt.phones.out", 1, -5.4), route("xt.madi2.in", 2, "xt.phones.out", 2, -5.4),
            // 只有一边 → 不合并
            route("xt.madi1.in", 9, "xt.madi1.out", 1), route("xt.madi1.in", 12, "xt.madi1.out", 2),
        ]), others: [:])
        let xtCards = OutputCards.build(s).first { $0.device.id == "xt" }!.cards
        XCTAssertEqual(xtCards.map(\.address), ["xt.phones.out:1-2", "xt.madi1.out:1", "xt.madi1.out:2"])
        XCTAssertEqual(xtCards[0].sources.map(\.label), ["xt.madi2.in:1-2", "xt.mic.in:1"])   // 电平高的在前
        XCTAssertEqual(xtCards[0].port.name, "耳机")
        XCTAssertNil(OutputCards.build(s).first { $0.device.id == "12mic" })                   // 没有路由的设备不出现
    }

    func testPlaybackHiddenByDefault() {
        let s = StudioSetup.snapshot(xt: xt([
            route("xt.playback.in", 73, "xt.madi2.out", 3),                 // 只有回放：不出现
            route("xt.playback.in", 1, "xt.an.out", 1), route("xt.mic.in", 1, "xt.an.out", 1, -29.8),
        ]), others: [:])
        let hidden = OutputCards.build(s, showPlayback: false)[0].cards
        XCTAssertEqual(hidden.map(\.address), ["xt.an.out:1"])
        XCTAssertEqual(hidden[0].sources.map(\.label), ["xt.mic.in:1"])
        XCTAssertEqual(hidden[0].hiddenPlayback, 1)
        let all = OutputCards.build(s, showPlayback: true)[0].cards
        XCTAssertEqual(all.map(\.address), ["xt.an.out:1", "xt.madi2.out:3"])
        XCTAssertEqual(all[0].hiddenPlayback, 0)
    }

    func testCardEvidenceIsWeakestSource() {
        let s = StudioSetup.snapshot(xt: xt([
            route("xt.mic.in", 1, "xt.madi1.out", 1, 0, .confirmed), route("xt.mic.in", 2, "xt.madi1.out", 1, 0, .unknown),
        ]), others: [:])
        XCTAssertEqual(OutputCards.build(s)[0].cards[0].evidence, .unknown)
    }

    func testApplySetsStatusAndDefaultTraceTarget() {
        let model = AppModel(defaults: UserDefaults(suiteName: "rme.test.\(UUID())")!)
        XCTAssertEqual(model.xtStatus, .notLoaded)
        XCTAssertTrue(model.isDemo("12mic"))

        model.apply(xt: xt([route("xt.mic.in", 1, "xt.phones.out", 1)], reachable: false))
        XCTAssertEqual(model.xtStatus, .offlineSaved)
        XCTAssertNotNil(model.lastLoaded)
        XCTAssertEqual(model.traceCandidates.first, ChannelRef("xt.mic.in", 1))   // 拓扑里 XT 在前
        XCTAssertEqual(model.traceTarget, ChannelRef("xt.mic.in", 1))
        XCTAssertEqual(model.snapshot.devices["12mic"]?.routes.count, 12)          // 演示数据保留

        model.apply(xt: xt([], reachable: true))
        XCTAssertEqual(model.xtStatus, .live)
    }

    func testSettingsPersist() {
        let defaults = UserDefaults(suiteName: "rme.test.\(UUID())")!
        let a = AppModel(defaults: defaults)
        a.settings.port = 7001
        a.settings.listenPort = 9001
        let b = AppModel(defaults: defaults)
        XCTAssertEqual(b.settings.port, 7001)
        XCTAssertEqual(b.settings.listenPort, 9001)
    }
}
