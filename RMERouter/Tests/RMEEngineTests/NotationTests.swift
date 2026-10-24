import XCTest
@testable import RMECore

/// 第 6.1 节链路表示法：地址解析、格式化与路径不变量。
final class NotationTests: XCTestCase {
    func testParseSingleAndRange() throws {
        XCTAssertEqual(try Notation.parse("xt.madi1.in:9"), [ChannelRef("xt.madi1.in", 9)])
        XCTAssertEqual(try Notation.parse("xtc.madi.out:1-3").map(\.channel), [1, 2, 3])
        XCTAssertThrowsError(try Notation.parse("xt.madi1:9"))       // 缺方向
        XCTAssertThrowsError(try Notation.parse("xt.madi1.in:0"))    // 通道从 1 起
        XCTAssertThrowsError(try Notation.parse("xt.madi1.in:5-2"))  // 范围倒置
    }

    func testFormatCompressesRanges() {
        let refs = [9, 10, 11, 20].map { ChannelRef("12mic.madi_optical.out", $0) }
        XCTAssertEqual(Notation.format(refs), ["12mic.madi_optical.out:9-11", "12mic.madi_optical.out:20"])
        XCTAssertEqual(ChannelRef("xt.madi1.in", 9).description, "xt.madi1.in:9")
    }

    /// 实机示例：XTC Mic 1 → 12Mic 耳机左，跨三台设备。
    func testCrossDevicePathIsConsistent() {
        let topo = Fixture.topology()
        let hops: [Hop] = [
            .route(from: ChannelRef("xtc.mic.in", 1), to: ChannelRef("xtc.madi.out", 1), domain: .xtc, kind: .blockAssign(size: 8)),
            .cable(from: ChannelRef("xtc.madi.out", 1), to: ChannelRef("xt.madi2.in", 1)),
            .route(from: ChannelRef("xt.madi2.in", 1), to: ChannelRef("xt.madi1.out", 33), domain: .totalMix, kind: .mixSend(gainDB: 0)),
            .cable(from: ChannelRef("xt.madi1.out", 33), to: ChannelRef("12mic.madi_optical.in", 33)),
            .route(from: ChannelRef("12mic.madi_optical.in", 33), to: ChannelRef("12mic.phones.out", 1), domain: .twelveMic, kind: .passthrough),
        ]
        XCTAssertEqual(PathInvariants.violations(hops, in: topo), [])
    }

    func testInvariantsCatchBrokenPath() {
        let topo = Fixture.topology()
        let hops: [Hop] = [
            .cable(from: ChannelRef("xt.madi1.out", 1), to: ChannelRef("12mic.madi_optical.in", 2)),  // 线缆改了通道号
            .route(from: ChannelRef("xt.madi2.in", 1), to: ChannelRef("xt.madi2.out", 1), domain: .totalMix, kind: .mixSend(gainDB: 0)), // 没接上
        ]
        let v = PathInvariants.violations(hops, in: topo)
        XCTAssertTrue(v.contains { $0.contains("不改变通道号") })
        XCTAssertTrue(v.contains { $0.contains("没有接上") })
    }
}
