import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 前级写入（文档第 7.2 节）：协议层、12Mic 写入检查、暂存→确认→发送→回读→撤销。全部对假设备。
@MainActor
final class PreampWriteTests: XCTestCase {

    /// 假 12Mic：可读可写，记录收到的请求体。
    final class Fake12Mic: URLProtocol {
        nonisolated(unsafe) static var analog: [String: [String: Any]] = [:]
        nonisolated(unsafe) static var bodies: [[String: Any]] = []
        static let lock = NSLock()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let data = request.httpBody ?? request.httpBodyStream.map(TwelveMicTestsShared.readAll) ?? Data()
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            var reply: [String: Any] = [:]
            Self.lock.withLock {
                Self.bodies.append(body)
                if !TwelveMicReadGate.isReadOnly(body),
                   let a = (body["input"] as? [String: Any])?["analog"] as? [String: Any] {
                    for (n, fields) in a { for (k, v) in fields as? [String: Any] ?? [:] { Self.analog[n, default: [:]][k] = v } }
                }
                reply = ["device": ["entity_name": "12Mic"], "clock": ["current_sampling_rate": 48000, "source": "internal"],
                         "routing": [:] as [String: Any], "output": ["madi": ["mode": 64, "framesize": 48]],
                         "input": ["analog": Self.analog]]
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: reply))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    let xtMic1 = ChannelRef("xt.mic.in", 1)
    let micIn3 = ChannelRef("12mic.analog.in", 3)

