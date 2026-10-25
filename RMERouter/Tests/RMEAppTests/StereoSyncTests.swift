import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 与 TotalMix 同步、立体声配对、麦克风去向（文档第 6.4.3、7.8 节）。全部对假 TotalMix。
@MainActor
final class StereoSyncTests: XCTestCase {
    var fake: ChannelStripTests.FakeTM!

    func model() async -> AppModel {
        let fake = ChannelStripTests.FakeTM()
        self.fake = fake
        let m = AppModel(defaults: UserDefaults(suiteName: "sync-\(UUID())")!,
                         makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fake.transport) },
                         makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: XTCAppTests.offlineSession) })
        await m.refresh()
        return m
    }

    /// TotalMix 那边改了东西（这里模拟它主动发来的消息），App 不用按“读取”就跟上。
    func injectFromTotalMix(_ messages: [OSCMessage]) async {
        fake.transport.inject(messages)
        try? await Task.sleep(for: .milliseconds(50))
    }

    func testRevisionIgnoresLevels() {
        var s = TotalMixState()
        s.apply(OSCMessage("/input/0/mute", [.float(0)]))
        let r = s.revision
        s.apply(OSCMessage("/level/in/0", [.float(-20)]))
        XCTAssertEqual(s.revision, r, "电平不算变化")
        s.apply(OSCMessage("/input/0/mute", [.float(0)]))
        XCTAssertEqual(s.revision, r, "同值不算变化")
        s.apply(OSCMessage("/input/0/mute", [.float(1)]))
        XCTAssertEqual(s.revision, r + 1)
    }

    func testSplitInTotalMixShowsUpWithoutRefresh() async {
        let m = await model()
        XCTAssertEqual(m.xtStrips(.input).map(\.name), ["Mic 1", "M2-1/2"])
        XCTAssertEqual(m.outputs.first { $0.id == "xt" }?.cards.first { $0.port.id == "xt.phones.out" }?.channels, [1, 2])
        let nothing = await m.syncFromTotalMix()
        XCTAssertFalse(nothing, "没变化时不重建")

        // 在 TotalMix 里把 M2-1/2 拆开、耳机输出改成单声道
        await injectFromTotalMix([
            OSCMessage("/input/68/stereo", [.float(0)]), OSCMessage("/input/68/name", [.string("M2-1")]),
            OSCMessage("/input/69/name", [.string("M2-2")]), OSCMessage("/input/69/stereo", [.float(0)]),
            OSCMessage("/output/4/stereo", [.float(0)]),
        ])
        let changed = await m.syncFromTotalMix()
        XCTAssertTrue(changed)
        XCTAssertEqual(m.xtStrips(.input).map(\.name), ["Mic 1", "M2-1", "M2-2"])
        XCTAssertEqual(m.xtStrips(.input).last?.ref, ChannelRef("xt.madi2.in", 2))
        // 输出页按 TotalMix 拆开：耳机卡只剩左声道
        XCTAssertEqual(m.outputs.first { $0.id == "xt" }?.cards.first { $0.port.id == "xt.phones.out" }?.channels, [1])

        // 再合回去
        await injectFromTotalMix([OSCMessage("/input/68/stereo", [.float(1)]), OSCMessage("/input/68/name", [.string("M2-1/2")]),
                                  OSCMessage("/output/4/stereo", [.float(1)])])
        await m.syncFromTotalMix()
        XCTAssertEqual(m.xtStrips(.input).map(\.name), ["Mic 1", "M2-1/2"])
        XCTAssertEqual(m.outputs.first { $0.id == "xt" }?.cards.first { $0.port.id == "xt.phones.out" }?.channels, [1, 2])
    }

    /// 在 App 里拆分：写在左声道上，必须明确确认，回读核对。
    func testSplitFromApp() async throws {
        let m = await model()
        XCTAssertNil(m.stageStrip(ChannelRef("xt.madi2.in", 2), .stereo, 0))   // 从右声道发起也写左声道
        let c = try XCTUnwrap(m.pendingStrips.first)
        XCTAssertEqual(c.write.message, OSCMessage("/input/68/stereo", [.float(0)]))
        XCTAssertTrue(c.isLayoutChange)
        XCTAssertTrue(m.needsExplicitConfirmation)
        m.confirmMode = .quick
        await m.commitIfQuick()
        XCTAssertTrue(m.showConfirm, "快速方式下改配对也要确认")
        XCTAssertTrue(fake.lastWrites.isEmpty)
        let applied = await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
        XCTAssertEqual(try XCTUnwrap(applied).outcomes[c.id], .verified)
        XCTAssertEqual(fake.value("/input/68/stereo"), 0)
    }

    /// 麦克风去向：一个来源送到哪些输出；源头沿接线追到 12Mic。
    func testSendsAndOrigins() async {
        let m = await model()
        let sends = m.xtSends(from: TotalMixChannel(.input, 1))
        XCTAssertEqual(sends.map(\.output), [TotalMixChannel(.output, 5)])
        XCTAssertEqual(sends.first?.dB ?? 0, -6.9, accuracy: 0.01)

        // 演示数据里 12Mic Mic n → MADI 光口输出 8+n → XT MADI 1 输入 8+n（接线 L1）
        let labels = m.originLabels([ChannelRef("xt.madi1.in", 9), ChannelRef("xt.mic.in", 1)])
        XCTAssertEqual(labels[ChannelRef("xt.madi1.in", 9)]?.text, "← 12Mic Mic 1")
        XCTAssertEqual(labels[ChannelRef("xt.madi1.in", 9)]?.verified, false, "12Mic 没读到：这一段是演示数据，不能当成已核对")
        XCTAssertNil(labels[ChannelRef("xt.mic.in", 1)], "XT 自己的话放没有更上游")
    }
}
