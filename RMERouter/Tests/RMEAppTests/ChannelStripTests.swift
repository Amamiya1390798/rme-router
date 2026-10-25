import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// TotalMix 通道条（文档第 7.8 节）：音量、平衡、静音、相位、发送声像。全部对假 TotalMix。
@MainActor
final class ChannelStripTests: XCTestCase {

    /// 假 TotalMix：通道参数与节点参数都按地址存；/sendchan、/sendsubmix、/sendall 回发对应参数。
    final class FakeTM: @unchecked Sendable {
        let transport = MockOSCTransport()
        private let lock = NSLock()
        var ignoreWrites = false
        private(set) var writes: [OSCMessage] = []
        private var params: [String: OSCValue] = [
            "/input/0/name": .string("Mic 1"), "/input/0/stereo": .float(0), "/input/0/mute": .float(0), "/input/0/phase": .float(0),
            "/input/68/name": .string("M2-1/2"), "/input/68/stereo": .float(1), "/input/68/mute": .float(0),
            "/input/68/phase": .float(0), "/input/69/phase": .float(0),
            "/playback/4/name": .string("PH"), "/playback/4/stereo": .float(1),
            "/output/4/name": .string("Phones 1"), "/output/4/stereo": .float(1), "/output/4/volume": .float(-300),
            "/output/4/mute": .float(0), "/output/4/balpan": .float(0), "/output/4/phase": .float(0), "/output/5/phase": .float(0),
            "/output/6/name": .string("M1-1"), "/output/6/stereo": .float(0), "/output/6/volume": .float(0),
            "/output/6/mute": .float(1), "/output/6/balpan": .float(0), "/output/6/phase": .float(0),
            "/mix/in/0/4/fader": .float(-6.9), "/mix/in/0/4/balpan": .float(0),
            "/mix/in/68/4/fader": .float(-5.4), "/mix/in/68/4/balpan": .float(0),
            "/status/connection": .float(0),
        ]

        init() { transport.respond = { [unowned self] m, t in self.handle(m, t) } }

        func value(_ address: String) -> Float? {
            lock.withLock { if case let .float(v)? = params[address] { return v }; return nil }
        }

        func handle(_ m: OSCMessage, _ t: MockOSCTransport) {
            let a = m.address
            func send(_ filter: (String) -> Bool) {
                t.inject(lock.withLock { params.filter { filter($0.key) }.map { OSCMessage($0.key, [$0.value]) } })
            }
            if a == "/sendall" { send { _ in true } }
            else if a == "/sendstate" { send { $0.hasPrefix("/status/") } }
            else if a.hasPrefix("/sendchan/") {
                let p = a.split(separator: "/")   // sendchan, bus, n
                send { $0.hasPrefix("/\(p[1])/\(p[2])/") }
            } else if a.hasPrefix("/sendsubmix/"), let out = a.split(separator: "/").last {
                send { $0.hasPrefix("/mix/") && $0.split(separator: "/")[3] == out }
            } else if !a.hasPrefix("/send") {
                lock.withLock {
                    writes.append(m)
                    if !ignoreWrites, let v = m.arguments.first { params[a] = v }
                }
            }
        }

        var lastWrites: [OSCMessage] { lock.withLock { writes } }

        /// 模拟用户在 TotalMix 里改了东西：自己的状态跟着变，并把变化主动发给 App。
        func changeInTotalMix(_ messages: [OSCMessage]) {
            lock.withLock { for m in messages { if let v = m.arguments.first { params[m.address] = v } } }
            transport.inject(messages)
        }
    }

    var fake: FakeTM!

