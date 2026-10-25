import XCTest
@testable import RMECore
@testable import RMEEngine
@testable import RMEApp

/// 接线表编辑（阶段 A4）：校验、存盘、各处立即生效。
@MainActor
final class WiringTests: XCTestCase {
    var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("rme-wiring-\(UUID())")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func makeModel() -> AppModel {
        AppModel(defaults: UserDefaults(suiteName: "rme.wiring.\(UUID())")!,
                 linkStore: LinkStore(url: dir.appendingPathComponent("links.json")))
    }

    func testAddLinkPersistsAndIsUsedEverywhere() {
        let model = makeModel()
        XCTAssertFalse(model.linksCustomized)
        XCTAssertNil(model.addLink(from: "xtc.adat2.out", to: "p16i.adat_b.in"))
        XCTAssertTrue(model.linksCustomized)
        XCTAssertTrue(model.snapshot.topology.links(into: "p16i.adat_b.in").count == 1)

        let reopened = makeModel()                                          // 重启后仍在
        XCTAssertEqual(Set(reopened.links), Set(model.links))

        // 信号流立即可用：XTC ADAT 2 输出 ⇒ P16 ADAT B
        let up = SignalTrace(snapshot: reopened.snapshot).upstream(to: ChannelRef("p16i.adat_b.in", 1))
        XCTAssertEqual(up.first?.last?.hop.description, "xtc.adat2.out:1 ⇒ p16i.adat_b.in:1")
    }

    func testRejectsInvalidLinks() {
        let model = makeModel()
        XCTAssertNotNil(model.addLink(from: "xtc.adat2.out", to: "xt.madi3.in"))        // ADAT → MADI 同轴
        XCTAssertNotNil(model.addLink(from: "xt.madi1.in", to: "12mic.madi_optical.in")) // 起点是输入
        XCTAssertNotNil(model.addLink(from: "xtc.adat1.out", to: "p16i.adat_a.in"))     // 已经有了 / 输入口已占用
        XCTAssertNotNil(model.addLink(from: "12mic.madi_coaxial.out", to: "12mic.madi_coaxial.in")) // 接回自己
        XCTAssertFalse(model.linksCustomized)
    }

    func testRemoveLinkShowsInCheckupAndResetRestores() {
        let model = makeModel()
        let l5 = model.links.first { $0.to == "p16i.adat_a.in" }!
        model.removeLink(l5.id)
        let r8 = CheckupReport.build(model.snapshot).first { $0.id == "R8" }!
        XCTAssertEqual(r8.status, .problem, "P16 的 ADAT A 没线了，R8 应报问题")

        model.resetLinks()
        XCTAssertFalse(model.linksCustomized)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("links.json").path))
    }

    func testDeviceReadKeepsCustomLinks() {
        let model = makeModel()
        model.addLink(from: "xtc.adat2.out", to: "p16i.adat_b.in")
        model.apply(xt: StudioSetup.emptyXT(reason: "test"))
        XCTAssertEqual(model.snapshot.topology.links(into: "p16i.adat_b.in").count, 1, "读取设备不能把接线改回默认")
    }

    func testIssuesListed() {
        let model = makeModel()
        model.removeLink(model.links.first { $0.from == "xt.madi1.out" }!.id)   // 只留 12Mic → XT 单向
        let issues = model.linkIssues.values.flatMap { $0 }
        XCTAssertTrue(issues.contains(.missingReturnPath))
    }
}
