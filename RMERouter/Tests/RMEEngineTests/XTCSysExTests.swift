import XCTest
@testable import RMECore
@testable import RMEAdapters

/// OctaMic XTC SysEx 编解码与翻译（文档第 6.3 节）。纯逻辑，不碰设备。
final class XTCSysExTests: XCTestCase {

    func testRequestAll() throws {
        XCTAssertEqual(try XTCSysEx.request(.requestAll, device: 0), [0xF0, 0x00, 0x20, 0x0D, 0x69, 0x00, 0x10, 0xF7])
        XCTAssertEqual(try XTCSysEx.request(.requestLevels, device: 3), [0xF0, 0x00, 0x20, 0x0D, 0x69, 0x03, 0x11, 0xF7])
        XCTAssertThrowsError(try XTCSysEx.request(.requestAll, device: 128))
    }

    /// 手册第 29 章的例子：Mic 2 增益 37 dB、Pad 开；参数 10 = 30 10 0d。
    func testManualExample() throws {
        let bytes: [UInt8] = [0xF0, 0x00, 0x20, 0x00, 0x69, 0x00, 0x20, 0x01, 0x1C, 0x08, 0x7F, 0x0A, 0x30, 0x10, 0x0D, 0xF7]
        // 手册例子的厂商号第 3 字节印成了 0，按正式格式改为 0D 再解析。
        var fixed = bytes; fixed[3] = 0x0D
        let msg = try XCTUnwrap(XTCSysEx.parse(fixed))
        XCTAssertEqual(msg.command, 0x20)
        XCTAssertEqual(msg.params, [.init(index: 1, lsb: 0x1C, msb: 0x08, flags: 0x7F), .init(index: 0x0A, lsb: 0x30, msb: 0x10, flags: 0x0D)])
        let mic = XTCMicSettings(lsb: 0x1C, msb: 0x08)
        XCTAssertEqual(mic.gainDB, 37)
        XCTAssertTrue(mic.padOrInstrument)
        XCTAssertFalse(mic.phantom)
        // 编码回去一字不差。
        XCTAssertEqual(try XTCSysEx.set(msg.params, device: 0), fixed)
        // 原样（厂商号错）不认。
        XCTAssertNil(XTCSysEx.parse(bytes))
    }

    func testSetRejectsHighBytes() {
        XCTAssertThrowsError(try XTCSysEx.set([.init(index: 0, lsb: 0x80, msb: 0, flags: 0x01)], device: 0)) {
            XCTAssertEqual($0 as? XTCSysEx.CodecError, .dataByte(0x80))
        }
    }

    func testGainCode() {
        XCTAssertEqual(XTCMicSettings.gain(fromCode: 0), 0)
        XCTAssertEqual(XTCMicSettings.gain(fromCode: 1), 10)
        XCTAssertEqual(XTCMicSettings.gain(fromCode: 56), 65)
        XCTAssertEqual(XTCMicSettings.code(fromGain: 0), 0)
        XCTAssertEqual(XTCMicSettings.code(fromGain: 37), 28)
        XCTAssertEqual(XTCMicSettings.code(fromGain: 3), 1)    // 1–9 dB 按 10 dB（文档第 6.3 节）
        XCTAssertEqual(XTCMicSettings.code(fromGain: 0.2), 0)
        XCTAssertEqual(XTCMicSettings.effectiveGain(4), 10)
        XCTAssertEqual(XTCMicSettings.code(fromGain: 80), 56)
    }

