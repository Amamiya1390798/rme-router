import XCTest
@testable import RMECore
@testable import RMEEngine
@testable import RMEApp

/// 体检报告：按规则分组、排序、状态判定。
final class CheckupReportTests: XCTestCase {
    struct Fixed: DiagnosticRule {
        let id: String
        let severity: Severity
        let verdicts: [Verdict]
        func evaluate(_ s: SystemSnapshot) -> [Finding] {
            verdicts.enumerated().map { Finding(ruleID: id, severity: severity, subject: "s\($0.offset)", verdict: $0.element) }
        }
    }

    func snapshot() -> SystemSnapshot { StudioSetup.snapshot(xt: StudioSetup.emptyXT(reason: "test")) }

    func testStatusAndOrdering() {
        let rules: [any DiagnosticRule] = [
            Fixed(id: "R14", severity: .info, verdicts: [.fail("提示问题")]),
            Fixed(id: "R2", severity: .error, verdicts: [.pass, .cannotDetermine("读不到")]),
            Fixed(id: "R5", severity: .warning, verdicts: [.pass, .fail("x"), .cannotDetermine("y")]),
            Fixed(id: "R1", severity: .error, verdicts: [.fail("两个主时钟")]),
            Fixed(id: "R6", severity: .warning, verdicts: [.pass, .pass]),
            Fixed(id: "R12", severity: .warning, verdicts: []),
        ]
        let r = CheckupReport.build(snapshot(), rules: rules)
        XCTAssertEqual(r.map(\.id), ["R1", "R5", "R14", "R2", "R6", "R12"])
        XCTAssertEqual(r.map(\.status), [.problem, .problem, .problem, .undetermined, .pass, .notApplicable])
        XCTAssertEqual(r[0].info.title, "主时钟唯一")
        XCTAssertEqual(r[1].failures.count, 1)
        XCTAssertEqual(r[1].undetermined.count, 1)
        let c = CheckupReport.counts(r)
        XCTAssertEqual(c.problem, 3)
        XCTAssertEqual(c.undetermined, 1)
        XCTAssertEqual(c.pass, 1)                       // “没有可检查的项”不算通过
    }

    /// 什么都没读到时：不能出现“通过”的读数类规则，设备离线要报出来。
    func testNothingLoadedIsNeverAllGreen() {
        let r = CheckupReport.build(snapshot())
        XCTAssertEqual(r.count, Diagnostics.allRules.count)
        XCTAssertEqual(r.first { $0.id == "R10" }?.status, .problem)       // 设备不可读
        XCTAssertEqual(r.first { $0.id == "R2" }?.status, .undetermined)   // 读不到采样率
        XCTAssertNotEqual(r.first { $0.id == "R1" }?.status, .pass)
        XCTAssertEqual(r.first { $0.id == "R14" }?.status, .undetermined)  // 读不到采样率不能算通过
    }
}
