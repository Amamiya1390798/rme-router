import Foundation
import RMECore
import RMEEngine

/// 设备页“看路径”的一段（文档第 6.4.4 节）。
public struct PathSegment: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// 设备内部的路由，带一句说明（如“11 → 9  -6.9 dB”）。
        case route(String)
        /// 实物线缆（接线表里的线）。
        case cable(linkID: String)
        /// 进电脑：XT 硬件输入 n 就是录音第 n 路。
        case recording(Int)
    }

    public var from: ChannelRef
    public var to: ChannelRef?
    public var kind: Kind
    /// 证据足够（不是演示数据、线已核对）；false 时画虚线。
    public var verified: Bool

    public var id: String { "\(from)>\(to.map(\.description) ?? "mac")" }
}

/// 一个通道的完整路径：上游到源头 + 下游到每个终点。
public struct SignalPathInfo: Equatable, Sendable {
    public var target: ChannelRef
    public var segments: [PathSegment]
    /// 一行文字：源头 → 这一路 → 去向。
    public var text: String
}

extension AppModel {
    /// 沿路由与接线追出一个通道的全部路径（只读）。
    public func signalPath(for ref: ChannelRef) -> SignalPathInfo {
        let trace = SignalTrace(snapshot: snapshot)
        let up = trace.upstream(to: ref), down = trace.downstream(from: ref)
        let topo = snapshot.topology
        var segments: [PathSegment] = []
        var seen: Set<String> = []
        func add(_ s: PathSegment) { if seen.insert(s.id).inserted { segments.append(s) } }

        for step in (up + down).flatMap({ $0 }) {
            switch step.hop {
            case let .cable(f, t):
                guard let link = topo.links.first(where: { $0.from == f.portID && $0.to == t.portID }) else { continue }
                add(PathSegment(from: f, to: t, kind: .cable(linkID: link.id),
                                verified: linkVerifications[LinkVerification.key(f.portID, t.portID)] != nil))
            case let .route(f, t, domain, kind):
                var label = "\(f.channel) → \(t.channel)"
                if case let .mixSend(g?) = kind { label += String(format: "  %.1f dB", g) }
                if domain == .xtc, case .blockAssign = kind { label = "\(f.channel)–\(f.channel + 7) → \(t.channel)–\(t.channel + 7)" }
                add(PathSegment(from: f, to: t, kind: .route(label), verified: step.evidence != .unknown))
            }
        }
        // 经过的 XT 硬件输入都直接进电脑录音
        let nodes = Set(segments.flatMap { [$0.from] + ($0.to.map { [$0] } ?? []) } + [ref])
        for n in nodes.sorted() {
            guard let p = topo.port(n.portID), p.deviceID == "xt", p.direction == .input, p.type != .usb else { continue }
            add(PathSegment(from: n, to: nil, kind: .recording(tmChannel(for: n)?.number ?? n.channel), verified: true))
        }

        let origins = Set(up.compactMap { $0.first?.hop.from }).sorted()
        let ends = Set(down.compactMap { $0.last?.hop.to }).sorted()
        let recording = segments.compactMap { s -> String? in if case let .recording(n) = s.kind { return "电脑录音 \(n)" } else { return nil } }
        var parts: [String] = []
        if !origins.isEmpty { parts.append(origins.prefix(3).map(shortName).joined(separator: "、")) }
        parts.append(shortName(ref))
        let outs = ends.prefix(4).map(shortName) + recording
        if !outs.isEmpty { parts.append(outs.joined(separator: "、") + (ends.count > 4 ? " 等" : "")) }
        let text = parts.count == 1 ? "\(shortName(ref))：没有路由也没有接线" : parts.joined(separator: " → ")
        return SignalPathInfo(target: ref, segments: segments, text: text)
    }

    /// 一个通道在面板上画在哪：当前这一面的接口 `conn:<id>`；只在另一面 → `edge:<设备>`（再给一个标签）；
    /// 没有面板的设备 → `node:<设备>`。
    public func pathAnchor(_ ref: ChannelRef, face: PanelFace) -> (key: String, offFace: String?)? {
        guard let port = snapshot.topology.port(ref.portID) else { return nil }
        func find(_ f: PanelFace) -> PanelConnector? {
            guard let p = PanelLayout.panel(port.deviceID, f) else { return nil }
            return p.connectors.first { $0.ports.contains(ref.portID) && $0.channel == ref.channel }
                ?? p.connectors.first { $0.ports.contains(ref.portID) && $0.channel == nil }
        }
        if let c = find(face) { return ("conn:\(c.id)", nil) }
        let other: PanelFace = face == .rear ? .front : .rear
        if let c = find(other) { return ("edge:\(port.deviceID)", "\(other == .front ? "前" : "后") · \(c.name)") }
        if PanelLayout.all.contains(where: { $0.deviceID == port.deviceID }) { return nil }
        return ("node:\(port.deviceID)", nil)
    }
}

/// 在面板上从一个接口拖到另一个接口时要做的事（第 6.4.4 节“拖线”）。
public enum DragIntent: Equatable, Sendable {
    /// 接实物线：只改接线表。
    case addLink(from: String, to: String)
    /// 送一路声音：打开“跨设备送一路声音”，来源和去处已填好。
    case send(from: ChannelRef, to: ChannelRef)
    case rejected(String)
}

extension AppModel {
    public func dragIntent(from a: PanelConnector, to b: PanelConnector) -> DragIntent {
        guard a.id != b.id else { return .rejected("同一个接口") }
        guard a.routes, b.routes else { return .rejected("这个接口不参与路由（电源、时钟、网络、控制）") }
        let topo = snapshot.topology
        func port(_ c: PanelConnector, _ d: Direction) -> RMECore.Port? {
            c.ports.compactMap(topo.port).first { $0.direction == d }
        }
        if let out = port(a, .output), let inp = port(b, .input), out.deviceID != inp.deviceID {
            if topo.links.contains(where: { $0.from == out.id && $0.to == inp.id }) { return .rejected("这根线已经有了") }
            return .addLink(from: out.id, to: inp.id)
        }
        guard let src = port(a, .input) ?? port(a, .output) else { return .rejected("起点不是音频接口") }
        let terminals = Set(snapshot.terminals.map(\.deviceID))
        guard let dst = port(b, .output) ?? port(b, .input).flatMap({ terminals.contains($0.deviceID) ? $0 : nil }) else {
            return .rejected("终点要是输出口（或 P16 这类终端的输入）")
        }
        return .send(from: ChannelRef(src.id, a.channel ?? 1), to: ChannelRef(dst.id, b.channel ?? 1))
    }
}
