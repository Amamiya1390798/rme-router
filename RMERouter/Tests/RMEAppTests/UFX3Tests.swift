import XCTest
@testable import RMECore
@testable import RMEAdapters
@testable import RMEApp

/// Fireface UFX III 档案（文档第 6.4.6 节，出处官方手册）。
@MainActor
final class UFX3Tests: XCTestCase {
    override func tearDown() {
        StudioConfig.current = StudioConfig()
        PreampField.totalMixGainMax = 60
    }

    /// TotalMix 通道顺序：模拟 12、AES 2、ADAT 2×n、MADI m；单 / 双 / 四速。
    func testLayout() throws {
        let inp = try XCTUnwrap(TotalMixChannelMap.ufx3Layout(bus: .input, maxNumber: 94))
        XCTAssertEqual(inp.count, 94)
        XCTAssertEqual(inp[0], ChannelRef("xt.line.in", 1))
        XCTAssertEqual(inp[8], ChannelRef("xt.mic.in", 1), "模拟 9 = 前面板 Mic 1")
        XCTAssertEqual(inp[12], ChannelRef("xt.aes.in", 1))
        XCTAssertEqual(inp[14], ChannelRef("xt.adat1.in", 1))
        XCTAssertEqual(inp[22], ChannelRef("xt.adat2.in", 1))
        XCTAssertEqual(inp[30], ChannelRef("xt.madi.in", 1))
        let out = try XCTUnwrap(TotalMixChannelMap.ufx3Layout(bus: .output, maxNumber: 94))
        XCTAssertEqual(out[8], ChannelRef("xt.phones.out", 1), "模拟输出 9 = Phones 1")
        // 双速：ADAT 每口 4，MADI 32 → 54 路；四速 34 路
        XCTAssertEqual(TotalMixChannelMap.ufx3Layout(bus: .input, maxNumber: 54)?[22], ChannelRef("xt.madi.in", 1))
        XCTAssertEqual(TotalMixChannelMap.ufx3Layout(bus: .input, maxNumber: 34)?.last, ChannelRef("xt.madi.in", 16))
        XCTAssertNil(TotalMixChannelMap.ufx3Layout(bus: .input, maxNumber: 70), "推不出速率时不按位置映射")
    }

    /// 对照表按位置推断（不看名字），记为“推断”。
    func testInferByPosition() {
        var state = TotalMixState()
        for n in 0 ..< 94 {
            state.apply(OSCMessage("/input/\(n)/mute", [.float(0)]))
            state.apply(OSCMessage("/output/\(n)/mute", [.float(0)]))
        }
        var map = TotalMixChannelMap()
        map.layout = .ufx3
        map.infer(from: state)
        XCTAssertEqual(map[TotalMixChannel(.input, 9)]?.ref, ChannelRef("xt.mic.in", 1))
        XCTAssertEqual(map[TotalMixChannel(.input, 9)]?.evidence, .inferred)
        XCTAssertEqual(map[TotalMixChannel(.output, 94)]?.ref, ChannelRef("xt.madi.out", 64))
    }

    /// 选 UFX III：拓扑、路由能力、默认接线、话放上限 75 dB。
    func testConfig() async {
        let d = UserDefaults(suiteName: "ufx3-\(UUID())")!
        if let data = try? JSONEncoder().encode(StudioConfig(mainCard: .ufx3)) { d.set(data, forKey: StudioConfig.defaultsKey) }
        let m = AppModel(defaults: d)
        let xt = m.snapshot.topology.device("xt")
        XCTAssertEqual(xt?.model, .firefaceUFX3)
        XCTAssertEqual(xt?.ports.filter { $0.direction == .input && $0.id != "xt.playback.in" }.map(\.singleSpeedChannels).reduce(0, +), 94)
        XCTAssertTrue(m.snapshot.topology.links.contains { $0.to == "xt.madi.in" })
        XCTAssertTrue(m.snapshot.capabilities.first { $0.deviceID == "xt" }?.inputPorts.contains("xt.adat2.in") == true)
        XCTAssertEqual(PreampField.gainRange(device: "xt").upperBound, 75)
        XCTAssertEqual(PreampField.gainRange(device: "12mic").upperBound, 60)
        XCTAssertEqual(TotalMixWrite.preamp(input: TotalMixChannel(.input, 9), field: .gain, value: .gain(80)).message.arguments.first, .float(75))
    }
}
