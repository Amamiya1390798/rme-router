import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 写入流程（文档第 7.1 节）：暂存 → 确认 → 发送 → 回读核对 → 撤销。全部对假 TotalMix，不碰网络。
@MainActor
final class WriteTests: XCTestCase {

    /// 假 TotalMix：记住节点电平；/sendall 发名字与节点，/sendsubmix/N 发该输出的全部节点；可设为忽略写入。
    final class FakeTotalMix: @unchecked Sendable {
        let transport = MockOSCTransport()
        private let lock = NSLock()
        private var nodes: [String: Float] = ["/mix/in/0/4/fader": -6.9]   // Mic 1 → Phones 1
        var ignoreWrites = false
        private(set) var writes: [OSCMessage] = []

        init() {
            transport.respond = { [unowned self] m, t in self.handle(m, t) }
        }

        func handle(_ m: OSCMessage, _ t: MockOSCTransport) {
            let names: [OSCMessage] = [
                OSCMessage("/input/0/name", [.string("Mic 1")]), OSCMessage("/input/0/stereo", [.float(0)]),
                OSCMessage("/input/12/name", [.string("M1-9")]), OSCMessage("/input/12/stereo", [.float(0)]),
                OSCMessage("/playback/4/name", [.string("PH")]), OSCMessage("/playback/4/stereo", [.float(1)]),
                OSCMessage("/output/4/name", [.string("Phones 1")]), OSCMessage("/output/4/stereo", [.float(1)]),
                OSCMessage("/status/connection", [.float(0)]),
            ]
            if m.address.hasPrefix("/mix/") {
                lock.withLock {
                    writes.append(m)
                    if !ignoreWrites, case let .float(v)? = m.arguments.first { nodes[m.address] = v }
                }
            } else if m.address == "/sendall" {
                t.inject(names + nodeMessages(output: nil))
            } else if m.address.hasPrefix("/sendsubmix/"), let out = Int(m.address.split(separator: "/").last!) {
                t.inject(nodeMessages(output: out))
            } else if m.address == "/sendstate" {
                t.inject([OSCMessage("/status/connection", [.float(0)])])
            }
        }

        func nodeMessages(output: Int?) -> [OSCMessage] {
            lock.withLock {
                nodes.filter { k, _ in output.map { k.hasSuffix("/\($0)/fader") } ?? true }
                    .map { OSCMessage($0.key, [.float($0.value)]) }
            }
        }

        var lastWrites: [OSCMessage] { lock.withLock { writes } }
    }

    let mic1 = ChannelRef("xt.mic.in", 1)
    let phonesL = ChannelRef("xt.phones.out", 1)
    let madi1in9 = ChannelRef("xt.madi1.in", 9)

