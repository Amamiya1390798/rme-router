import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 通道条进场景（文档第 7.6 节）：保存、对比、恢复静音 / 音量 / 立体声配对。全部对假 TotalMix。
@MainActor
final class StripSceneTests: XCTestCase {
    var fake: ChannelStripTests.FakeTM!

    func model() async -> AppModel {
        let fake = ChannelStripTests.FakeTM()
        self.fake = fake
        let m = AppModel(defaults: UserDefaults(suiteName: "stripscene-\(UUID())")!,
                         makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fake.transport) },
                         makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: XTCAppTests.offlineSession) })
        await m.refresh()
        return m
    }

    func inject(_ m: AppModel, _ messages: [OSCMessage]) async {
        fake.changeInTotalMix(messages)
        try? await Task.sleep(for: .milliseconds(50))
        _ = await m.syncFromTotalMix()
    }

    func applyAll(_ m: AppModel) async {
        _ = await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
    }

    let phonesL = ChannelRef("xt.phones.out", 1), madiOut1 = ChannelRef("xt.madi1.out", 1)

    func stripDiffs(_ d: [SceneDiff]) -> [SceneDiff] { d.filter { if case .strip = $0.kind { true } else { false } } }

    func testSaveDiffRestore() async throws {
        let m = await model()
        let scene = try XCTUnwrap(m.saveScene(named: "通道条"))
        let strips = try XCTUnwrap(scene.strips)
        XCTAssertTrue(strips.contains(.init(ref: phonesL, param: .volume, value: -300)))
        XCTAssertTrue(strips.contains(.init(ref: madiOut1, param: .mute, value: 1)))
        XCTAssertTrue(scene.summary.contains("通道条"))
        XCTAssertTrue(stripDiffs(m.diff(scene)).isEmpty, "刚存完没有差异")

        // TotalMix 里改了耳机音量、取消了 MADI 1 输出的静音
        await inject(m, [OSCMessage("/output/4/volume", [.float(-10)]), OSCMessage("/output/6/mute", [.float(0)])])
        let d = stripDiffs(m.diff(scene))
        XCTAssertEqual(d.count, 2)
        XCTAssertTrue(d.contains { $0.text.contains("xt.phones.out:1") && $0.text.contains("音量") })

        let errors = m.restore(scene)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertTrue(m.showConfirm, "恢复一律弹确认框")
        await applyAll(m)
        XCTAssertEqual(fake.value("/output/4/volume"), -300)
        XCTAssertEqual(fake.value("/output/6/mute"), 1)
        XCTAssertTrue(stripDiffs(m.diff(scene)).isEmpty)
    }

    /// 配对有变化时，这一次只恢复配对，并提示再点一次。
    func testStereoRestoredFirst() async throws {
        let m = await model()
        let scene = try XCTUnwrap(m.saveScene(named: "配对"))
        await inject(m, [OSCMessage("/output/4/stereo", [.float(0)]), OSCMessage("/output/6/mute", [.float(0)])])
        let errors = m.restore(scene)
        XCTAssertTrue(errors.contains { $0.contains("先恢复立体声配对") })
        XCTAssertEqual(m.pendingStrips.map(\.param), [.stereo], "这次只有配对")
        XCTAssertTrue(m.pendingStrips.isEmpty == false)
    }

    /// 旧场景文件（没有 strips）照常读取，对比不涉及通道条。
    func testOldSceneFile() async throws {
        let m = await model()
        var scene = try XCTUnwrap(m.saveScene(named: "旧"))
        scene.strips = nil
        let data = try JSONEncoder().encode(scene)
        let decoded = try JSONDecoder().decode(StudioScene.self, from: data)
        XCTAssertNil(decoded.strips)
        await inject(m, [OSCMessage("/output/6/mute", [.float(0)])])
        XCTAssertTrue(stripDiffs(m.diff(decoded)).isEmpty)
    }
}
