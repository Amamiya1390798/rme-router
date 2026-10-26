import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// EQ 与低切（文档第 7.8 节）。全部对假 TotalMix。
@MainActor
final class EQTests: XCTestCase {
    var fake: ChannelStripTests.FakeTM!

    func model() async -> AppModel {
        let fake = ChannelStripTests.FakeTM()
        self.fake = fake
        let m = AppModel(defaults: UserDefaults(suiteName: "eq-\(UUID())")!,
                         makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fake.transport) },
                         makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: XTCAppTests.offlineSession) })
        await m.refresh()
        // 同本机 TotalMix 读回的默认值（Phones 1）
        fake.changeInTotalMix([
            OSCMessage("/output/4/eq/enable", [.float(0)]),
            OSCMessage("/output/4/eq/band1gain", [.float(0)]), OSCMessage("/output/4/eq/band1freq", [.float(80)]),
            OSCMessage("/output/4/eq/band1q", [.float(1)]), OSCMessage("/output/4/eq/band1type", [.float(1)]),
            OSCMessage("/output/4/eq/band2gain", [.float(0)]), OSCMessage("/output/4/eq/band2freq", [.float(1000)]),
            OSCMessage("/output/4/eq/band2q", [.float(1)]),
            OSCMessage("/output/4/eq/band3gain", [.float(0)]), OSCMessage("/output/4/eq/band3freq", [.float(5000)]),
            OSCMessage("/output/4/eq/band3q", [.float(1)]), OSCMessage("/output/4/eq/band3type", [.float(1)]),
            OSCMessage("/output/4/lowcut/enable", [.float(0)]), OSCMessage("/output/4/lowcut/freq", [.float(20)]),
            OSCMessage("/output/4/lowcut/slope", [.float(1)]),
        ])
        try? await Task.sleep(for: .milliseconds(50))
        _ = await m.syncFromTotalMix()
        return m
    }

    let phonesL = ChannelRef("xt.phones.out", 1)

    func testEncodingAndRanges() {
        let out = TotalMixChannel(.output, 5)
        XCTAssertEqual(TotalMixWrite.strip(channel: out, param: .eqB2Gain, value: 30).message, OSCMessage("/output/4/eq/band2gain", [.float(20)]))
        XCTAssertEqual(TotalMixWrite.strip(channel: out, param: .eqB1Q, value: 0.1).message, OSCMessage("/output/4/eq/band1q", [.float(0.7)]))
        XCTAssertEqual(TotalMixWrite.strip(channel: out, param: .lcFreq, value: 900).message, OSCMessage("/output/4/lowcut/freq", [.float(500)]))
        XCTAssertEqual(TotalMixStripParam.eqB1Freq.text(1500), "1.5 kHz")
        XCTAssertTrue(TotalMixStripParam.eqEnable.applies(to: .input))
        XCTAssertFalse(TotalMixStripParam.eqB1Type.isWritable)
    }

    /// 写增益、频率、开关；回读核对；撤销还原。类型只读。
    func testWriteVerifyUndo() async throws {
        let m = await model()
        XCTAssertEqual(m.stripValue(phonesL, .eqB2Freq), 1000)
        XCTAssertNil(m.stageStrip(phonesL, .eqEnable, 1))
        XCTAssertNil(m.stageStrip(phonesL, .eqB2Gain, 4.5))
        XCTAssertNil(m.stageStrip(phonesL, .eqB2Freq, 2500))
        XCTAssertNil(m.stageStrip(phonesL, .lcEnable, 1))
        XCTAssertNotNil(m.stageStrip(phonesL, .eqB1Type, 0), "类型序号含义未核对，只读")
        let applied = await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
        let batch = try XCTUnwrap(applied)
        XCTAssertTrue(batch.outcomes.values.allSatisfy { $0 == .verified })
        XCTAssertEqual(fake.value("/output/4/eq/band2gain"), 4.5)
        XCTAssertEqual(fake.value("/output/4/eq/band2freq"), 2500)
        m.stageUndo(batch)
        _ = await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
        XCTAssertEqual(fake.value("/output/4/eq/band2gain"), 0)
        XCTAssertEqual(fake.value("/output/4/eq/enable"), 0)
    }

    /// EQ 进场景（类型、斜率不进）。
    func testInScenes() async throws {
        let m = await model()
        let scene = try XCTUnwrap(m.saveScene(named: "EQ"))
        let strips = try XCTUnwrap(scene.strips)
        XCTAssertTrue(strips.contains(.init(ref: phonesL, param: .eqB2Freq, value: 1000)))
        XCTAssertFalse(strips.contains { $0.param == .eqB1Type })
    }

    /// 曲线：峰值滤波器在中心频率处正好是设定增益；低切在截止点约 -3 dB。
    func testCurveMath() {
        XCTAssertEqual(EQCurve.peak(1000, f0: 1000, gain: 6, q: 1), 6, accuracy: 0.05)
        XCTAssertEqual(EQCurve.peak(10000, f0: 100, gain: 6, q: 2), 0, accuracy: 0.1)
        XCTAssertEqual(EQCurve.highPass(100, f0: 100), -3, accuracy: 0.2)
    }
}