    /// 12Mic 一律立刻失败：测试不碰网络。
    final class No12Mic: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)) }
        override func stopLoading() {}
    }

    func loadedModel(_ fake: FakeTotalMix) async -> AppModel {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [No12Mic.self]
        let session = URLSession(configuration: cfg)
        let model = AppModel(defaults: UserDefaults(suiteName: "rme.write.\(UUID())")!,
                             makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fake.transport) },
                             makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: session) })
        await model.refresh()
        return model
    }

    // MARK: 协议层

    func testWriteMessageEncoding() {
        let mic1TM = TotalMixChannel(.input, 1), phones = TotalMixChannel(.output, 5)
        XCTAssertEqual(TotalMixWrite.sendGain(source: mic1TM, output: phones, dB: -20).message,
                       OSCMessage("/mix/in/0/4/fader", [.float(-20)]))
        XCTAssertEqual(TotalMixWrite.sendGain(source: TotalMixChannel(.playback, 3), output: phones, dB: 0).message,
                       OSCMessage("/mix/pb/2/4/fader", [.float(0)]))
        XCTAssertEqual(TotalMixWrite.sendGain(source: mic1TM, output: phones, dB: nil).message.arguments, [.float(-300)])
        XCTAssertEqual(TotalMixWrite.sendGain(source: mic1TM, output: phones, dB: 12).message.arguments, [.float(6)])
        XCTAssertEqual(TotalMixWrite.sendGain(source: mic1TM, output: phones, dB: -80).message.arguments, [.float(-300)])
        XCTAssertFalse(OSCSendGate.isRequest("/mix/in/0/4/fader"))   // 写入地址不在只读白名单里
    }

    func testClientRefusesWriteWithoutMatchingConfirmation() async throws {
        let fake = FakeTotalMix()
        let client = TotalMixGlobalOSCClient(transport: fake.transport)
        try await client.start()
        let w = TotalMixWrite.sendGain(source: TotalMixChannel(.input, 1), output: TotalMixChannel(.output, 5), dB: -20)
        let op = PlannedOperation(deviceID: "xt", parameter: w.message.address, oldValue: nil, newValue: "-20", access: .readWrite)
        let otherOp = PlannedOperation(deviceID: "xt", parameter: w.message.address, oldValue: nil, newValue: "-20", access: .readWrite)
        let wrongAddress = PlannedOperation(deviceID: "xt", parameter: "/mix/in/1/4/fader", oldValue: nil, newValue: "-20", access: .readWrite)

        do { try await client.write(w, for: otherOp, confirmation: ConfirmationGate.userConfirmed([op])); XCTFail() } catch {}
        do { try await client.write(w, for: wrongAddress, confirmation: ConfirmationGate.userConfirmed([wrongAddress])); XCTFail() } catch {}
        XCTAssertEqual(fake.lastWrites, [])

        try await client.write(w, for: op, confirmation: ConfirmationGate.userConfirmed([op]))
        XCTAssertEqual(fake.lastWrites, [OSCMessage("/mix/in/0/4/fader", [.float(-20)])])
    }

    // MARK: 暂存、应用、核对、撤销

    func testStageApplyVerifyUndo() async throws {
        let fake = FakeTotalMix()
        let model = await loadedModel(fake)
        XCTAssertEqual(model.xtStatus, .offlineSaved)

        XCTAssertNil(model.stageGain(source: mic1, destination: phonesL, dB: -20))
        XCTAssertEqual(model.pending.count, 1)
        let c = model.pending[0]
        XCTAssertEqual(c.oldDB!, -6.9, accuracy: 0.01)
        XCTAssertEqual(c.newDB, -20)
        XCTAssertEqual(c.totalMixLabel, "input 1（Mic 1） → output 5（Phones 1）")
        XCTAssertEqual(c.mapEvidence, .inferred)
        XCTAssertEqual(c.operation.parameter, "/mix/in/0/4/fader")
        XCTAssertEqual(fake.lastWrites, [], "暂存不发送任何消息")

        let batch = await model.applyPending(confirmation: ConfirmationGate.userConfirmed(model.pending.map(\.operation)))
        XCTAssertEqual(fake.lastWrites, [OSCMessage("/mix/in/0/4/fader", [.float(-20)])])
        XCTAssertEqual(batch?.outcomes[c.id], .verified)
        XCTAssertEqual(model.pending, [])
        XCTAssertEqual(model.history.count, 1)
        let route = model.snapshot.devices["xt"]!.routes.first { $0.source == mic1 && $0.destination == phonesL }
        XCTAssertEqual(route?.kind, .mixSend(gainDB: -20))

        model.stageUndo(model.history[0])
        XCTAssertEqual(model.pending.count, 1)
        XCTAssertEqual(model.pending[0].newDB!, -6.9, accuracy: 0.01)
    }

    func testMismatchWhenTotalMixIgnoresWrite() async {
        let fake = FakeTotalMix()
        fake.ignoreWrites = true
        let model = await loadedModel(fake)
        model.stageGain(source: mic1, destination: phonesL, dB: -20)
        let id = model.pending[0].id
        let batch = await model.applyPending(confirmation: ConfirmationGate.userConfirmed(model.pending.map(\.operation)))
        guard case let .mismatch(readBack)? = batch?.outcomes[id] else { return XCTFail("应为回读不一致") }
        XCTAssertEqual(readBack!, -6.9, accuracy: 0.01)
    }

    func testApplyWithoutConfirmationCoverageSendsNothing() async {
        let fake = FakeTotalMix()
        let model = await loadedModel(fake)
        model.stageGain(source: mic1, destination: phonesL, dB: -20)
        let id = model.pending[0].id
        let batch = await model.applyPending(confirmation: ConfirmationGate.userConfirmed([]))
        XCTAssertEqual(fake.lastWrites, [])
        guard case .failed? = batch?.outcomes[id] else { return XCTFail("未确认的改动应发送失败") }
    }

    func testStagingRules() async {
        let fake = FakeTotalMix()
        let model = await loadedModel(fake)
        // 改回原值 → 从待应用栏移除
        model.stageGain(source: mic1, destination: phonesL, dB: -20)
        model.stageGain(source: mic1, destination: phonesL, dB: -6.9)
        XCTAssertEqual(model.pending, [])
        // 非 TotalMix 设备、未映射通道
        XCTAssertEqual(model.stageGain(source: ChannelRef("12mic.analog.in", 1), destination: ChannelRef("12mic.madi_optical.out", 9), dB: 0), .notTotalMix)
        XCTAssertEqual(model.stageGain(source: ChannelRef("xt.madi3.in", 40), destination: phonesL, dB: 0), .notMapped(ChannelRef("xt.madi3.in", 40)))
        // 新建发送默认 -30 dB；从关推到 0 dB 标警示；超过 +6 截断
        XCTAssertNil(model.stageNewSend(source: madi1in9, destination: phonesL))
        XCTAssertEqual(model.pending.last?.oldDB, nil)
        XCTAssertEqual(model.pending.last?.newDB, -30)
        XCTAssertFalse(model.pending.last!.isLargeJump)
        model.stageGain(source: madi1in9, destination: phonesL, dB: 12)
        XCTAssertEqual(model.pending.last?.newDB, 6)
        XCTAssertTrue(model.pending.last!.isLargeJump)
        XCTAssertEqual(model.sendSourceCandidates, [madi1in9, mic1].sorted())
    }
}
