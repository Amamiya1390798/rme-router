import Foundation
import RMECore

/// 代价权重（第 9 节初值；用第 11 节场景调整）。
public struct CostWeights: Sendable {
    public var overrideExisting = 100
    public var manualStep = 10
    public var domainSwitch = 3
    public var hop = 1
    public var wastedBlockChannel = 1
    public init() {}
}

/// 图中的一条边。
public enum EdgeKind: Equatable, Sendable {
    case cable(Link)
    case existingRoute(Route)
    case newRoute(RouteChange, access: Access, overrides: [Route])
}

public struct PathEdge: Equatable, Sendable {
    public var from: ChannelRef
    public var to: ChannelRef
    public var kind: EdgeKind
    public var cost: Int
    public var formatEvidence: Evidence   // 线缆边：两端格式是否已知
}

/// 计划中的一步（第 9 节第 5 步的字段）。
public struct PlanStep: Equatable, Sendable {
    public enum Location: Equatable, Sendable { case cable, device(String, ControlDomain) }
    public var location: Location
    public var summary: String
    public var change: RouteChange?
    public var overrides: [Route]          // 旧值，供回滚
    public var remoteWritable: Bool
    public var status: Evidence            // 这一段目前的可信度
    public var verification: String
}

public struct RoutePlan: Equatable, Sendable {
    public var edges: [PathEdge]
    public var steps: [PlanStep]           // 已按“下游到上游”排好执行顺序
    public var totalCost: Int
    public var overrides: [Route] { steps.flatMap(\.overrides) }
    public var manualSteps: [PlanStep] { steps.filter { $0.change != nil && !$0.remoteWritable } }
}

public enum PathResult: Equatable, Sendable {
    case found(RoutePlan)
    /// 无解时说明卡在哪些约束（去重后排序）。
    case infeasible(reasons: [String])
}

public struct PathFinder {
    public var snapshot: SystemSnapshot
    public var weights: CostWeights

    public init(snapshot: SystemSnapshot, weights: CostWeights = CostWeights()) {
        self.snapshot = snapshot
        self.weights = weights
    }

    // MARK: 搜索（Dijkstra，状态 = 通道 + 上一个控制域）

    private struct State: Hashable { var node: ChannelRef; var domain: ControlDomain? }

    public func find(from source: ChannelRef, to target: ChannelRef) -> PathResult {
        var dist: [State: Int] = [:]
        var prev: [State: (State, PathEdge)] = [:]
        var blocked = Set<String>()
        var heap = MinHeap<(Int, State)>(by: { $0.0 < $1.0 })

        let start = State(node: source, domain: nil)
        dist[start] = 0
        heap.push((0, start))

        while let (d, st) = heap.pop() {
            if d > dist[st, default: .max] { continue }
            if st.node == target { return .found(buildPlan(endingAt: st, prev: prev, cost: d)) }
            for edge in edges(from: st.node, blocked: &blocked) {
                var cost = edge.cost
                var domain = st.domain
                if let edgeDomain = Self.domain(of: edge) {
                    if let last = st.domain, last != edgeDomain { cost += weights.domainSwitch }
                    domain = edgeDomain
                }
                let next = State(node: edge.to, domain: domain)
                let nd = d + cost
                if nd < dist[next, default: .max] {
                    dist[next] = nd
                    prev[next] = (st, edge)
                    heap.push((nd, next))
                }
            }
        }
        return .infeasible(reasons: blocked.isEmpty ? ["连接表或路由能力中不存在从 \(source) 到 \(target) 的路径"] : blocked.sorted())
    }

    private static func domain(of e: PathEdge) -> ControlDomain? {
        switch e.kind {
        case .cable: return nil
        case let .existingRoute(r): return r.domain
        case let .newRoute(c, _, _): return c.domain
        }
    }

    // MARK: 边的生成（约束过滤在这里）

    func edges(from node: ChannelRef, blocked: inout Set<String>) -> [PathEdge] {
        guard let port = snapshot.topology.port(node.portID) else { return [] }
        return port.direction == .output ? cableEdges(from: node, port: port, blocked: &blocked)
                                         : internalEdges(from: node, port: port)
    }

    private func usableChannels(_ port: RMECore.Port) -> Int {
        snapshot.format(of: port.id)?.knownValue?.audioChannels(on: port.type) ?? port.singleSpeedChannels
    }

    private func cableEdges(from node: ChannelRef, port: RMECore.Port, blocked: inout Set<String>) -> [PathEdge] {
        snapshot.topology.links(from: port.id).compactMap { link in
            guard let to = snapshot.topology.port(link.to), port.type.canConnect(to: to.type) else {
                blocked.insert("\(link.from)→\(link.to)：接口类型不符")
                return nil
            }
            if node.channel > usableChannels(port) {
                blocked.insert("\(port.id) 在当前采样率下只有 \(usableChannels(port)) 路，通道 \(node.channel) 不存在")
                return nil
            }
            let tx = snapshot.format(of: port.id)?.knownValue
            let terminal = snapshot.terminals.first { $0.deviceID == to.deviceID }
            var evidence = Evidence.confirmed
            if let tx {
                // 终端没有可读的接收格式，用发送格式自比，只检查终端约束。
                let rx = terminal == nil ? snapshot.format(of: to.id)?.knownValue : tx
                if let rx {
                    let errors = FormatCheck.compare(sender: tx, receiver: rx,
                                                     terminalRates: terminal?.allowedSampleRates ?? [])
                        .filter(\.isError)
                    if !errors.isEmpty {
                        let name = snapshot.topology.device(to.deviceID)?.name ?? to.deviceID
                        blocked.insert("\(port.id)→\(to.id)（\(name)）：" + errors.map(\.description).joined(separator: "；"))
                        return nil
                    }
                } else { evidence = .unknown }
            } else { evidence = .unknown }
            return PathEdge(from: node, to: ChannelRef(to.id, node.channel), kind: .cable(link),
                            cost: 0, formatEvidence: evidence)
        }
    }

