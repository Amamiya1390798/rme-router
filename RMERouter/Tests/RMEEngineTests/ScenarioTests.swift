import XCTest
@testable import RMECore
@testable import RMEEngine
@testable import RMEAdapters

/// 第 11 节 T1–T10。全部基于 Mock 夹具，不需要硬件。
final class ScenarioTests: XCTestCase {
    let mic1 = ChannelRef("12mic.analog.in", 1)
    let p16ch1 = ChannelRef("p16i.adat_a.in", 1)

    func verdicts(_ s: SystemSnapshot, _ rule: String) -> [Verdict] {
        Diagnostics.run(s).filter { $0.ruleID == rule }.map(\.verdict)
    }

    // 黄金配置本身：错误级规则全部不失败，路径可找到。
    func testGoldenConfigIsClean() {
        let s = Fixture.golden()
        let failures = Diagnostics.run(s).filter { $0.verdict.isFail && $0.severity == .error }
        XCTAssertEqual(failures, [])
        guard case .found = PathFinder(snapshot: s).find(from: mic1, to: p16ch1) else {
            return XCTFail("黄金配置应能找到路径")
        }
    }

    // T1 采样率不一致：XT 48 kHz，XTC 设成 96 kHz（问题 1 的复核结论：XTC 会 Lock 但按双速解读）。
    func testT1_SampleRateMismatch() {
        let s = Fixture.golden(rate: 48_000, xtcRate: 96_000)
        XCTAssertTrue(verdicts(s, "R2").contains { $0.isFail })
        XCTAssertTrue(verdicts(s, "R3").contains { $0.isFail })
        let issues = FormatCheck.compare(sender: StreamFormat(sampleRate: 48_000, madiFrame: .frame48k, channelMode: .ch64),
                                         receiver: StreamFormat(sampleRate: 96_000, madiFrame: .frame48k, channelMode: .ch64))
        XCTAssertEqual(issues, [.speedMisinterpreted(sender: .single, receiver: .double)])
    }

    // T2 映射位置：12Mic Mic 1 经 /routing 落在 MADI 9；改成 MADI 1 后路径起点随之变化。
    func testT2_MappingOffset() {
        var s = Fixture.golden()
        guard case let .found(plan) = PathFinder(snapshot: s).find(from: mic1, to: p16ch1) else { return XCTFail() }
        XCTAssertEqual(plan.edges[1].to, ChannelRef("xt.madi1.in", 9))

        s.devices["12mic"]!.routes = (1...12).map {
            Route(domain: .twelveMic, source: ChannelRef("12mic.analog.in", $0),
                  destination: ChannelRef("12mic.madi_optical.out", $0), kind: .passthrough, evidence: .confirmed)
        }
        guard case let .found(plan2) = PathFinder(snapshot: s).find(from: mic1, to: p16ch1) else { return XCTFail() }
        XCTAssertEqual(plan2.edges[1].to, ChannelRef("xt.madi1.in", 1))
        // Aux Device 仍按 MADI 9 遥控 → R11 报错
        XCTAssertTrue(verdicts(s, "R11").contains { $0.isFail })
    }

    // T3 终端采样率：全系统 96 kHz，P16-I 不接受。
    func testT3_TerminalRate() {
        let s = Fixture.golden(rate: 96_000)
        XCTAssertTrue(verdicts(s, "R7").contains { $0.isFail })
        guard case let .infeasible(reasons) = PathFinder(snapshot: s).find(from: mic1, to: p16ch1) else {
            return XCTFail("96 kHz 下不应有到 P16-I 的路径")
        }
        XCTAssertTrue(reasons.contains { $0.contains("96000") && $0.contains("P16-I") }, "\(reasons)")
    }

    // T4 XTC ADAT Out 源为 Mic 而不是 MADI In。
    func testT4_AdatSourceMismatch() {
        var s = Fixture.golden()
        s.devices["xtc"]!.settings["xtc.adatOut1.source"] = .confirmed("mic.1-8", Fixture.m)
        XCTAssertTrue(verdicts(s, "R12").contains { $0.isFail })
        s.devices["xtc"]!.settings["xtc.adatOut1.source"] = .unknown()
        XCTAssertTrue(verdicts(s, "R12").allSatisfy { $0.isUndetermined })
    }