    func model() async -> AppModel {
        let fake = FakeTM()
        self.fake = fake
        let m = AppModel(defaults: UserDefaults(suiteName: "strip-\(UUID())")!,
                         makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fake.transport) },
                         makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: XTCAppTests.offlineSession) })
        await m.refresh()
        return m
    }

    func applyAll(_ m: AppModel) async -> AppliedBatch? {
        await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
    }

    let phonesL = ChannelRef("xt.phones.out", 1), phonesR = ChannelRef("xt.phones.out", 2)
    let madiOut1 = ChannelRef("xt.madi1.out", 1)
    let mic1 = ChannelRef("xt.mic.in", 1)
    let m2L = ChannelRef("xt.madi2.in", 1), m2R = ChannelRef("xt.madi2.in", 2)

    // MARK: 协议层

    func testEncodingAndClamp() {
        let out = TotalMixChannel(.output, 5), inp = TotalMixChannel(.input, 1)
        XCTAssertEqual(TotalMixWrite.strip(channel: out, param: .volume, value: 10).message, OSCMessage("/output/4/volume", [.float(6)]))
        XCTAssertEqual(TotalMixWrite.strip(channel: out, param: .volume, value: -70).message, OSCMessage("/output/4/volume", [.float(-300)]))
        XCTAssertEqual(TotalMixWrite.strip(channel: inp, param: .mute, value: 1).message, OSCMessage("/input/0/mute", [.float(1)]))
        XCTAssertEqual(TotalMixWrite.sendPan(source: inp, output: out, pan: 2).message, OSCMessage("/mix/in/0/4/balpan", [.float(1)]))
        XCTAssertFalse(TotalMixStripParam.volume.applies(to: .input))
        XCTAssertEqual(TotalMixWrite.panText(-0.3), "左 30")
        XCTAssertEqual(TotalMixWrite.panText(0), "中")
    }

    // MARK: 读取

    func testReadsCurrentValues() async {
        let m = await model()
        XCTAssertEqual(m.stripValue(phonesL, .volume), -300)
        XCTAssertEqual(m.stripValue(phonesR, .volume), -300)          // 右声道读左声道
        XCTAssertEqual(m.stripValue(madiOut1, .mute), 1)
        XCTAssertNil(m.stripValue(mic1, .volume))                     // 输入没有音量
        XCTAssertEqual(m.sendPan(source: mic1, destination: phonesL), 0)
        XCTAssertNil(m.sendPan(source: mic1, destination: madiOut1))  // 没有这条发送
    }

    // MARK: 写入

    func testOutputVolumeWriteVerifyUndo() async throws {
        let m = await model()
        XCTAssertNil(m.stageStrip(phonesL, .volume, -10))
        let c = try XCTUnwrap(m.pendingStrips.first)
        XCTAssertEqual(c.wireText, "OSC：/output/4/volume -10.0")
        XCTAssertTrue(c.stereo)
        XCTAssertTrue(c.isLargeJump)                                   // 关 → -10 dB
        XCTAssertTrue(m.needsExplicitConfirmation)
        XCTAssertTrue(fake.lastWrites.isEmpty)                         // 暂存不发送

        let applied = await applyAll(m); let batch = try XCTUnwrap(applied)
        XCTAssertEqual(batch.outcomes[c.id], .verified)
        XCTAssertEqual(fake.value("/output/4/volume"), -10)
        XCTAssertEqual(m.stripValue(phonesL, .volume), -10)

        m.stageUndo(batch)
        XCTAssertEqual(m.pendingStrips.first?.new, -300)
        _ = await applyAll(m)
        XCTAssertEqual(fake.value("/output/4/volume"), -300)
    }

    func testStereoRightSideAddressesLeft() async throws {
        let m = await model()
        m.stageStrip(phonesR, .mute, 1)
        XCTAssertEqual(m.pendingStrips.first?.write.message.address, "/output/4/mute")
        XCTAssertEqual(m.pendingStrip(phonesL, .mute), 1)              // 左右两声道都显示待应用

        // 相位是 L/R 参数：右声道单独写 N+1
        m.stageStrip(m2R, .phase, 1)
        XCTAssertEqual(m.pendingStrips.last?.write.message.address, "/input/69/phase")
        m.stageStrip(m2L, .mute, 1)
        XCTAssertEqual(m.pendingStrips.last?.write.message.address, "/input/68/mute")
        _ = await applyAll(m)
        XCTAssertEqual(fake.value("/input/69/phase"), 1)
        XCTAssertEqual(fake.value("/input/68/phase"), 0)
    }

    func testInputHasNoVolume() async {
        let m = await model()
        if case .notSupported? = m.stageStrip(mic1, .volume, -10) {} else { XCTFail() }
        XCTAssertFalse(m.hasPending)
    }

    func testSendPan() async throws {
        let m = await model()
        XCTAssertNil(m.stageSendPan(source: mic1, destination: phonesL, pan: -0.5))
        let c = try XCTUnwrap(m.pendingStrips.first)
        XCTAssertEqual(c.write.message, OSCMessage("/mix/in/0/4/balpan", [.float(-0.5)]))
        XCTAssertEqual(c.changeText, "中 → 左 50")
        let applied = await applyAll(m); let batch = try XCTUnwrap(applied)
        XCTAssertEqual(batch.outcomes[c.id], .verified)
        XCTAssertEqual(m.sendPan(source: mic1, destination: phonesL) ?? 9, -0.5, accuracy: 0.001)

        // 立体声来源的右声道也落到左声道的节点
        XCTAssertNil(m.stageSendPan(source: m2R, destination: phonesR, pan: 0.2))
        XCTAssertEqual(m.pendingStrips.first?.write.message.address, "/mix/in/68/4/balpan")

        XCTAssertEqual(m.stageSendPan(source: mic1, destination: madiOut1, pan: 0.3), .noSend)
    }

    func testUnmuteNeedsExplicitConfirmEvenInQuickMode() async {
        let m = await model()
        m.confirmMode = .quick
        m.stageStrip(madiOut1, .mute, 0)
        XCTAssertTrue(m.pendingStrips.first?.isUnmute == true)
        await m.commitIfQuick()
        XCTAssertTrue(m.showConfirm)
        XCTAssertTrue(fake.lastWrites.isEmpty)

        // 静音（不会突然出声）在快速方式下直接发
        m.discardAll(); m.showConfirm = false
        m.stageStrip(phonesL, .mute, 1)
        await m.commitIfQuick()
        XCTAssertFalse(m.showConfirm)
        XCTAssertEqual(fake.value("/output/4/mute"), 1)
    }

    func testRevertingRemovesPending() async {
        let m = await model()
        m.stageStrip(phonesL, .balpan, 0.4)
        XCTAssertEqual(m.pendingCount, 1)
        m.stageStrip(phonesL, .balpan, 0)
        XCTAssertEqual(m.pendingCount, 0)
    }

    func testMismatchWhenTotalMixIgnoresWrite() async throws {
        let m = await model()
        fake.ignoreWrites = true
        m.stageStrip(phonesL, .phase, 1)
        let id = try XCTUnwrap(m.pendingStrips.first?.id)
        let applied = await applyAll(m); let batch = try XCTUnwrap(applied)
        XCTAssertEqual(batch.outcomes[id], .mismatchValue(readBack: "正相"))
    }
}
