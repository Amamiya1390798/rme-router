import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// E10 通道条补全（文档第 7.8 节）：送效果、效果返回、宽度、M/S、自动增益、收对讲。全部对假 TotalMix。
@MainActor
final class StripExtrasTests: XCTestCase {
    var fake: ChannelStripTests.FakeTM!

    func model() async -> AppModel {
        let fake = ChannelStripTests.FakeTM()
        self.fake = fake
        let m = AppModel(defaults: UserDefaults(suiteName: "extras-\(UUID())")!,
                         makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fake.transport) },
                         makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: XTCAppTests.offlineSession) })
        await m.refresh()
        // 同本机 TotalMix 读回的初值
        fake.changeInTotalMix([
            OSCMessage("/input/0/fxsend", [.float(-300)]), OSCMessage("/input/0/width", [.float(1)]),
            OSCMessage("/input/0/msproc", [.float(0)]), OSCMessage("/input/0/autoset", [.float(0)]),
            OSCMessage("/output/4/fxreturn", [.float(-65)]), OSCMessage("/output/4/talkbacksel", [.float(1)]),
        ])
        try? await Task.sleep(for: .milliseconds(50))
        _ = await m.syncFromTotalMix()
        return m
    }

    func apply(_ m: AppModel) async -> AppliedBatch? {
        await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
    }

    let mic1 = ChannelRef("xt.mic.in", 1), phonesL = ChannelRef("xt.phones.out", 1)

    func testEncodingAndRanges() {
        let inp = TotalMixChannel(.input, 1), out = TotalMixChannel(.output, 5)
        XCTAssertEqual(TotalMixWrite.strip(channel: inp, param: .fxsend, value: -100).message, OSCMessage("/input/0/fxsend", [.float(-300)]))
        XCTAssertEqual(TotalMixWrite.strip(channel: out, param: .fxreturn, value: -100).message, OSCMessage("/output/4/fxreturn", [.float(-65)]))
        XCTAssertEqual(TotalMixWrite.strip(channel: inp, param: .width, value: 3).message, OSCMessage("/input/0/width", [.float(1)]))
        XCTAssertEqual(TotalMixStripParam.width.text(-1), "-1.00")
        XCTAssertFalse(TotalMixStripParam.fxsend.applies(to: .output))
        XCTAssertFalse(TotalMixStripParam.fxreturn.applies(to: .input))
        XCTAssertFalse(TotalMixStripParam.autoset.applies(to: .playback))
        XCTAssertTrue(TotalMixStripParam.width.applies(to: .playback))
    }

    func testReads() async {
        let m = await model()
        XCTAssertEqual(m.stripValue(mic1, .fxsend), -300)
        XCTAssertEqual(m.stripValue(mic1, .width), 1)
        XCTAssertEqual(m.stripValue(phonesL, .talkbacksel), 1)
        XCTAssertNil(m.stripValue(mic1, .fxreturn), "输入没有效果返回")
    }

    /// 写入、回读核对、撤销；不额外要求确认。
    func testWriteVerifyUndo() async throws {
        let m = await model()
        XCTAssertNil(m.stageStrip(mic1, .fxsend, -12))
        XCTAssertNil(m.stageStrip(mic1, .width, 0))
        XCTAssertNil(m.stageStrip(phonesL, .talkbacksel, 0))
        XCTAssertNil(m.stageStrip(mic1, .autoset, 1))
        XCTAssertFalse(m.needsExplicitConfirmation)
        let applied = await apply(m); let batch = try XCTUnwrap(applied)
        XCTAssertTrue(batch.outcomes.values.allSatisfy { $0 == .verified })
        XCTAssertEqual(fake.value("/input/0/fxsend"), -12)
        XCTAssertEqual(fake.value("/input/0/width"), 0)
        XCTAssertEqual(fake.value("/output/4/talkbacksel"), 0)
        XCTAssertEqual(fake.value("/input/0/autoset"), 1)

        m.stageUndo(batch)
        _ = await apply(m)
        XCTAssertEqual(fake.value("/input/0/fxsend"), -300)
        XCTAssertEqual(fake.value("/input/0/width"), 1)
        XCTAssertEqual(fake.value("/output/4/talkbacksel"), 1)
    }

    /// 进场景：存下来，改了能对比出来。
    func testInScenes() async throws {
        let m = await model()
        let scene = try XCTUnwrap(m.saveScene(named: "E10"))
        XCTAssertTrue(scene.strips?.contains(.init(ref: mic1, param: .width, value: 1)) == true)
        fake.changeInTotalMix([OSCMessage("/input/0/width", [.float(0.5)])])
        try? await Task.sleep(for: .milliseconds(50))
        _ = await m.syncFromTotalMix()
        XCTAssertTrue(m.diff(scene).contains { $0.text.contains("宽度") })
    }
}
