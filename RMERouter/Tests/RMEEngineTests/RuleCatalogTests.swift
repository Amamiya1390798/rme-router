import XCTest
@testable import RMECore
@testable import RMEEngine

/// 每条体检规则都要有中文标题、说明、改法与确认方法（体检视图依赖它）。
final class RuleCatalogTests: XCTestCase {
    func testCatalogCoversEveryRule() {
        let ruleIDs = Diagnostics.allRules.map(\.id)
        XCTAssertEqual(Set(ruleIDs), Set(RuleCatalog.all.map(\.id)), "规则与说明表不一致")
        XCTAssertEqual(RuleCatalog.all.count, Set(RuleCatalog.all.map(\.id)).count, "说明表里有重复 ID")
        for info in RuleCatalog.all {
            XCTAssertFalse(info.title.isEmpty, info.id)
            XCTAssertFalse(info.explanation.isEmpty, info.id)
            XCTAssertFalse(info.fix.isEmpty, info.id)
            XCTAssertFalse(info.howToCheck.isEmpty, info.id)
        }
    }

    func testR14UndeterminedWithoutRates() {
        var s = Fixture.golden()
        for k in s.devices.keys { s.devices[k]!.clock.configuredRate = .unknown() }
        XCTAssertEqual(R14SpeedInfo().evaluate(s).map(\.verdict), [.cannotDetermine("读不到任何设备的采样率")])
        XCTAssertEqual(R14SpeedInfo().evaluate(Fixture.golden()).map(\.verdict), [.pass])          // 48 kHz
        XCTAssertTrue(R14SpeedInfo().evaluate(Fixture.golden(rate: 96_000)).allSatisfy(\.verdict.isFail))
    }

    func testR6PassesExplicitlyWhenNothingMissing() {
        let findings = R6ReturnPath().evaluate(Fixture.golden())
        XCTAssertEqual(findings.map(\.verdict), [.pass])
    }
}
