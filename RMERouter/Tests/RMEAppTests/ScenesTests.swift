import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 场景（文档第 7.6 节）：保存 → 改动 → 对比 → 恢复（一律弹确认框）→ 一致；存盘与删除。
@MainActor
final class ScenesTests: XCTestCase {
    var fakeTM: WriteTests.FakeTotalMix!
    var dir: URL!

    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("rme-scenes-\(UUID())") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func makeModel(resetDevices: Bool = true) async -> AppModel {
        if resetDevices {
            fakeTM = WriteTests.FakeTotalMix()
            RouteWriteTests.Fake12Mic.ignoreWrites = false
            RouteWriteTests.Fake12Mic.routing = ["madi_optical": ["9": ["analog", 1]], "phones": ["1": ["madi_optical", 33]]]
        }
        let tm = fakeTM!
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [RouteWriteTests.Fake12Mic.self]
        let session = URLSession(configuration: cfg)
        let model = AppModel(defaults: UserDefaults(suiteName: "rme.scenes.\(UUID())")!,
                             makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: tm.transport) },
                             makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: session) },
                             sceneStore: SceneStore(directory: dir))
        await model.refresh()
        return model
    }

    let mic1 = ChannelRef("xt.mic.in", 1)
    let phonesL = ChannelRef("xt.phones.out", 1)
    let out9 = ChannelRef("12mic.madi_optical.out", 9)

    func confirmAll(_ m: AppModel) async {
        let ops = m.pending.map(\.operation) + m.pendingPreamps.map(\.operation) + m.pendingRoutes.map(\.operation)
        _ = await m.applyPending(confirmation: ConfirmationGate.userConfirmed(ops))
    }

    func testSaveChangeCompareRestore() async throws {
        let model = await makeModel()
        let scene = try XCTUnwrap(model.saveScene(named: "排练"))
        XCTAssertEqual(scene.devices, ["xt", "12mic"])
        XCTAssertEqual(scene.sends.count, 1)
        XCTAssertEqual(scene.sends[0].source, mic1)
        XCTAssertEqual(scene.sends[0].dB, -6.9, accuracy: 0.01)
        XCTAssertEqual(scene.preamps.first?.gain, 20)
        XCTAssertEqual(scene.routes.count, 2)
        XCTAssertTrue(model.diff(scene).isEmpty, "刚存的场景应与当前一致")

        // 改三处
        model.stageGain(source: mic1, destination: phonesL, dB: -20)
        model.stagePreamp(deviceID: "xt", input: mic1, field: .gain, value: .gain(25))
        model.stageTwelveMicRoute(destination: out9, source: ChannelRef("12mic.analog.in", 5))
        await confirmAll(model)
        XCTAssertEqual(model.diff(scene).count, 3)

        // 恢复：差异进待应用，并且一律打开确认框
        XCTAssertEqual(model.restore(scene), [])
        XCTAssertTrue(model.showConfirm)
        XCTAssertEqual(model.pending.count + model.pendingPreamps.count + model.pendingRoutes.count, 3)
        await confirmAll(model)
        XCTAssertTrue(model.diff(scene).isEmpty, "恢复后应与场景一致")
    }

    func testQuickModeStillConfirmsRestore() async throws {
        let model = await makeModel()
        model.confirmMode = .quick
        let scene = try XCTUnwrap(model.saveScene(named: "A"))
        model.stageGain(source: mic1, destination: phonesL, dB: -20)
        await model.commitIfQuick()                                    // 快速方式：直接发了
        XCTAssertTrue(model.pending.isEmpty)
        model.restore(scene)
        XCTAssertTrue(model.showConfirm, "恢复场景不论确认方式都要确认")
        XCTAssertEqual(model.pending.count, 1)
    }

    func testPersistAndDelete() async throws {
        let model = await makeModel()
        let scene = try XCTUnwrap(model.saveScene(named: "保存测试"))
        let reopened = await makeModel(resetDevices: false)
        XCTAssertEqual(reopened.scenes.map(\.id), [scene.id])
        XCTAssertEqual(reopened.scenes.first, scene)
        reopened.deleteScene(scene.id)
        XCTAssertTrue(reopened.scenes.isEmpty)
        XCTAssertTrue(SceneStore(directory: dir).load().isEmpty)
    }

    func testNothingToSaveWithoutDevices() {
        let model = AppModel(defaults: UserDefaults(suiteName: "rme.scenes.\(UUID())")!, sceneStore: SceneStore(directory: dir))
        XCTAssertNil(model.saveScene(named: "空"), "演示数据不能存")
    }
}
