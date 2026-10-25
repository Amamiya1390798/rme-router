import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// DAW 适配与“只看有信号”（文档第 6.7 节、第 8.2 节 E1）。
@MainActor
final class DAWTests: XCTestCase {
    func writePlist(_ dict: [String: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("logic-\(UUID()).plist")
        try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0).write(to: url)
        return url
    }

    func testReadLogicDevices() throws {
        // 本机实测的样子：录音 Fireface、放音另一台，都不是 XT
        let url = try writePlist(["InputDriverName": "Fireface UFX III (24266449)", "OutputDriverName": "DAWN PRO2",
                                  "IOLabels": [["dev_1": ["type_65": ["30": ["opt": 2]]]]]])
        let s = try XCTUnwrap(LogicAudioSettings.read(url))
        XCTAssertEqual(s.inputDevice, "Fireface UFX III (24266449)")
        XCTAssertFalse(s.usesXT.input || s.usesXT.output)
        let xt = try XCTUnwrap(LogicAudioSettings.read(try writePlist(["InputDriverName": "MADIface XT (23749373)",
                                                                       "OutputDriverName": "MADIface XT (23749373)"])))
        XCTAssertTrue(xt.usesXT.input && xt.usesXT.output)
        XCTAssertNil(LogicAudioSettings.read(URL(fileURLWithPath: "/nonexistent/logic.plist")))
        XCTAssertNil(LogicAudioSettings.read(try writePlist(["Other": 1])), "没有这两项就当没读到")
    }

    func testModelReadsLogicOnRefresh() throws {
        let m = AppModel(defaults: UserDefaults(suiteName: "daw-\(UUID())")!, audioSystem: FakeAudioSystem(nil))
        m.logicPrefsURL = try writePlist(["InputDriverName": "MADIface XT", "OutputDriverName": "DAWN PRO2"])
        m.refreshAudio()
        XCTAssertEqual(m.logicSettings?.usesXT.input, true)
        XCTAssertEqual(m.logicSettings?.usesXT.output, false)
    }

    func testDAWActivePlayback() {
        let m = AppModel(defaults: UserDefaults(suiteName: "daw-\(UUID())")!, audioSystem: FakeAudioSystem(nil))
        XCTAssertNil(m.dawActivePlayback, "收不到电平：无法判断")
        m.meters.deviceLive = true
        let pb = { ChannelRef("xt.playback.in", $0) }
        m.meters.update([pb(1): -20, pb(2): -22, pb(9): -30, pb(10): -31, pb(5): -90])
        XCTAssertEqual(m.dawActivePlayback, "1–2、9–10")
    }

    func testOnlyWithSignalFilter() {
        let port = StudioSetup.topology().port("xt.phones.out")!
        let a = ChannelRef("xt.mic.in", 1), b = ChannelRef("xt.mic.in", 2)
        let card = OutputCard(port: port, channels: [1, 2],
                              sources: [.init(refs: [a], kind: .mixSend(gainDB: -6), evidence: .confirmed),
                                        .init(refs: [b], kind: .mixSend(gainDB: -6), evidence: .confirmed)],
                              hiddenPlayback: 0)
        let groups = [DeviceOutputs(device: StudioSetup.topology().device("xt")!, cards: [card])]
        let out = AppModel.onlyWithSignal(groups, active: [a])
        XCTAssertEqual(out.first?.cards.first?.sources.map(\.refs), [[a]])
        XCTAssertTrue(AppModel.onlyWithSignal(groups, active: []).isEmpty, "都没信号：整台设备不列")
    }
}
