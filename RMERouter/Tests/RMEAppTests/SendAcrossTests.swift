import XCTest
@testable import RMECore
@testable import RMEEngine
@testable import RMEAdapters
@testable import RMEApp

/// 跨设备“送一路声音”（文档第 7.5 节）：路径翻译成计划、自动步骤进待应用、人工步骤进清单。
@MainActor
final class SendAcrossTests: XCTestCase {
    var fakeTM: WriteTests.FakeTotalMix!

    /// 假 TotalMix + 假 12Mic（耳机左 ← MADI 光口 33）；对照表补上这条路径用到的 XT 通道。
    func loadedModel() async -> AppModel {
        let tm = WriteTests.FakeTotalMix()
        fakeTM = tm
        RouteWriteTests.Fake12Mic.bodies = []
        RouteWriteTests.Fake12Mic.ignoreWrites = false
        RouteWriteTests.Fake12Mic.routing = ["madi_optical": ["9": ["analog", 1]], "phones": ["1": ["madi_optical", 33], "2": ["madi_optical", 34]]]
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [RouteWriteTests.Fake12Mic.self]
        let session = URLSession(configuration: cfg)
        let map = TotalMixChannelMap(confirmed: [
            TotalMixChannel(.input, 69): ChannelRef("xt.madi2.in", 1), TotalMixChannel(.input, 70): ChannelRef("xt.madi2.in", 2),
            TotalMixChannel(.output, 39): ChannelRef("xt.madi1.out", 33), TotalMixChannel(.output, 40): ChannelRef("xt.madi1.out", 34),
        ])
        let model = AppModel(defaults: UserDefaults(suiteName: "rme.send.\(UUID())")!,
                             makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: tm.transport, channelMap: map) },
                             makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: session) })
        await model.refresh()
        return model
    }

    let xtcMic1 = ChannelRef("xtc.mic.in", 1)
    let phonesL = ChannelRef("12mic.phones.out", 1)

    /// 文档第 6.1 节示例：XTC Mic 1 → 12Mic 耳机左。应复用 12Mic 已有的 MADI 33 → 耳机路由，不覆盖任何东西。
    func testDocExamplePlan() async {
        let model = await loadedModel()
        guard case let .found(plans) = SendAcross.plan(model.snapshot, from: xtcMic1, to: phonesL) else {
            return XCTFail("应能找到路径")
        }
        let plan = plans[0]
        XCTAssertEqual(plan.overrides, [])
        XCTAssertEqual(plan.manualSteps.count, 1)
        XCTAssertTrue(plan.manualSteps[0].contains("Digital Routing"))
        XCTAssertEqual(plan.steps.map(\.action), [
            .manual(plan.manualSteps[0]),
            .cable(from: ChannelRef("xtc.madi.out", 1), to: ChannelRef("xt.madi2.in", 1)),
            .totalMixSend(source: ChannelRef("xt.madi2.in", 1), destination: ChannelRef("xt.madi1.out", 33), dB: -30),
            .cable(from: ChannelRef("xt.madi1.out", 33), to: ChannelRef("12mic.madi_optical.in", 33)),
            .existing(model.snapshot.devices["12mic"]!.routes.first { $0.destination == phonesL }!),
        ])
        XCTAssertEqual(plan.autoCount, 1)
    }

    func testStagePlanAddsPendingAndManualTasks() async {
        let model = await loadedModel()
        guard case let .found(plans) = SendAcross.plan(model.snapshot, from: xtcMic1, to: phonesL, pair: true) else {
            return XCTFail()
        }
        XCTAssertEqual(plans.count, 2)                                   // 左右各一条
        XCTAssertEqual(model.stageSendPlan(plans), [])
        XCTAssertEqual(model.pending.map(\.newDB), [-30, -30])
        XCTAssertEqual(model.pending.map(\.destination), [ChannelRef("xt.madi1.out", 33), ChannelRef("xt.madi1.out", 34)])
        XCTAssertEqual(model.manualTasks.count, 1, "两路落在 XTC 同一个 8 路块，人工步骤只列一次")
        XCTAssertEqual(fakeTM.lastWrites, [], "加入待应用不发送")

        // 加入后按普通流程发送并核对
        let batch = await model.applyPending(confirmation: ConfirmationGate.userConfirmed(model.pending.map(\.operation)))
        XCTAssertEqual(batch?.verifiedCount, 2)
        model.completeManualTask(model.manualTasks[0].id)
        XCTAssertTrue(model.manualTasks.isEmpty)
    }

    func testInfeasibleExplainsWhy() async {
        let model = await loadedModel()
        // P16-I 只有 ADAT A/B 输入，从 12Mic 模拟输入到 ADAT B 没有任何能力边
        guard case let .infeasible(reasons) = SendAcross.plan(model.snapshot, from: ChannelRef("12mic.analog.in", 1),
                                                             to: ChannelRef("p16i.adat_b.in", 1)) else {
            return XCTFail("ADAT B 没有接线，应找不到路径")
        }
        XCTAssertFalse(reasons.isEmpty)
    }

    func testStagingErrorRollsBack() async {
        let model = await loadedModel()
        // 构造一个用到未映射 XT 通道的计划：整体不加入
        let plan = SendPlan(source: xtcMic1, destination: phonesL, steps: [
            .init(id: 0, action: .totalMixSend(source: ChannelRef("xt.madi3.in", 5), destination: ChannelRef("xt.madi3.out", 5), dB: -30), overrides: []),
        ])
        XCTAssertFalse(model.stageSendPlan([plan]).isEmpty)
        XCTAssertTrue(model.pending.isEmpty)
        XCTAssertTrue(model.manualTasks.isEmpty)
    }
}
