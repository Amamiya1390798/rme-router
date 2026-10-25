import XCTest
@testable import RMECore
@testable import RMEAdapters

/// 12Mic 只读客户端（文档第 6.2 节）：请求体全为 null、回包解析、离线处理。用 URLProtocol 假设备，不碰网络。
final class TwelveMicTests: XCTestCase {

    /// 假 12Mic：记录收到的请求体，按请求里的顶层键返回预设回包。
    final class Fake12Mic: URLProtocol {
        nonisolated(unsafe) static var bodies: [[String: Any]] = []
        nonisolated(unsafe) static var reply: [String: Any] = [:]
        nonisolated(unsafe) static var offline = false
        static let lock = NSLock()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            if Self.offline {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            let data = request.httpBody ?? request.httpBodyStream.map(Self.readAll) ?? Data()
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            Self.lock.withLock { Self.bodies.append(body) }
            var out: [String: Any] = [:]
            for key in body.keys { out[key] = Self.reply[key] }
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: out))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}

        static func readAll(_ s: InputStream) -> Data {
            s.open(); defer { s.close() }
            var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
            return d
        }
    }

    /// 回包形状按手册示例：routing 值为 ["<输入口>", 通道] 或 ["unrouted", 1]。
    static let sampleReply: [String: Any] = [
        "device": ["entity_name": "12Mic"],
        "clock": [
            "current_sampling_rate": 48000,
            "source": "madi_optical",
            "sources": [
                "madi_optical": ["rate": 48000, "sync": true],
                "madi_coaxial": ["rate": "NoLock", "sync": false],
            ],
            "soundness": ["state": "Good"],
        ],
        "output": ["madi": ["mode": 64, "framesize": 48]],
        "routing": [
            "madi_optical": ["9": ["analog", 1], "10": ["analog", 2], "1": ["unrouted", 1], "40": ["avb1", 3]],
            "phones": ["1": ["madi_optical", 33], "2": ["madi_optical", 34]],
        ],
    ]

    var adapter: TwelveMicJSONAdapter!

    override func setUp() {
        Fake12Mic.bodies = []
        Fake12Mic.reply = Self.sampleReply
        Fake12Mic.offline = false
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [Fake12Mic.self]
        adapter = TwelveMicJSONAdapter(baseURL: URL(string: "http://12mic.test")!, session: URLSession(configuration: cfg))
    }

    func testReadGate() {
        XCTAssertTrue(TwelveMicReadGate.isReadOnly(["clock": NSNull(), "output": ["madi": NSNull()]]))
        XCTAssertFalse(TwelveMicReadGate.isReadOnly(["device": ["identify": true]]))       // 手册例：会让面板闪烁
        XCTAssertFalse(TwelveMicReadGate.isReadOnly(["routing": ["phones": ["1": ["analog", 1]]]]))
        XCTAssertFalse(TwelveMicReadGate.isReadOnly([String: Any]()))
        XCTAssertFalse(TwelveMicReadGate.isReadOnly(["device": [String: Any]()]))
    }

    func testReadRefusesNonNullBodyWithoutSending() async {
        do {
            _ = try await adapter.read(["device": ["identify": true]])
            XCTFail("应当拦截")
        } catch {}
        XCTAssertTrue(Fake12Mic.bodies.isEmpty, "被拦截的请求不应发出")
    }

    func testSnapshotParsesAndSendsOnlyNulls() async throws {
        let snap = try await adapter.snapshot()
        XCTAssertFalse(Fake12Mic.bodies.isEmpty)
        for body in Fake12Mic.bodies { XCTAssertTrue(TwelveMicReadGate.isReadOnly(body), "\(body)") }

        XCTAssertEqual(snap.routes.map { "\($0.source) -> \($0.destination)" }, [
            "12mic.analog.in:1 -> 12mic.madi_optical.out:9",
            "12mic.analog.in:2 -> 12mic.madi_optical.out:10",
            "12mic.madi_optical.in:33 -> 12mic.phones.out:1",
            "12mic.madi_optical.in:34 -> 12mic.phones.out:2",
        ])
        XCTAssertTrue(snap.routes.allSatisfy { $0.evidence == .confirmed && $0.kind == .passthrough })
        XCTAssertEqual(snap.clock.configuredRate.knownValue, 48000)
        XCTAssertEqual(snap.clock.source.knownValue, .port("12mic.madi_optical.in"))
        XCTAssertEqual(snap.clock.lock["12mic.madi_optical.in"]?.value, true)
        XCTAssertEqual(snap.clock.lock["12mic.madi_coaxial.in"]?.value, false)
        XCTAssertEqual(snap.clock.lock["12mic.madi_coaxial.in"]?.evidence, .inferred)   // 未锁定取值手册未写
        XCTAssertEqual(snap.clock.sync["12mic.madi_optical.in"]?.value, true)
        XCTAssertEqual(snap.portFormats["12mic.madi_optical.out"]?.knownValue?.channelMode, .ch64)
        XCTAssertNil(snap.portFormats["12mic.phones.out"])
        XCTAssertEqual(snap.settings["12mic.entityName"]?.knownValue, "12Mic")
        XCTAssertEqual(snap.settings["12mic.clock.soundness"]?.knownValue, "Good")
        XCTAssertEqual(snap.settings["12mic.unknownInputPorts"]?.knownValue, "avb1×1")      // 未登记的输入口计数
        XCTAssertEqual(snap.controlPaths.first?.state, .online)
    }

    func testProbeUsesDocumentedKey() async {
        let path = await adapter.probe()
        XCTAssertEqual(path.state, .online)
        XCTAssertEqual(Fake12Mic.bodies.first?["device"] as? [String: NSNull], ["entity_name": NSNull()])
    }

    func testOffline() async {
        Fake12Mic.offline = true
        let path = await adapter.probe()
        XCTAssertEqual(path.state, .offline)
        do { _ = try await adapter.snapshot(); XCTFail() } catch {
            XCTAssertEqual(error as? AdapterError, .unreachable)
        }
    }
}
