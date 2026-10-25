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
}
