import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 12Mic 路由写入（文档第 7.3 节）。全部对假 12Mic。
@MainActor
final class RouteWriteTests: XCTestCase {

    /// 假 12Mic：路由可读可写；可设为忽略写入。
    final class Fake12Mic: URLProtocol {
        nonisolated(unsafe) static var routing: [String: [String: [Any]]] = [:]
        nonisolated(unsafe) static var bodies: [[String: Any]] = []
        nonisolated(unsafe) static var ignoreWrites = false
        static let lock = NSLock()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let data = request.httpBody ?? request.httpBodyStream.map(TwelveMicTestsShared.readAll) ?? Data()
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            var reply: [String: Any] = [:]
            Self.lock.withLock {
                Self.bodies.append(body)
                if !TwelveMicReadGate.isReadOnly(body), !Self.ignoreWrites, let r = body["routing"] as? [String: Any] {
                    for (port, table) in r { for (ch, v) in table as? [String: Any] ?? [:] { Self.routing[port, default: [:]][ch] = v as? [Any] } }
                }
                reply = ["device": ["entity_name": "12Mic"], "clock": ["current_sampling_rate": 48000, "source": "internal"],
                         "routing": Self.routing, "output": ["madi": ["mode": 64, "framesize": 48]],
                         "input": ["analog": [:] as [String: Any]]]
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: reply))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}

        static var writes: [[String: Any]] { lock.withLock { bodies.filter { !TwelveMicReadGate.isReadOnly($0) } } }
    }

    func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [Fake12Mic.self]
        return URLSession(configuration: cfg)
    }

    /// 假 TotalMix 要活得和模型一样久（它的回调对自身是 unowned 引用）。
    var fakeTM: WriteTests.FakeTotalMix!

    func loadedModel() async -> AppModel {
        let tm = WriteTests.FakeTotalMix()
        fakeTM = tm
        Fake12Mic.bodies = []
        Fake12Mic.ignoreWrites = false
        Fake12Mic.routing = ["madi_optical": ["9": ["analog", 1], "10": ["analog", 2]], "phones": ["1": ["madi_optical", 33]]]
        let s = session()
        let model = AppModel(defaults: UserDefaults(suiteName: "rme.route.\(UUID())")!,
                             makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: tm.transport) },
                             makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: s) })
        await model.refresh()
        return model
    }

    let out9 = ChannelRef("12mic.madi_optical.out", 9)
    let phonesL = ChannelRef("12mic.phones.out", 1)
    let mic5 = ChannelRef("12mic.analog.in", 5)

    func testRouteGate() {
        XCTAssertNotNil(TwelveMicWriteGate.routeBody(outPort: "madi_optical", outChannel: 9, source: ("analog", 5)))
        XCTAssertEqual(TwelveMicWriteGate.routeBody(outPort: "phones", outChannel: 1, source: nil)?["routing"] as? [String: [String: [AnyHashable]]],
                       ["phones": ["1": ["unrouted", 1]]])
        XCTAssertNil(TwelveMicWriteGate.routeBody(outPort: "phones", outChannel: 3, source: ("analog", 1)))     // 耳机只有 1–2
        XCTAssertNil(TwelveMicWriteGate.routeBody(outPort: "madi_optical", outChannel: 9, source: ("analog", 13)))
        XCTAssertNil(TwelveMicWriteGate.routeBody(outPort: "avb1", outChannel: 1, source: ("analog", 1)))      // 未登记输出口
        XCTAssertNil(TwelveMicWriteGate.routeBody(outPort: "madi_optical", outChannel: 1, source: ("avb1", 1)))
    }

    func testWriteRouteNeedsMatchingConfirmation() async {
        Fake12Mic.bodies = []
        let mic = TwelveMicJSONAdapter(baseURL: URL(string: "http://12mic.test")!, session: session())
        let op = PlannedOperation(deviceID: "12mic", parameter: "routing/madi_optical/9", oldValue: nil, newValue: "x", access: .readWrite)
        let wrongTarget = PlannedOperation(deviceID: "12mic", parameter: "routing/madi_optical/10", oldValue: nil, newValue: "x", access: .readWrite)
        do { try await mic.writeRoute(destination: out9, source: mic5, for: wrongTarget,
                                      confirmation: ConfirmationGate.userConfirmed([wrongTarget])); XCTFail() } catch {}
        do { try await mic.writeRoute(destination: out9, source: mic5, for: op, confirmation: ConfirmationGate.userConfirmed([])); XCTFail() } catch {}
        XCTAssertTrue(Fake12Mic.writes.isEmpty)
        try? await mic.writeRoute(destination: out9, source: mic5, for: op, confirmation: ConfirmationGate.userConfirmed([op]))
        XCTAssertEqual(Fake12Mic.writes.count, 1)
        XCTAssertEqual(((Fake12Mic.writes[0]["routing"] as? [String: Any])?["madi_optical"] as? [String: [AnyHashable]])?["9"], ["analog", 5])
    }

    func testStageApplyVerifyUndo() async {
        let model = await loadedModel()
        XCTAssertEqual(model.twelveMicStatus, .live)
        XCTAssertEqual(model.twelveMicSource(of: out9), ChannelRef("12mic.analog.in", 1))

        XCTAssertNil(model.stageTwelveMicRoute(destination: out9, source: mic5))
        XCTAssertNil(model.stageTwelveMicRoute(destination: phonesL, source: nil))          // 断开耳机左
        XCTAssertEqual(model.pendingRoutes.count, 2)
        XCTAssertTrue(model.pendingRoutes[1].isPhones)
        XCTAssertEqual(model.pendingRoutes[0].parameter, "routing/madi_optical/9")
        XCTAssertTrue(Fake12Mic.writes.isEmpty, "暂存不发送")

        let batch = await model.applyPending(confirmation: ConfirmationGate.userConfirmed(model.pendingRoutes.map(\.operation)))
        XCTAssertEqual(Fake12Mic.writes.count, 2)
        XCTAssertEqual(batch?.verifiedCount, 2)
        XCTAssertEqual(model.twelveMicSource(of: out9), mic5)
        XCTAssertNil(model.twelveMicSource(of: phonesL))
        XCTAssertTrue(model.pendingRoutes.isEmpty)

        model.stageUndo(model.history[0])
        XCTAssertEqual(model.pendingRoutes.map(\.new), [ChannelRef("12mic.analog.in", 1), ChannelRef("12mic.madi_optical.in", 33)])
    }

    func testStagingRulesAndMismatch() async {
        let model = await loadedModel()
        // 改回原值 → 移除
        model.stageTwelveMicRoute(destination: out9, source: mic5)
        model.stageTwelveMicRoute(destination: out9, source: ChannelRef("12mic.analog.in", 1))
        XCTAssertTrue(model.pendingRoutes.isEmpty)
        // 白名单外
        XCTAssertEqual(model.stageTwelveMicRoute(destination: ChannelRef("12mic.phones.out", 3), source: mic5),
                       .notMapped(ChannelRef("12mic.phones.out", 3)))
        XCTAssertEqual(model.stageTwelveMicRoute(destination: out9, source: ChannelRef("12mic.analog.in", 13)),
                       .notMapped(ChannelRef("12mic.analog.in", 13)))
        // 设备忽略写入 → 回读不一致
        Fake12Mic.ignoreWrites = true
        model.stageTwelveMicRoute(destination: out9, source: mic5)
        let id = model.pendingRoutes[0].id
        let batch = await model.applyPending(confirmation: ConfirmationGate.userConfirmed(model.pendingRoutes.map(\.operation)))
        XCTAssertEqual(batch?.outcomes[id], .mismatchValue(readBack: "12mic.analog.in:1"))
    }

    func testTwelveMicCardsNotMerged() async {
        let model = await loadedModel()
        let cards = OutputCards.build(model.snapshot).first { $0.device.id == "12mic" }?.cards ?? []
        XCTAssertEqual(cards.map(\.address), ["12mic.madi_optical.out:9", "12mic.madi_optical.out:10", "12mic.phones.out:1"])
    }
}
