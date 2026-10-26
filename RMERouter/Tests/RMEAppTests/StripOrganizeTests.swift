import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 通道条的屏蔽与搜索（文档第 6.4.5 节）。
@MainActor
final class StripOrganizeTests: XCTestCase {
    var fake: ChannelStripTests.FakeTM!

    func loaded(_ defaults: UserDefaults) async -> AppModel {
        let fake = ChannelStripTests.FakeTM()
        self.fake = fake
        let m = AppModel(defaults: defaults,
                         makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fake.transport) },
                         makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: XTCAppTests.offlineSession) })
        await m.refresh()
        return m
    }

    /// 屏蔽存进偏好，换一个模型（重开 App）还在；取消屏蔽后清掉。不向设备发任何东西。
    func testHidePersistsAndSendsNothing() async {
        let d = UserDefaults(suiteName: "hide-\(UUID())")!
        let m = await loaded(d)
        let sent = fake.writes.count
        let mic1 = TotalMixChannel(.input, 1), phones = TotalMixChannel(.output, 5)
        m.hideStrips([mic1, phones])
        XCTAssertEqual(m.hiddenStrips, [mic1, phones])
        XCTAssertEqual(fake.writes.count, sent, "屏蔽只影响显示")
        XCTAssertEqual(AppModel(defaults: d).hiddenStrips, [mic1, phones])
        m.unhideStrips([mic1])
        XCTAssertEqual(AppModel(defaults: d).hiddenStrips, [phones])
        m.unhideAllStrips()
        XCTAssertTrue(AppModel(defaults: d).hiddenStrips.isEmpty)
    }

    /// 按名字、通道号搜；被屏蔽的也能搜到并标出来；名字开头匹配的排前面。
    func testSearch() async {
        let m = await loaded(UserDefaults(suiteName: "search-\(UUID())")!)
        XCTAssertEqual(m.searchStrips("phones").first?.strip.tm, TotalMixChannel(.output, 5))
        XCTAssertEqual(m.searchStrips("mic 1").first?.strip.tm, TotalMixChannel(.input, 1))
        XCTAssertEqual(m.searchStrips("输入 1").first?.strip.tm, TotalMixChannel(.input, 1))
        XCTAssertTrue(m.searchStrips("输出 6").contains { $0.strip.tm == TotalMixChannel(.output, 5) }, "立体声右声道号也认")
        XCTAssertTrue(m.searchStrips("").isEmpty)
        XCTAssertTrue(m.searchStrips("没有这个名字").isEmpty)
        m.hideStrips([TotalMixChannel(.output, 5)])
        let hit = m.searchStrips("phones").first
        XCTAssertEqual(hit?.hidden, true)
        XCTAssertTrue(hit?.detail.contains("已屏蔽") == true)
        XCTAssertLessThanOrEqual(m.searchStrips("m", limit: 3).count, 3)
    }

    /// 批量静音、批量设发送电平：一批改动，发送后回读；撤销整批。
    func testBatch() async throws {
        let m = await loaded(UserDefaults(suiteName: "batch-\(UUID())")!)
        let mic1 = TotalMixChannel(.input, 1), m2 = TotalMixChannel(.input, 69), phones = TotalMixChannel(.output, 5)
        XCTAssertNil(m.stageBatchMute([mic1, m2], on: true))
        XCTAssertEqual(m.pendingStrips.count, 2)
        XCTAssertNil(m.stageBatchSend([mic1, m2, phones], to: phones, dB: -20))
        XCTAssertEqual(m.pending.count, 2, "输出条被忽略，两条来源各一条发送")
        let applied = await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
        let batch = try XCTUnwrap(applied)
        XCTAssertTrue(batch.outcomes.values.allSatisfy { $0 == .verified })
        XCTAssertEqual(m.xtSend(from: mic1, to: phones) ?? 0, -20, accuracy: 0.1)
        XCTAssertEqual(m.stripValue(ChannelRef("xt.mic.in", 1), .mute), 1)
    }
}
