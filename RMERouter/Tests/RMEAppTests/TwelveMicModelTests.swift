import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// App 接入 12Mic：读到就替换演示数据，读不到保留演示数据并说明原因。
@MainActor
final class TwelveMicModelTests: XCTestCase {

    final class Stub: URLProtocol {
        nonisolated(unsafe) static var offline = false
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            if Self.offline { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return }
            let reply: [String: Any] = [
                "device": ["entity_name": "12Mic"],
                "clock": ["current_sampling_rate": 48000, "source": "internal"],
                "routing": ["madi_optical": ["9": ["analog", 1]]],
                "output": ["madi": ["mode": 64, "framesize": 48]],
            ]
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: reply))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    func makeModel() -> AppModel {
        let fakeTM = WriteTests.FakeTotalMix()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [Stub.self]
        let session = URLSession(configuration: cfg)
        return AppModel(defaults: UserDefaults(suiteName: "rme.12mic.\(UUID())")!,
                        makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: fakeTM.transport) },
                        makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: session) })
    }

    func testLiveTwelveMicReplacesDemo() async {
        Stub.offline = false
        let model = makeModel()
        XCTAssertTrue(model.isDemo("12mic"))
        await model.refresh()
        XCTAssertEqual(model.twelveMicStatus, .live)
        XCTAssertFalse(model.isDemo("12mic"))
        XCTAssertEqual(model.snapshot.devices["12mic"]?.routes.count, 1)              // 演示数据是 12 条
        XCTAssertEqual(model.snapshot.devices["12mic"]?.routes.first?.evidence, .confirmed)
        XCTAssertEqual(model.xtStatus, .offlineSaved)                                   // TotalMix 同时读到
        XCTAssertNotNil(model.snapshot.devices["xt"]?.routes.first)
    }

    func testOfflineTwelveMicKeepsDemo() async {
        Stub.offline = true
        let model = makeModel()
        await model.refresh()
        guard case .unreachable = model.twelveMicStatus else { return XCTFail("应为 unreachable") }
        XCTAssertTrue(model.isDemo("12mic"))
        XCTAssertEqual(model.snapshot.devices["12mic"]?.routes.count, 12)
    }

    func testInvalidURL() async {
        let model = makeModel()
        model.twelveMicURL = "不是地址"
        await model.refreshTwelveMic()
        XCTAssertEqual(model.twelveMicStatus, .unreachable("12Mic 地址无效：不是地址"))
    }

    func testURLPersists() {
        let defaults = UserDefaults(suiteName: "rme.12mic.\(UUID())")!
        AppModel(defaults: defaults).twelveMicURL = "http://172.20.0.1"
        XCTAssertEqual(AppModel(defaults: defaults).twelveMicURL, "http://172.20.0.1")
    }
}
