import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 控制室、全局静音、快照（文档第 7.9 节）。全部对假 TotalMix。
@MainActor
final class ControlRoomTests: XCTestCase {
    var fake: ChannelStripTests.FakeTM!

    func model() async -> AppModel {
        let fake = ChannelStripTests.FakeTM()
        self.fake = fake
        let m = AppModel(defaults: UserDefaults(suiteName: "cr-\(UUID())")!,
                         makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fake.transport) },
                         makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: XTCAppTests.offlineSession) })
        await m.refresh()
        return m
    }

    func applyAll(_ m: AppModel) async -> AppliedBatch? {
        await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
    }

    func testParseAndRead() async {
        XCTAssertEqual(TotalMixEvent.parse(OSCMessage("/controlroom/dim", [.float(1)])), .global(key: "controlroom/dim", value: .float(1)))
        XCTAssertEqual(TotalMixEvent.parse(OSCMessage("/snapshot/load/3", [.float(2)])), .global(key: "snapshot/load/3", value: .float(2)))
        let m = await model()
        XCTAssertEqual(m.globalValue(.dim), 0)
        XCTAssertEqual(m.globalValue(.globalMute), 1)
        XCTAssertEqual(m.snapshots.map(\.number), [1, 2, 3])
        XCTAssertEqual(m.snapshots.first?.state, 2)
    }

    func testDimWriteVerifyUndo() async throws {
        let m = await model()
        XCTAssertNil(m.stageGlobal(.dim, on: true))
        let c = try XCTUnwrap(m.pendingGlobals.first)
        XCTAssertEqual(c.write.message, OSCMessage("/controlroom/dim", [.float(1)]))
        XCTAssertFalse(c.needsExplicit)
        let applied = await applyAll(m)
        let batch = try XCTUnwrap(applied)
        XCTAssertEqual(batch.outcomes[c.id], .verified)
        XCTAssertEqual(fake.value("/controlroom/dim"), 1)
        m.stageUndo(batch)
        XCTAssertEqual(m.pendingGlobals.first?.on, false)
        _ = await applyAll(m)
        XCTAssertEqual(fake.value("/controlroom/dim"), 0)
        // 改回原值：移除
        m.stageGlobal(.mainMono, on: true); m.stageGlobal(.mainMono, on: false)
        XCTAssertFalse(m.hasPending)
    }

    func testUnmuteAllNeedsConfirmEvenInQuickMode() async {
        let m = await model()
        m.confirmMode = .quick
        m.stageGlobal(.globalMute, on: false)
        XCTAssertTrue(m.pendingGlobals.first?.needsExplicit == true)
        await m.commitIfQuick()
        XCTAssertTrue(m.showConfirm)
        XCTAssertTrue(fake.lastWrites.isEmpty)
    }

    func testSnapshotLoadConfirmVerifyNoUndo() async throws {
        let m = await model()
        m.confirmMode = .quick
        XCTAssertNil(m.stageSnapshot(2))
        m.stageSnapshot(3)
        XCTAssertEqual(m.pendingGlobals.count, 1, "同时只留一个快照调用")
        let c = try XCTUnwrap(m.pendingGlobals.first)
        XCTAssertEqual(c.write.message, OSCMessage("/snapshot/load/3", [.float(1)]))
        await m.commitIfQuick()
        XCTAssertTrue(m.showConfirm, "调用快照一律确认")
        let applied = await applyAll(m)
        let batch = try XCTUnwrap(applied)
        XCTAssertEqual(batch.outcomes[c.id], .verified)
        XCTAssertEqual(m.snapshots.first { $0.state >= 1.5 }?.number, 3)
        m.stageUndo(batch)
        XCTAssertFalse(m.hasPending, "快照调用不能撤销")
        XCTAssertNotNil(m.stageSnapshot(9))
    }
}