    /// 设备回包（命令 30）：路由、时钟、Lock/Sync、话放。
    func testStateFromSend() throws {
        let reply: [UInt8] = XTCSysEx.header + [0x00, 0x30,
            0x00, 0x45, 0x04,        // Mic 1：增益码 5 = 14 dB、反相；48V
            0x0E, 0x03, 0x00,        // ADAT1 ← MADI 1–8，ADAT2 ← Mic
            0x10, 0x00, 0x0A,        // MADI 输出 1–8 ← Mic，9–16 ← MADI 57–64
            0x15, 0x07, 0x02,        // 时钟 MADI、48 kHz
            0x19, 0x20, 0x20,        // MADI Lock + Sync
            XTCSysEx.end]
        let msg = try XCTUnwrap(XTCSysEx.parse(reply))
        var s = XTCState(); s.apply(msg.params)

        XCTAssertEqual(s.mics[1]?.gainDB, 14)
        XCTAssertEqual(s.mics[1]?.phase, true)
        XCTAssertEqual(s.mics[1]?.phantom, true)
        XCTAssertEqual(s.routing[.adat1], .madi(block: 0))
        XCTAssertEqual(s.routing[.adat2], .mic)
        XCTAssertEqual(s.routing[.madi(block: 0)], .mic)
        XCTAssertEqual(s.routing[.madi(block: 1)], .madi(block: 7))
        XCTAssertEqual(s.clockSource, 7)
        XCTAssertEqual(s.sampleRate, 48_000)
        XCTAssertEqual(s.madiLock, true)
        XCTAssertEqual(s.madiSync, true)

        let routes = s.routes()
        XCTAssertEqual(routes.count, 32)
        XCTAssertTrue(routes.contains { $0.source == ChannelRef("xtc.madi.in", 57) && $0.destination == ChannelRef("xtc.madi.out", 9) })
        XCTAssertTrue(routes.contains { $0.source == ChannelRef("xtc.madi.in", 8) && $0.destination == ChannelRef("xtc.adat1.out", 8) })
        XCTAssertTrue(routes.allSatisfy { $0.domain == .xtc && $0.source.offsetInBlock == $0.destination.offsetInBlock })
    }

    /// 回放来源（电脑 USB）没有登记端口：不产生路由，但状态里保留。
    func testPlaybackSourceHasNoRoute() {
        var s = XTCState()
        s.apply([.init(index: 14, lsb: 11, msb: 2)])
        XCTAssertEqual(s.routing[.adat1], .playback(value: 11))
        XCTAssertEqual(s.routing[.adat2], .aesIn)
        XCTAssertTrue(s.routes().isEmpty)
    }

    /// 设置一块：只带这一半的置位标志，另一半不动。
    func testRoutingSetParam() throws {
        let out = try XCTUnwrap(XTCRoutingOutput(portID: "xtc.madi.out", channel: 17))
        XCTAssertEqual(out, .madi(block: 2))
        let src = try XCTUnwrap(XTCRoutingSource(firstChannel: ChannelRef("xtc.madi.in", 9)))
        XCTAssertEqual(out.setParam(src), .init(index: 17, lsb: 4, msb: 0, flags: 0x01))
        XCTAssertEqual(XTCRoutingOutput.madi(block: 3).setParam(.mic), .init(index: 17, lsb: 0, msb: 0, flags: 0x02))
        XCTAssertNil(XTCRoutingSource(firstChannel: ChannelRef("xtc.madi.in", 10)))   // 不在块首
        XCTAssertNil(XTCRoutingOutput(portID: "xtc.adat1.out", channel: 9))
    }

    /// 改一路话放：只带要改的字段的置位标志（手册：增益 0x01、反相 0x02、48V 0x10）。
    func testMicSetParam() {
        XCTAssertEqual(XTCMicSettings.setParam(mic: 2, gainDB: 37), .init(index: 1, lsb: 28, msb: 0, flags: 0x01))
        XCTAssertEqual(XTCMicSettings.setParam(mic: 1, phantom: true), .init(index: 0, lsb: 0, msb: 0x04, flags: 0x10))
        XCTAssertEqual(XTCMicSettings.setParam(mic: 8, gainDB: 0, phase: true), .init(index: 7, lsb: 0x40, msb: 0, flags: 0x03))
    }

    func testLevels() {
        XCTAssertEqual(XTCLevel.dB(125), 0)
        XCTAssertEqual(XTCLevel.dB(126), 0.1)
        XCTAssertEqual(XTCLevel.dB(94), -6.5)
        XCTAssertEqual(XTCLevel.dB(23), -42)
        XCTAssertEqual(XTCLevel.dB(22), -43)
        XCTAssertEqual(XTCLevel.dB(1), -64)
        XCTAssertNil(XTCLevel.dB(0))
    }
}