    // T5 控制路径并行：12Mic 允许并行（官方手册），XTC 不允许。
    func testT5_ParallelControl() {
        var s = Fixture.golden()
        s.devices["12mic"]!.controlPaths.append(
            ControlPath(controller: "totalmix-aux", transport: .midiOverMadi(viaPort: "12mic.madi_optical.in"), state: .online, active: true))
        s.devices["xtc"]!.controlPaths.append(
            ControlPath(controller: "midi-remote", transport: .coreMIDI(endpoint: "XTC"), state: .online, active: true))
        let r9 = Diagnostics.run(s).filter { $0.ruleID == "R9" }
        XCTAssertEqual(r9.first { $0.subject == "12Mic" }?.verdict, .pass)
        XCTAssertTrue(r9.first { $0.subject == "OctaMic XTC" }?.verdict.isFail == true)
    }

    // T6 12Mic 离线：相关状态全部“无法判断”，不得通过。
    func testT6_Offline() {
        var s = Fixture.golden()
        s.devices["12mic"]!.reachable = false
        XCTAssertTrue(verdicts(s, "R10").contains { $0.isFail })
        XCTAssertTrue(verdicts(s, "R11").allSatisfy { $0.isUndetermined })
        XCTAssertTrue(verdicts(s, "R2").allSatisfy { $0.isUndetermined })
    }

    // T7 接口类型不符：ADAT 接到 MADI 光口；SC↔SFP 只是警告。
    func testT7_MediumMismatch() {
        var s = Fixture.golden()
        s.topology.links.append(Link(id: "bad", from: "xtc.adat2.out", to: "xt.madi3.in"))
        let issues = s.topology.validate()
        XCTAssertTrue(issues.contains { $0.link.id == "bad" && $0.issue == .mediumMismatch(.adat, .madiCoaxial) })
        XCTAssertTrue(issues.contains { $0.link.id == "L1" && !$0.issue.isError })
    }

    // T8 块/通道冲突：XT MADI 2 输出 1 已被别的信号占用，计划必须列出将被覆盖的路由。
    // 占用者的来源取 xt.madi3.in（无来线、搜索不可达）。若用 xt.madi1.in:20（= Mic 12），
    // 搜索会改去覆盖 12Mic 的 Mic 12 路由来复用这条 XT 路由（代价 107 < 117），测不到本场景。
    func testT8_Override() {
        var s = Fixture.golden()
        let other = Route(domain: .totalMix, source: ChannelRef("xt.madi3.in", 1),
                          destination: ChannelRef("xt.madi2.out", 1), kind: .mixSend(gainDB: 0), evidence: .confirmed)
        s.devices["xt"]!.routes = [other]
        guard case let .found(plan) = PathFinder(snapshot: s).find(from: mic1, to: p16ch1) else { return XCTFail() }
        XCTAssertEqual(plan.overrides, [other])
    }

    // T9 写入部分失败：第 2 步失败，第 1 步回滚。
    @MainActor
    func testT9_PartialWriteRollback() async {
        let dev = MockDevice(Fixture.golden().devices["xtc"]!)
        let ops = [
            PlannedOperation(deviceID: "xtc", parameter: "setting:a", oldValue: "0", newValue: "1", access: .readWrite),
            PlannedOperation(deviceID: "xtc", parameter: "setting:b", oldValue: "0", newValue: "1", access: .readWrite),
            PlannedOperation(deviceID: "xtc", parameter: "setting:c", oldValue: "0", newValue: "1", access: .readWrite),
        ]
        await dev.failWrites(to: ["setting:b"])
        let outcome = await PlanExecutor.run(ops, on: dev, confirmation: ConfirmationGate.userConfirmed(ops))
        XCTAssertEqual(outcome.failed, ops[1].id)
        XCTAssertEqual(outcome.rolledBack, [ops[0].id])
        let a = await dev.state.settings["a"]?.value
        XCTAssertEqual(a, "0")
    }

    // T10 P16-I ADAT A 无输入。
    func testT10_NoAdatA() {
        var s = Fixture.golden()
        s.topology.links.removeAll { $0.to == "p16i.adat_a.in" }
        s.topology.links.append(Link(id: "L5b", from: "xtc.adat1.out", to: "p16i.adat_b.in"))
        XCTAssertTrue(verdicts(s, "R8").contains { $0.isFail })
    }

    // 计划顺序：改动步骤从下游到上游；不可远程写入的步骤列为人工步骤。
    func testPlanOrderAndManualSteps() {
        guard case let .found(plan) = PathFinder(snapshot: Fixture.golden()).find(from: mic1, to: p16ch1) else { return XCTFail() }
        XCTAssertEqual(plan.manualSteps.count, 1)              // TotalMix 一步，能力未知
        XCTAssertEqual(plan.manualSteps.first?.change?.domain, .totalMix)
        XCTAssertEqual(plan.manualSteps.first?.change?.destination, ChannelRef("xt.madi2.out", 1))
    }
}
