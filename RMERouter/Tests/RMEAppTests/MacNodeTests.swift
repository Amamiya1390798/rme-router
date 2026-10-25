import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// “这台 Mac”节点（文档第 6.6 节）：用假的音频系统。
@MainActor
final class MacNodeTests: XCTestCase {
    func xt(rate: Double = 48_000) -> AudioDeviceInfo {
        AudioDeviceInfo(id: 77, name: "MADIface XT (23749373)", transport: "USB", sampleRate: rate,
                        availableRates: [44_100, 48_000, 88_200, 96_000], inputs: 196, outputs: 198, running: true,
                        clients: [AudioClient(pid: 999_999, bundleID: "com.apple.logic10", input: true, output: true)])
    }

    func testReadsDeviceAndFillsXTClock() {
        let audio = FakeAudioSystem(xt())
        let m = AppModel(defaults: UserDefaults(suiteName: "mac-\(UUID())")!, audioSystem: audio)
        m.apply(xt: StudioSetup.emptyXT(reason: "测试"))
        m.refreshAudio()
        XCTAssertEqual(m.xtAudio?.inputs, 196)
        XCTAssertEqual(m.xtAudioClients.first?.name, "com.apple.logic10", "进程不在时退回 bundle id")
        let rate = m.snapshot.devices["xt"]?.clock.configuredRate
        XCTAssertEqual(rate?.knownValue, 48_000)
        XCTAssertEqual(rate?.evidence, .confirmed)
        XCTAssertEqual(rate?.source.interface, "coreaudio")
        // 没变就不改快照
        let v = m.snapshotVersion
        m.refreshAudio()
        XCTAssertEqual(m.snapshotVersion, v)
    }

    func testNoXT() {
        let m = AppModel(defaults: UserDefaults(suiteName: "mac-\(UUID())")!, audioSystem: FakeAudioSystem(nil))
        m.refreshAudio()
        XCTAssertNil(m.xtAudio)
        XCTAssertTrue(m.audioChecked)
    }

    func testSetSampleRateVerifies() async {
        let audio = FakeAudioSystem(xt())
        let m = AppModel(defaults: UserDefaults(suiteName: "mac-\(UUID())")!, audioSystem: audio)
        m.refreshAudio()
        let ok = await m.setXTSampleRate(96_000)
        XCTAssertNil(ok)
        XCTAssertEqual(m.xtAudio?.sampleRate, 96_000)
        let bad = await m.setXTSampleRate(192_000)
        XCTAssertEqual(bad, "XT 不支持 192 kHz")
        XCTAssertEqual(AppModel.rateText(44_100), "44.1 kHz")
    }
}
