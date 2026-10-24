import XCTest
@testable import RMECore
@testable import RMEEngine

/// 信号流追踪：沿已有路由与线缆走完整条跨设备路径。
final class SignalTraceTests: XCTestCase {
    let mic1 = ChannelRef("12mic.analog.in", 1)
    let p16ch1 = ChannelRef("p16i.adat_a.in", 1)

    /// 黄金配置 + XT 上一条发送：12Mic Mic 1 一路送到 P16 通道 1。
    func snapshotWithXTSend() -> SystemSnapshot {
        var s = Fixture.golden()
        s.devices["xt"]!.routes = [Route(domain: .totalMix, source: ChannelRef("xt.madi1.in", 9),
                                         destination: ChannelRef("xt.madi2.out", 1), kind: .mixSend(gainDB: 0),
                                         evidence: .inferred)]
        return s
    }

    func testDownstreamFollowsRoutesAndCables() {
        let paths = SignalTrace(snapshot: snapshotWithXTSend()).downstream(from: mic1)
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths[0].map(\.hop.description), [
            "12mic.analog.in:1 →[twelveMic 直通] 12mic.madi_optical.out:9",
            "12mic.madi_optical.out:9 ⇒ xt.madi1.in:9",
            "xt.madi1.in:9 →[totalMix 发送 0.0 dB] xt.madi2.out:1",
            "xt.madi2.out:1 ⇒ xtc.madi.in:1",
            "xtc.madi.in:1 →[xtc 8 路块] xtc.adat1.out:1",
            "xtc.adat1.out:1 ⇒ p16i.adat_a.in:1",
        ])
        XCTAssertEqual(paths[0].map(\.evidence), [.confirmed, .documented, .inferred, .documented, .confirmed, .documented])
        XCTAssertTrue(PathInvariants.violations(paths[0].map(\.hop), in: Fixture.topology()).isEmpty)
    }

    func testUpstreamFindsSourceInSignalOrder() {
        let trace = SignalTrace(snapshot: snapshotWithXTSend())
        let up = trace.upstream(to: p16ch1)
        XCTAssertEqual(up.count, 1)
        XCTAssertEqual(up[0].first?.hop.from, mic1)
        XCTAssertEqual(up[0].last?.hop.to, p16ch1)
        XCTAssertEqual(up[0], trace.downstream(from: mic1)[0])
        XCTAssertEqual(trace.destinations(of: mic1), [p16ch1])
    }

    /// 实机拓扑里 XT 与 12Mic 互连成环：追踪必须停下，不重复经过同一通道。
    func testLoopTerminates() {
        var s = snapshotWithXTSend()
        s.devices["xt"]!.routes.append(Route(domain: .totalMix, source: ChannelRef("xt.madi1.in", 9),
                                             destination: ChannelRef("xt.madi1.out", 9), kind: .mixSend(gainDB: 0),
                                             evidence: .inferred))
        s.devices["12mic"]!.routes.append(Route(domain: .twelveMic, source: ChannelRef("12mic.madi_optical.in", 9),
                                                destination: ChannelRef("12mic.madi_optical.out", 9), kind: .passthrough,
                                                evidence: .confirmed))
        let paths = SignalTrace(snapshot: s).downstream(from: mic1)
        XCTAssertEqual(paths.count, 2)
        for p in paths {
            let nodes = [p[0].hop.from] + p.map(\.hop.to)
            XCTAssertEqual(Set(nodes).count, nodes.count, "路径里有重复通道：\(nodes)")
        }
    }

    func testChannelWithoutRoutesHasNoPaths() {
        XCTAssertEqual(SignalTrace(snapshot: Fixture.golden()).downstream(from: ChannelRef("xtc.mic.in", 3)), [])
    }
}