    private func internalEdges(from node: ChannelRef, port: RMECore.Port) -> [PathEdge] {
        let existing = snapshot.allRoutes()
        var out: [PathEdge] = existing.filter { $0.source == node }.map {
            PathEdge(from: node, to: $0.destination, kind: .existingRoute($0), cost: 0, formatEvidence: $0.evidence)
        }
        for cap in snapshot.capabilities where cap.inputPorts.contains(port.id) {
            for outID in cap.outputPorts {
                guard let outPort = snapshot.topology.port(outID) else { continue }
                let n = usableChannels(outPort)
                let targets: [Int]
                let kind: RouteKind
                var extra = 0
                switch cap.granularity {
                case .channel:
                    targets = Array(1...max(n, 1))
                    kind = cap.kindIsMix ? .mixSend(gainDB: 0) : .passthrough
                case let .block(size):
                    targets = stride(from: node.offsetInBlock + 1, through: n, by: size).map { $0 }
                    kind = .blockAssign(size: size)
                    extra = (size - 1) * weights.wastedBlockChannel
                }
                for ch in targets {
                    let dest = ChannelRef(outID, ch)
                    if out.contains(where: { $0.to == dest }) { continue }   // 已有同一路由
                    let overrides = occupants(of: dest, by: node, granularity: cap.granularity, in: existing)
                    var cost = weights.hop + extra
                    if cap.access != .readWrite { cost += weights.manualStep }
                    if !overrides.isEmpty { cost += weights.overrideExisting }
                    let change = RouteChange(domain: cap.domain, source: node, destination: dest, kind: kind)
                    out.append(PathEdge(from: node, to: dest, kind: .newRoute(change, access: cap.access, overrides: overrides),
                                        cost: cost, formatEvidence: .documented))
                }
            }
        }
        return out
    }

    /// 目标通道（或目标块）上已有、且来源不同的路由——写入会覆盖它们。
    private func occupants(of dest: ChannelRef, by source: ChannelRef, granularity: RoutingGranularity,
                           in routes: [Route]) -> [Route] {
        switch granularity {
        case .channel:
            return routes.filter { $0.destination == dest && $0.source != source }
        case .block:
            return routes.filter {
                $0.destination.portID == dest.portID && $0.destination.block == dest.block
                    && !($0.source.portID == source.portID && $0.source.block == source.block)
            }
        }
    }

    // MARK: 计划

    private func buildPlan(endingAt end: State, prev: [State: (State, PathEdge)], cost: Int) -> RoutePlan {
        var edges: [PathEdge] = []
        var cur = end
        while let (p, e) = prev[cur] { edges.append(e); cur = p }
        edges.reverse()

        var steps: [PlanStep] = []
        for e in edges {
            switch e.kind {
            case let .cable(link):
                steps.append(PlanStep(location: .cable, summary: "线缆 \(link.from) → \(link.to)，通道 \(e.from.channel)",
                                      change: nil, overrides: [], remoteWritable: false, status: e.formatEvidence,
                                      verification: e.formatEvidence == .unknown ? "格式未知，需读取两端设置" : "两端格式一致"))
            case let .existingRoute(r):
                steps.append(PlanStep(location: .device(deviceID(of: r.source), r.domain),
                                      summary: "已有路由 \(r.source) → \(r.destination)", change: nil, overrides: [],
                                      remoteWritable: false, status: r.evidence, verification: "回读确认仍然存在"))
            case let .newRoute(c, access, overrides):
                steps.append(PlanStep(location: .device(deviceID(of: c.source), c.domain),
                                      summary: "新建 \(c.source) → \(c.destination)", change: c, overrides: overrides,
                                      remoteWritable: access == .readWrite, status: .inferred,
                                      verification: access == .readWrite ? "写后回读比对" : "人工设置后在设备上核对"))
            }
        }
        // 执行顺序：先读与校验类步骤，再把需要改动的步骤从下游到上游排列（第 9 节第 6 步）。
        let readOnly = steps.filter { $0.change == nil }
        let changes = Array(steps.filter { $0.change != nil }.reversed())
        return RoutePlan(edges: edges, steps: readOnly + changes, totalCost: cost)
    }

    private func deviceID(of ch: ChannelRef) -> String {
        snapshot.topology.port(ch.portID)?.deviceID ?? "?"
    }
}

// MARK: - 最小堆

struct MinHeap<T> {
    private var items: [T] = []
    private let less: (T, T) -> Bool
    init(by less: @escaping (T, T) -> Bool) { self.less = less }

    mutating func push(_ x: T) {
        items.append(x)
        var i = items.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            if !less(items[i], items[p]) { break }
            items.swapAt(i, p); i = p
        }
    }

    mutating func pop() -> T? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var i = 0
        while true {
            let l = 2 * i + 1, r = l + 1
            var m = i
            if l < items.count && less(items[l], items[m]) { m = l }
            if r < items.count && less(items[r], items[m]) { m = r }
            if m == i { break }
            items.swapAt(i, m); i = m
        }
        return top
    }
}
