import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 确认方式（文档第 7.4 节）：快速方式点下即发；打开 48V、大幅抬高仍要确认框；每次确认方式不自动发送。
@MainActor
final class ConfirmModeTests: XCTestCase {
    var fakeTM: WriteTests.FakeTotalMix!

    func loadedModel(mode: ConfirmMode) async -> AppModel {
        let tm = WriteTests.FakeTotalMix()
        fakeTM = tm
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [WriteTests.No12Mic.self]
        let session = URLSession(configuration: cfg)
        let model = AppModel(defaults: UserDefaults(suiteName: "rme.confirm.\(UUID())")!,
                             makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: tm.transport) },
                             makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: session) })
        model.confirmMode = mode
        await model.refresh()
        return model
    }

    let mic1 = ChannelRef("xt.mic.in", 1)
    let phonesL = ChannelRef("xt.phones.out", 1)

    func testQuickModeSendsImmediately() async {
        let model = await loadedModel(mode: .quick)
        model.stageGain(source: mic1, destination: phonesL, dB: -10)        // 降低：不需要确认
        await model.commitIfQuick()
        XCTAssertEqual(fakeTM.lastWrites, [OSCMessage("/mix/in/0/4/fader", [.float(-10)])])
        XCTAssertTrue(model.pending.isEmpty)
        XCTAssertFalse(model.showConfirm)
        XCTAssertEqual(model.history.first?.verifiedCount, 1)

        // 撤销在快速方式下也是点下即发
        model.stageUndo(model.history[0])
        await model.commitIfQuick()
        XCTAssertEqual(fakeTM.lastWrites.count, 2)
        XCTAssertTrue(model.pending.isEmpty)
    }

    /// 第 7.4 节（2026-10-26）：快速方式下只有切换 48V、一次抬高超过 20 dB 要确认。
    func testQuickModeStillConfirmsPhantomAndLargeJumps() async {
        let model = await loadedModel(mode: .quick)
        model.stagePreamp(deviceID: "xt", input: mic1, field: .phantom, value: .flag(true))
        await model.commitIfQuick()
        XCTAssertTrue(model.showConfirm, "打开 48V 仍须确认")
        XCTAssertEqual(fakeTM.lastWrites, [])
        XCTAssertEqual(model.pendingPreamps.count, 1)

        model.discardAll(); model.showConfirm = false
        model.stagePreamp(deviceID: "xt", input: mic1, field: .gain, value: .gain(45))   // 20 → 45，抬高 25 dB
        await model.commitIfQuick()
        XCTAssertTrue(model.showConfirm, "抬高超过 20 dB 仍须确认")
        XCTAssertEqual(fakeTM.lastWrites, [])

        model.discardAll(); model.showConfirm = false
        model.stagePreamp(deviceID: "xt", input: mic1, field: .gain, value: .gain(35))   // 抬高 15 dB：直接发
        await model.commitIfQuick()
        XCTAssertFalse(model.showConfirm)
        XCTAssertEqual(fakeTM.lastWrites.count, 1)
    }

    func testAlwaysModeNeverAutoSends() async {
        let model = await loadedModel(mode: .always)
        model.stageGain(source: mic1, destination: phonesL, dB: -10)
        await model.commitIfQuick()
        XCTAssertEqual(fakeTM.lastWrites, [])
        XCTAssertEqual(model.pending.count, 1)
        XCTAssertFalse(model.showConfirm)
    }

    func testModePersistsAndDefaultsToAlways() {
        let defaults = UserDefaults(suiteName: "rme.confirm.\(UUID())")!
        XCTAssertEqual(AppModel(defaults: defaults).confirmMode, .always)
        AppModel(defaults: defaults).confirmMode = .quick
        XCTAssertEqual(AppModel(defaults: defaults).confirmMode, .quick)
    }
}
