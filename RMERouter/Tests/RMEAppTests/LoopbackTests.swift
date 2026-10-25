import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 送到电脑录音 loopback（文档第 7.8 节）。全部对假 TotalMix。
@MainActor
final class LoopbackTests: XCTestCase {
    var fake: ChannelStripTests.FakeTM!

    func model() async -> AppModel {
        let fake = ChannelStripTests.FakeTM()
        self.fake = fake
        let m = AppModel(defaults: UserDefaults(suiteName: "loop-\(UUID())")!,
                         makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fake.transport) },
                         makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: XTCAppTests.offlineSession) })
        await m.refresh()
        // TotalMix 回报输出 7（M1-1）的 loopback = 关
        fake.changeInTotalMix([OSCMessage("/output/6/loopback", [.float(0)])])
        try? await Task.sleep(for: .milliseconds(50))
        _ = await m.syncFromTotalMix()
        return m
    }

    let madiOut1 = ChannelRef("xt.madi1.out", 1), mic1 = ChannelRef("xt.mic.in", 1)

    func testEncoding() {
        XCTAssertEqual(TotalMixWrite.strip(channel: TotalMixChannel(.output, 7), param: .loopback, value: 1).message,
                       OSCMessage("/output/6/loopback", [.float(1)]))
        XCTAssertTrue(TotalMixStripParam.loopback.applies(to: .output))
        XCTAssertFalse(TotalMixStripParam.loopback.applies(to: .input))
    }

    /// 打开：快速方式下也弹确认框、不发送；确认后写入并回读，录音 7 显示被这个输出顶替；关闭不用特别确认。
    func testTurnOnNeedsConfirmEvenInQuickMode() async throws {
        let m = await model()
        m.confirmMode = .quick
        XCTAssertEqual(m.stripValue(madiOut1, .loopback), 0)
        XCTAssertNil(m.loopbackSource(recording: 7))

        XCTAssertNil(m.stageStrip(madiOut1, .loopback, 1))
        let c = try XCTUnwrap(m.pendingStrips.first)
        XCTAssertTrue(c.isLoopbackOn)
        XCTAssertEqual(c.loopbackRecording, "录音 7")
        XCTAssertTrue(m.needsExplicitConfirmation)
        await m.commitIfQuick()
        XCTAssertTrue(m.showConfirm, "打开送录音一律弹确认框")
        XCTAssertNil(fake.value("/output/6/loopback").flatMap { $0 >= 0.5 ? $0 : nil }, "没确认不发送")

        _ = await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
        XCTAssertEqual(fake.value("/output/6/loopback"), 1)
        XCTAssertEqual(m.loopbackSource(recording: 7)?.tm, TotalMixChannel(.output, 7))

        m.showConfirm = false
        XCTAssertNil(m.stageStrip(madiOut1, .loopback, 0))
        XCTAssertFalse(m.needsExplicitConfirmation, "关闭照常")
    }

    func testInputHasNoLoopback() async {
        let m = await model()
        XCTAssertNotNil(m.stageStrip(mic1, .loopback, 1))
        XCTAssertNil(m.stripValue(mic1, .loopback))
    }
}
