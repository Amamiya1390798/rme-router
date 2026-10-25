import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 主输出、耳机、对讲（文档第 7.9 节）。全部对假 TotalMix。
@MainActor
final class MonitorTests: XCTestCase {
    var fake: ChannelStripTests.FakeTM!

    func model() async -> AppModel {
        let fake = ChannelStripTests.FakeTM()
        self.fake = fake
        let m = AppModel(defaults: UserDefaults(suiteName: "mon-\(UUID())")!,
                         makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fake.transport) },
                         makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: XTCAppTests.offlineSession) })
        await m.refresh()
        // 同本机 TotalMix 读回：主输出 = 输出 1/2，耳机 1 = 输出 5/6，耳机 2 未指定，没指定对讲话筒
        fake.changeInTotalMix([
            OSCMessage("/controlroom/mainout", [.float(0)]), OSCMessage("/controlroom/phones1", [.float(4)]),
            OSCMessage("/controlroom/phones2", [.float(-1)]), OSCMessage("/controlroom/talkchannel", [.float(-1)]),
            OSCMessage("/controlroom/talkback", [.float(0)]), OSCMessage("/snapshot/load/1", [.float(2)]),
            OSCMessage("/controlroom/mutefx", [.float(0)]), OSCMessage("/controlroom/externalin", [.float(0)]),
        ])
        try? await Task.sleep(for: .milliseconds(50))
        _ = await m.syncFromTotalMix()
        return m
    }

    func apply(_ m: AppModel) async -> AppliedBatch? {
        await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
    }

    func testEncoding() {
        XCTAssertEqual(TotalMixWrite.controlSelect(.mainOut, output: TotalMixChannel(.output, 7)).message,
                       OSCMessage("/controlroom/mainout", [.float(6)]))
        XCTAssertEqual(TotalMixWrite.controlSelect(.phones(2), output: TotalMixChannel(.output, 5)).message,
                       OSCMessage("/controlroom/phones2", [.float(4)]))
        XCTAssertEqual(TotalMixGlobal.mainOut.text(-1), "未指定")
        XCTAssertEqual(TotalMixGlobal.phones(1).text(4), "输出 5")
    }

    func testReadsCurrent() async {
        let m = await model()
        XCTAssertEqual(m.monitorOutput(.mainOut), TotalMixChannel(.output, 1))
        XCTAssertEqual(m.monitorOutput(.phones(1)), TotalMixChannel(.output, 5))
        XCTAssertNil(m.monitorOutput(.phones(2)))
        XCTAssertFalse(m.talkbackReady, "没指定对讲话筒时不显示对讲")
    }

    /// 改主输出：快速方式下也弹确认框；确认后写序号、回读核对；撤销选回原来的。
    func testMainOutConfirmVerifyUndo() async throws {
        let m = await model()
        m.confirmMode = .quick
        XCTAssertNil(m.stageMonitor(.mainOut, output: TotalMixChannel(.output, 7)))
        let c = try XCTUnwrap(m.pendingGlobals.first)
        XCTAssertTrue(c.isMainOutChange)
        XCTAssertEqual(c.wireText, "OSC：/controlroom/mainout 6.0")
        await m.commitIfQuick()
        XCTAssertTrue(m.showConfirm)
        XCTAssertEqual(fake.value("/controlroom/mainout"), 0, "没确认不发送")

        let applied = await apply(m); let batch = try XCTUnwrap(applied)
        XCTAssertEqual(batch.outcomes[c.id], .verified)
        XCTAssertEqual(m.monitorOutput(.mainOut), TotalMixChannel(.output, 7))

        m.stageUndo(batch)
        XCTAssertEqual(m.pendingGlobals.first?.output, TotalMixChannel(.output, 1))
        _ = await apply(m)
        XCTAssertEqual(fake.value("/controlroom/mainout"), 0)
    }

    /// 耳机：选立体声右声道写左声道；选回当前值不进待应用；不用特别确认。
    func testPhones() async {
        let m = await model()
        XCTAssertNil(m.stageMonitor(.phones(1), output: TotalMixChannel(.output, 6)))
        XCTAssertTrue(m.pendingGlobals.isEmpty, "输出 6 是耳机 5/6 的右声道，等于当前值")
        XCTAssertNil(m.stageMonitor(.phones(2), output: TotalMixChannel(.output, 7)))
        XCTAssertFalse(m.needsExplicitConfirmation)
        XCTAssertNotNil(m.stageMonitor(.phones(1), output: TotalMixChannel(.input, 1)), "只能选硬件输出")
    }

    /// 静音效果：开关，写入回读。
    func testMuteFX() async throws {
        let m = await model()
        XCTAssertEqual(m.globalValue(.muteFX), 0)
        XCTAssertNil(m.stageGlobal(.muteFX, on: true))
        XCTAssertEqual(m.pendingGlobals.first?.wireText, "OSC：/controlroom/mutefx 1.0")
        let applied = await apply(m); let batch = try XCTUnwrap(applied)
        XCTAssertTrue(batch.outcomes.values.allSatisfy { $0 == .verified })
        XCTAssertEqual(fake.value("/controlroom/mutefx"), 1)
    }

    /// 修正：调用快照在快速方式下也要确认。
    func testSnapshotConfirmsInQuickMode() async {
        let m = await model()
        m.confirmMode = .quick
        XCTAssertNil(m.stageSnapshot(3))
        XCTAssertTrue(m.needsExplicitConfirmation)
    }
}
