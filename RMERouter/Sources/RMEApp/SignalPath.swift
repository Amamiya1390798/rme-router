import Foundation
import RMECore
import RMEEngine
import RMEAdapters

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

/// 选中一个接口时要在通道条上高亮的东西（第 6.4.4 节“选接口看链路”）。
public struct StripFocus: Equatable, Sendable {
    /// 选中的是什么（顶部一行用）。
    public var title: String
    public var inputs: Set<TotalMixChannel> = []
    public var playbacks: Set<TotalMixChannel> = []
    public var outputs: Set<TotalMixChannel> = []
    /// 链上的实物线缆（接线表 id），面板上加亮。
    public var links: Set<String> = []
    /// 通道条之间的线：来源条 → 输出条（都按立体声左声道），带电平。
    public var edges: [Edge] = []

    public struct Edge: Equatable, Sendable, Hashable {
        public var from: TotalMixChannel
        public var to: TotalMixChannel
        public var dB: Double
    }

    public static let maxEdges = 40
    /// 选中的接口超过这么多路时，默认只看在用的通道条（第 6.4.4 节）。
    public static let activeOnlyAbove = 8

    /// 过滤前链上的通道条数；只看在用的时大于 stripCount。
    public var total = 0
    /// 这次是否只留了在用的（有发送或有信号）。
    public var activeOnly = false
    public var stripCount: Int { inputs.count + playbacks.count + outputs.count }

    public var isEmpty: Bool { inputs.isEmpty && playbacks.isEmpty && outputs.isEmpty }
    public func contains(_ ch: TotalMixChannel) -> Bool { inputs.contains(ch) || playbacks.contains(ch) || outputs.contains(ch) }
}

extension AppModel {
    /// 立体声右声道并进左声道（通道条只有左声道那一条）。
    func stripChannel(_ ch: TotalMixChannel) -> TotalMixChannel {
        ch.number % 2 == 0 && tmState.isStereo(TotalMixChannel(ch.bus, ch.number - 1)) == true
            ? TotalMixChannel(ch.bus, ch.number - 1) : ch
    }

    /// 选中一个接口（channel 为 nil 时是整个接口的全部通道）后，沿路由和接线追出的整条链在通道条上的样子。
    /// activeOnly 为 nil 时自动：选中超过 `StripFocus.activeOnlyAbove` 路才只看在用的。
    public func stripFocus(connector c: PanelConnector, channel: Int? = nil, activeOnly: Bool? = nil) -> StripFocus {
        // 追链要沿全部路由走一遍（整个 MADI 口 64 路），每次重绘都算会让切页、点选变卡
        let key: [AnyHashable] = [c.id, channel, activeOnly, snapshotVersion, tmState.revision, meters.live, meters.active]
        if let cached = focusCache, cached.key == key { return cached.focus }
        let focus = computeStripFocus(connector: c, channel: channel, activeOnly: activeOnly)
        focusCache = (key, focus)
        return focus
    }

    private func computeStripFocus(connector c: PanelConnector, channel: Int?, activeOnly: Bool?) -> StripFocus {
        let topo = snapshot.topology
        var refs: [ChannelRef] = []
        for portID in c.ports {
            guard let port = topo.port(portID) else { continue }
            if let ch = channel ?? c.channel { refs.append(ChannelRef(portID, ch)) }
            else { refs += stride(from: 1, through: port.singleSpeedChannels, by: 1).map { ChannelRef(portID, $0) } }
        }
        let name = channel.map { "\(c.name) 第 \($0) 路" } ?? c.name
        var focus = StripFocus(title: name)
        var refOf: [TotalMixChannel: ChannelRef] = [:]
        let trace = SignalTrace(snapshot: snapshot)
        var chain: Set<ChannelRef> = []
        for ref in refs {
            chain.insert(ref)
            for step in (trace.upstream(to: ref) + trace.downstream(from: ref)).flatMap({ $0 }) {
                chain.insert(step.hop.from); chain.insert(step.hop.to)
                if case let .cable(f, t) = step.hop,
                   let l = topo.links.first(where: { $0.from == f.portID && $0.to == t.portID }) { focus.links.insert(l.id) }
            }
        }
        for ref in chain {
            guard let port = topo.port(ref.portID), port.deviceID == "xt" else { continue }
            if ref.portID == "xt.playback.in" {
                let tm = stripChannel(TotalMixChannel(.playback, ref.channel))
                focus.playbacks.insert(tm); refOf[tm] = refOf[tm] ?? ref
                continue
            }
            guard let tm = tmChannel(for: ref) else { continue }
            refOf[stripChannel(tm)] = refOf[stripChannel(tm)] ?? ref
            switch tm.bus {
            case .input: focus.inputs.insert(stripChannel(tm))
            case .output: focus.outputs.insert(stripChannel(tm))
            case .playback: focus.playbacks.insert(stripChannel(tm))
            }
        }
        // 来源条 → 输出条：读回的发送里两端都在链上的
        var edges: Set<StripFocus.Edge> = []
        for key in tmState.nodes.keys {
            guard let dB = tmState.gainDB(key) else { continue }
            let s = stripChannel(key.source), o = stripChannel(key.output)
            guard focus.inputs.contains(s) || focus.playbacks.contains(s), focus.outputs.contains(o) else { continue }
            edges.insert(.init(from: s, to: o, dB: dB))
        }
        focus.edges = edges.sorted { ($0.from, $0.to) < ($1.from, $1.to) }
        focus.total = focus.stripCount
        // 只看在用的：有发送或有信号的来源条、有发送进来的输出条；一条都没有时照旧显示全部
        if activeOnly ?? (refs.count > StripFocus.activeOnlyAbove) {
            let froms = Set(edges.map(\.from)), tos = Set(edges.map(\.to))
            func live(_ ch: TotalMixChannel) -> Bool { refOf[ch].map { hasSignal($0) == true } ?? false }
            var f = focus
            f.inputs = focus.inputs.filter { froms.contains($0) || live($0) }
            f.playbacks = focus.playbacks.filter { froms.contains($0) || live($0) }
            f.outputs = focus.outputs.filter { tos.contains($0) || live($0) }
            if f.stripCount > 0 { f.activeOnly = true; focus = f }
        }
        return focus
    }
}
