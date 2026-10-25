import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// 检查器（阶段 B2）：一个通道的来去、TotalMix 名字、前级、待应用、体检。
@MainActor
final class InspectorTests: XCTestCase {
    var fakeTM: WriteTests.FakeTotalMix!

    func loadedModel() async -> AppModel {
        let tm = WriteTests.FakeTotalMix()
        fakeTM = tm
        RouteWriteTests.Fake12Mic.ignoreWrites = false
        RouteWriteTests.Fake12Mic.routing = ["madi_optical": ["9": ["analog", 1]], "phones": ["1": ["madi_optical", 33]]]
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [RouteWriteTests.Fake12Mic.self]
        let session = URLSession(configuration: cfg)
        let model = AppModel(defaults: UserDefaults(suiteName: "rme.insp.\(UUID())")!,
                             makeAdapter: { TotalMixOSCAdapter(port: $0.port, transport: tm.transport) },
                             makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: session) })
        await model.refresh()
        return model
    }

    func testXTMicInput() async {
        let model = await loadedModel()
        let mic1 = ChannelRef("xt.mic.in", 1)
        let info = model.inspectorInfo(mic1)
        XCTAssertEqual(info.deviceName, "MADIface XT")
        XCTAssertTrue(info.isInput)
        XCTAssertEqual(info.totalMix, "input 1（Mic 1）")
        XCTAssertEqual(info.totalMixEvidence, .inferred)
        XCTAssertEqual(info.preamp?.gainDB.knownValue, 20)
        XCTAssertTrue(info.from.isEmpty)
        XCTAssertEqual(info.to.first?.ref, ChannelRef("xt.phones.out", 1))
        XCTAssertEqual(info.to.first?.via, "TotalMix -6.9 dB")
        XCTAssertTrue(info.endpoints.contains(ChannelRef("xt.phones.out", 1)))

        model.stagePreamp(deviceID: "xt", input: mic1, field: .phantom, value: .flag(true))
        XCTAssertEqual(model.inspectorInfo(mic1).pending, ["48V：关 → 开"])
    }

    func testTwelveMicOutputFollowsCable() async {
        let model = await loadedModel()
        let info = model.inspectorInfo(ChannelRef("12mic.madi_optical.out", 9))
        XCTAssertEqual(info.from.map(\.ref), [ChannelRef("12mic.analog.in", 1)])
        XCTAssertEqual(info.from.first?.via, "12Mic 直通")
        XCTAssertEqual(info.to.map(\.ref), [ChannelRef("xt.madi1.in", 9)])
        XCTAssertEqual(info.to.first?.via, "线缆")
        XCTAssertEqual(info.origins, [ChannelRef("12mic.analog.in", 1)])
    }

    func testTargetFollowsTraceUnlessExplicit() async {
        let model = await loadedModel()
        model.traceTarget = ChannelRef("xt.mic.in", 2)
        XCTAssertEqual(model.inspectorTarget, ChannelRef("xt.mic.in", 2))
        model.inspect(ChannelRef("xt.phones.out", 1))
        XCTAssertTrue(model.showInspector)
        XCTAssertEqual(model.inspectorTarget, ChannelRef("xt.phones.out", 1))
    }
}
