import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 场景里的 XTC（文档第 7.6 节）：保存、对比、恢复路由块与前级。全部对 FakeXTC。
@MainActor
final class XTCSceneTests: XCTestCase {
    var fake: FakeXTC!
    var dir: URL!

    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("rme-xtc-scenes-\(UUID())") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func makeModel(write: Bool) async -> AppModel {
        let fake = FakeXTC()
        self.fake = fake
        let m = AppModel(defaults: UserDefaults(suiteName: "xtc-scene-\(UUID())")!,
                         makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: XTCAppTests.offlineSession) },
                         makeXTC: { s in
                             XTCMIDIAdapter(client: XTCClient(transport: fake, midiDeviceID: s.midiDeviceID),
                                            endpointName: s.destinationName, controlEnabled: s.canWrite)
                         },
                         sceneStore: SceneStore(directory: dir))
        m.xtcSettings.sourceName = "XTC out"
        m.xtcSettings.destinationName = "XTC in"
        m.xtcSettings.readEnabled = true
        if write {
            m.xtcSettings.auxDeviceOff = true
            m.xtcSettings.writeEnabled = true
        }
        await m.refreshXTC()
        return m
    }

    func applyAll(_ m: AppModel) async {
        _ = await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
    }

    let madiOut25 = ChannelRef("xtc.madi.out", 25)
    let mic3 = ChannelRef("xtc.mic.in", 3)

    func testSaveCompareRestore() async throws {
        let m = await makeModel(write: true)
        let scene = try XCTUnwrap(m.saveScene(named: "XTC"))
        XCTAssertEqual(scene.devices, ["xtc"])
        XCTAssertEqual(scene.xtcRoutes?.count, 10)
        XCTAssertEqual(scene.xtcRoutes?.first { $0.destination == madiOut25 }?.sourceLabel, "Mic 1–8")
        XCTAssertEqual(scene.preamps.filter { $0.device == "xtc" }.count, 8)
        XCTAssertTrue(scene.summary.contains("XTC 路由 10 块"))
        XCTAssertTrue(m.diff(scene).isEmpty)

        // 改一块路由、一路增益
        m.stageXTCRoute(destination: madiOut25, source: ChannelRef("xtc.madi.in", 17))
        m.stagePreamp(deviceID: "xtc", input: mic3, field: .gain, value: .gain(30))
        await applyAll(m)
        let diffs = m.diff(scene)
        XCTAssertEqual(diffs.count, 2)
        XCTAssertTrue(diffs.map(\.text).contains("XTC 路由 xtc.madi.out:25–32：现在 MADI 17–24，场景 Mic 1–8"))
        XCTAssertTrue(diffs.map(\.text).contains { $0.hasPrefix("XTC 前级 xtc.mic.in:3 增益") })

        // 恢复：进待应用并弹确认框；确认后一致
        XCTAssertEqual(m.restore(scene), [])
        XCTAssertTrue(m.showConfirm)
        XCTAssertEqual(m.pendingXTCRoutes.count, 1)
        XCTAssertEqual(m.pendingPreamps.count, 1)
        await applyAll(m)
        XCTAssertTrue(m.diff(scene).isEmpty, "恢复后应与场景一致")
        XCTAssertEqual(fake.value(17)?.msb, 0)
        XCTAssertEqual(fake.value(2)?.lsb, 0)
    }

    func testReadOnlyCanSaveAndCompareButNotRestore() async throws {
        let m = await makeModel(write: false)
        let scene = try XCTUnwrap(m.saveScene(named: "只读"))
        fake.setValue(17, lsb: 0, msb: 5)     // 在面板上改了：MADI 25–32 ← MADI 17–24
        await m.refreshXTC()
        XCTAssertEqual(m.diff(scene).count, 1)
        let errors = m.restore(scene)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("未允许本 App 改动"))
        XCTAssertFalse(m.hasPending)
        XCTAssertEqual(fake.received.count, 2)  // 只有两次读取
    }

    func testUnregisteredSourceNeedsPanel() async throws {
        let m = await makeModel(write: true)
        fake.setValue(14, lsb: 1, msb: 4)      // ADAT 1 ← ADAT IN
        await m.refreshXTC()
        let scene = try XCTUnwrap(m.saveScene(named: "ADAT IN"))
        let block = try XCTUnwrap(scene.xtcRoutes?.first { $0.destination == ChannelRef("xtc.adat1.out", 1) })
        XCTAssertNil(block.source)
        XCTAssertEqual(block.sourceLabel, "ADAT IN")
        fake.setValue(14, lsb: 3, msb: 4)
        await m.refreshXTC()
        let errors = m.restore(scene)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("需在 XTC 面板上设置"))
    }

    func testOldSceneFileWithoutXTC() throws {
        let json = """
        {"id":"\(UUID())","name":"旧","date":"2026-10-25T00:00:00Z","devices":["xt"],"sends":[],"preamps":[],"routes":[]}
        """
        let scene = try SceneStore.decoder.decode(StudioScene.self, from: Data(json.utf8))
        XCTAssertNil(scene.xtcRoutes)
        XCTAssertFalse(scene.summary.contains("XTC"))
    }

    func testPersistRoundTrip() async throws {
        let m = await makeModel(write: false)
        let scene = try XCTUnwrap(m.saveScene(named: "存盘"))
        XCTAssertEqual(SceneStore(directory: dir).load().first, scene)
    }
}
