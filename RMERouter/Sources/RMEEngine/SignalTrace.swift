import Foundation
import RMECore

/// 路径中的一步：一跳加上这一跳的可信度（界面状态点用）。
public struct TraceStep: Equatable, Sendable {
    public var hop: Hop
    public var evidence: Evidence

    public init(hop: Hop, evidence: Evidence) {
        self.hop = hop
        self.evidence = evidence
    }
}

/// 信号流追踪：沿已有路由（→）与线缆（⇒）走，只读，不搜索新路由（新路由见 PathFinder）。
/// 线缆按连接表登记为 documented；路由沿用快照里的 evidence。
public struct SignalTrace {
    public let snapshot: SystemSnapshot
    private let bySource: [ChannelRef: [Route]]
    private let byDestination: [ChannelRef: [Route]]

    public init(snapshot: SystemSnapshot) {
        self.snapshot = snapshot
        let routes = snapshot.allRoutes()
        bySource = Dictionary(grouping: routes, by: \.source)
        byDestination = Dictionary(grouping: routes, by: \.destination)
    }

    /// 从 start 往下游的全部路径；每条走到没有去向、成环或 maxHops 为止。
    public func downstream(from start: ChannelRef, maxHops: Int = 12) -> [[TraceStep]] {
        walk(start, maxHops: maxHops, next: nextSteps)
    }

    /// 到 end 的全部上游路径（已按信号方向排好，从源头到 end）。
    public func upstream(to end: ChannelRef, maxHops: Int = 12) -> [[TraceStep]] {
        walk(end, maxHops: maxHops, next: previousSteps).map { $0.reversed() }
    }

    /// 某个通道在快照里的所有终点（下游路径的最后一个通道），去重排序。
    public func destinations(of start: ChannelRef) -> [ChannelRef] {
        Array(Set(downstream(from: start).compactMap { $0.last?.hop.to })).sorted()
    }

    // MARK: 内部

    private func walk(_ start: ChannelRef, maxHops: Int,
                      next: (ChannelRef) -> [(TraceStep, ChannelRef)]) -> [[TraceStep]] {
        var paths: [[TraceStep]] = []
        func dfs(_ node: ChannelRef, _ path: [TraceStep], _ seen: Set<ChannelRef>) {
            let candidates = path.count < maxHops ? next(node).filter { !seen.contains($0.1) } : []
            if candidates.isEmpty {
                if !path.isEmpty { paths.append(path) }
                return
            }
            for (step, to) in candidates { dfs(to, path + [step], seen.union([to])) }
        }
        dfs(start, [], [start])
        return paths
    }

    private func nextSteps(_ node: ChannelRef) -> [(TraceStep, ChannelRef)] {
        var out = (bySource[node] ?? []).sorted { $0.destination < $1.destination }.map { r in
            (TraceStep(hop: .route(from: r.source, to: r.destination, domain: r.domain, kind: r.kind), evidence: r.evidence),
             r.destination)
        }
        if snapshot.topology.port(node.portID)?.direction == .output {
            for link in snapshot.topology.links(from: node.portID) {
                let to = ChannelRef(link.to, node.channel)
                out.append((TraceStep(hop: .cable(from: node, to: to), evidence: .documented), to))
            }
        }
        return out
    }

    private func previousSteps(_ node: ChannelRef) -> [(TraceStep, ChannelRef)] {
        var out = (byDestination[node] ?? []).sorted { $0.source < $1.source }.map { r in
            (TraceStep(hop: .route(from: r.source, to: r.destination, domain: r.domain, kind: r.kind), evidence: r.evidence),
             r.source)
        }
        if snapshot.topology.port(node.portID)?.direction == .input {
            for link in snapshot.topology.links(into: node.portID) {
                let from = ChannelRef(link.from, node.channel)
                out.append((TraceStep(hop: .cable(from: from, to: node), evidence: .documented), from))
            }
        }
        return out
    }
}