    func loadedModel(_ fakeTM: WriteTests.FakeTotalMix) async -> AppModel {
        Fake12Mic.bodies = []
        Fake12Mic.analog = ["3": ["label": "Vox", "gain": 30.0, "p48": false, "phase": false]]
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [Fake12Mic.self]
        let session = URLSession(configuration: cfg)
        let model = AppModel(defaults: UserDefaults(suiteName: "rme.preamp.\(UUID())")!,
                             makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fakeTM.transport) },
                             makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: session) })
        await model.refresh()
        return model
    }

    // MARK: 协议层

    func testTotalMixPreampMessages() {
        let in1 = TotalMixChannel(.input, 1)
        XCTAssertEqual(TotalMixWrite.preamp(input: in1, field: .gain, value: .gain(40)).message, OSCMessage("/input/0/gain", [.float(40)]))
        XCTAssertEqual(TotalMixWrite.preamp(input: in1, field: .gain, value: .gain(75)).message.arguments, [.float(60)])   // 截到 60
        XCTAssertEqual(TotalMixWrite.preamp(input: in1, field: .phantom, value: .flag(true)).message, OSCMessage("/input/0/48v", [.float(1)]))
        XCTAssertEqual(TotalMixWrite.preamp(input: TotalMixChannel(.input, 2), field: .phase, value: .flag(false)).message,
                       OSCMessage("/input/1/phase", [.float(0)]))
        XCTAssertFalse(OSCSendGate.isRequest("/input/0/48v"))   // 写入地址不在只读白名单
    }

    func testTwelveMicWriteGate() {
        XCTAssertNotNil(TwelveMicWriteGate.preampBody(channel: 3, field: .phantom, value: .flag(true)))
        XCTAssertNil(TwelveMicWriteGate.preampBody(channel: 3, field: .gain, value: .gain(70)))       // 超出 0–60
        XCTAssertNil(TwelveMicWriteGate.preampBody(channel: 3, field: .gain, value: .flag(true)))     // 类型不符
        XCTAssertNil(TwelveMicWriteGate.preampBody(channel: 0, field: .phase, value: .flag(true)))
        XCTAssertEqual(TwelveMicWriteGate.parameter(channel: 3, field: .phantom), "input/analog/3/p48")
    }

    func testTwelveMicWriteNeedsMatchingConfirmation() async {
        Fake12Mic.bodies = []
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [Fake12Mic.self]
        let mic = TwelveMicJSONAdapter(baseURL: URL(string: "http://12mic.test")!, session: URLSession(configuration: cfg))
        let op = PlannedOperation(deviceID: "12mic", parameter: "input/analog/3/p48", oldValue: "关", newValue: "开", access: .readWrite)
        let other = PlannedOperation(deviceID: "12mic", parameter: "input/analog/3/p48", oldValue: "关", newValue: "开", access: .readWrite)
        do { try await mic.writePreamp(channel: 3, field: .phantom, value: .flag(true), for: other,
                                       confirmation: ConfirmationGate.userConfirmed([op])); XCTFail() } catch {}
        do { try await mic.writePreamp(channel: 4, field: .phantom, value: .flag(true), for: op,     // 字段与操作不符
                                       confirmation: ConfirmationGate.userConfirmed([op])); XCTFail() } catch {}
        XCTAssertTrue(Fake12Mic.bodies.isEmpty, "被拦截的写入不应发出")
        try? await mic.writePreamp(channel: 3, field: .phantom, value: .flag(true), for: op, confirmation: ConfirmationGate.userConfirmed([op]))
        XCTAssertEqual(Fake12Mic.bodies.count, 1)
        let leaf = ((Fake12Mic.bodies[0]["input"] as? [String: Any])?["analog"] as? [String: Any])?["3"] as? [String: Any]
        XCTAssertEqual(leaf?.keys.sorted(), ["p48"])
        XCTAssertEqual(leaf?["p48"] as? Bool, true)
    }

    // MARK: 完整流程

    func testStageApplyVerifyUndoBothDevices() async {
        let fakeTM = WriteTests.FakeTotalMix()
        let model = await loadedModel(fakeTM)
        XCTAssertEqual(model.twelveMicStatus, .live)
        XCTAssertEqual(model.snapshot.devices["xt"]?.preamps.first?.gainDB.knownValue, 20)

        XCTAssertNil(model.stagePreamp(deviceID: "xt", input: xtMic1, field: .gain, value: .gain(45)))
        XCTAssertNil(model.stagePreamp(deviceID: "12mic", input: micIn3, field: .phantom, value: .flag(true)))
        XCTAssertEqual(model.pendingPreamps.count, 2)
        XCTAssertTrue(model.pendingPreamps[0].isLargeJump)                 // 20 → 45
        XCTAssertTrue(model.pendingPreamps[1].needsPhantomAck)
        XCTAssertEqual(model.pendingPreamps[1].label, "Vox")
        XCTAssertEqual(model.pendingPreamps[0].parameter, "/input/0/gain")
        XCTAssertEqual(fakeTM.lastWrites, [], "暂存不发送")

        let batch = await model.applyPending(confirmation: ConfirmationGate.userConfirmed(model.pendingPreamps.map(\.operation)))
        XCTAssertEqual(fakeTM.lastWrites, [OSCMessage("/input/0/gain", [.float(45)])])
        XCTAssertEqual(batch?.count, 2)
        XCTAssertEqual(batch?.verifiedCount, 2)
        XCTAssertEqual(model.snapshot.devices["xt"]?.preamps.first?.gainDB.knownValue, 45)
        XCTAssertEqual(model.snapshot.devices["12mic"]?.preamps.first?.phantom.knownValue, true)
        XCTAssertTrue(model.pendingPreamps.isEmpty)

        model.stageUndo(model.history[0])
        XCTAssertEqual(model.pendingPreamps.map(\.new), [.gain(20), .flag(false)])
    }

    func testStagingRules() async {
        let model = await loadedModel(WriteTests.FakeTotalMix())
        // 改回原值 → 移除；增益截到 0–60
        model.stagePreamp(deviceID: "xt", input: xtMic1, field: .gain, value: .gain(30))
        model.stagePreamp(deviceID: "xt", input: xtMic1, field: .gain, value: .gain(20))
        XCTAssertTrue(model.pendingPreamps.isEmpty)
        model.stagePreamp(deviceID: "xt", input: xtMic1, field: .gain, value: .gain(99))
        XCTAssertEqual(model.pendingPreamps.first?.new, .gain(60))
        // 48V 点两次 → 撤回
        model.discardAll()
        model.stagePreamp(deviceID: "xt", input: xtMic1, field: .phantom, value: .flag(true))
        model.stagePreamp(deviceID: "xt", input: xtMic1, field: .phantom, value: .flag(false))
        XCTAssertTrue(model.pendingPreamps.isEmpty)
        // 读不到当前值、未映射
        XCTAssertEqual(model.stagePreamp(deviceID: "12mic", input: ChannelRef("12mic.analog.in", 9), field: .gain, value: .gain(10)),
                       .unknownCurrent("增益"))
        XCTAssertEqual(model.stagePreamp(deviceID: "xt", input: ChannelRef("xt.mic.in", 2), field: .gain, value: .gain(10)),
                       .notMapped(ChannelRef("xt.mic.in", 2)))
    }

    func testMismatchWhenTotalMixIgnoresPreampWrite() async {
        let fakeTM = WriteTests.FakeTotalMix()
        fakeTM.ignoreWrites = true
        let model = await loadedModel(fakeTM)
        model.stagePreamp(deviceID: "xt", input: xtMic1, field: .phantom, value: .flag(true))
        let id = model.pendingPreamps[0].id
        let batch = await model.applyPending(confirmation: ConfirmationGate.userConfirmed(model.pendingPreamps.map(\.operation)))
        XCTAssertEqual(batch?.outcomes[id], .mismatchValue(readBack: "关"))
    }
}

enum TwelveMicTestsShared {
    static func readAll(_ s: InputStream) -> Data {
        s.open(); defer { s.close() }
        var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
        while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
        return d
    }
}
