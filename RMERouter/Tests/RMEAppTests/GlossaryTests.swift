import XCTest
@testable import RMEApp

/// TotalMix 对照（文档第 6.8 节）。
final class GlossaryTests: XCTestCase {
    func testSearch() {
        XCTAssertEqual(TotalMixGlossary.search("").count, TotalMixGlossary.sections.count)
        let hits = TotalMixGlossary.search("send level")
        XCTAssertTrue(hits.flatMap(\.rows).contains { $0.en.contains("Send Level Data") })
        XCTAssertTrue(TotalMixGlossary.search("对讲").flatMap(\.rows).count >= 3)
        XCTAssertTrue(TotalMixGlossary.search("不存在的词xyz").isEmpty)
    }

    /// 本 App 依赖的几项一定标成“需要这样设”。
    func testRequiredSettingsMarked() {
        let rows = TotalMixGlossary.sections.flatMap(\.rows)
        for key in ["Enable OSC Control", "Compatibility (Mode)", "In Use"] {
            XCTAssertTrue(rows.contains { $0.en.contains(key) && $0.app == .required }, key)
        }
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count, "没有重复条目")
    }
}
