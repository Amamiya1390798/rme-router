import Foundation
import RMECore

/// “输出”视图的一张卡：一个在用的输出通道（或立体声对）以及送进来的声音。
public struct OutputCard: Identifiable, Equatable, Sendable {
    public struct Source: Equatable, Sendable {
        public var refs: [ChannelRef]      // 单声道 1 个；立体声对按左右
        public var kind: RouteKind
        public var evidence: Evidence

        public var label: String { Notation.format(refs).joined(separator: ", ") }
    }

    public var port: RMECore.Port
    public var channels: [Int]
    public var sources: [Source]
    /// 被隐藏的电脑回放来源数（showPlayback 为 false 时）。
    public var hiddenPlayback = 0

    public var id: String { "\(port.id):\(channels.map(String.init).joined(separator: "-"))" }
    public var address: String { Notation.format(channels.map { ChannelRef(port.id, $0) }).joined() }
    /// 卡片整体状态：取最弱的一条。
    public var evidence: Evidence { sources.map(\.evidence).min(by: { $0.strength < $1.strength }) ?? .unknown }
}

public struct DeviceOutputs: Identifiable, Sendable {
    public var device: Device
    public var cards: [OutputCard]
    public var id: String { device.id }
}

public enum OutputCards {
    /// 只列有路由送入的输出（设计原则 1：只显示在用的东西）。设备顺序按拓扑；卡按端口、通道排。
    /// 立体声合并：通道 c（奇数）与 c+1 的每条来源都能一一对应（同源，或来源也是相邻一对），且类型相同。
    /// showPlayback 为 false 时隐藏电脑回放来源（TotalMix 默认每路回放直送同号输出，会淹没设备间路由）：
    /// 只有回放来源的卡不出现，其余卡记下隐藏了几路。
    public static func build(_ snapshot: SystemSnapshot, showPlayback: Bool = true) -> [DeviceOutputs] {
        let all = Dictionary(grouping: snapshot.allRoutes(), by: \.destination)
        let byDest = showPlayback ? all : all.mapValues { $0.filter { !isPlayback($0.source) } }.filter { !$0.value.isEmpty }
        func hidden(_ chans: [Int], _ portID: String) -> Int {
            showPlayback ? 0 : chans.reduce(0) { n, c in n + (all[ChannelRef(portID, c)] ?? []).filter { isPlayback($0.source) }.count }
                / max(chans.count, 1)
        }
        return snapshot.topology.devices.compactMap { device in
            var cards: [OutputCard] = []
            for port in device.ports where port.direction == .output {
                let used = byDest.keys.filter { $0.portID == port.id }.map(\.channel).sorted()
                var i = 0
                while i < used.count {
                    let c = used[i]
                    let left = byDest[ChannelRef(port.id, c)] ?? []
                    if c % 2 == 1, i + 1 < used.count, used[i + 1] == c + 1,
                       let pair = pairSources(left, byDest[ChannelRef(port.id, c + 1)] ?? []) {
                        cards.append(OutputCard(port: port, channels: [c, c + 1], sources: pair,
                                                hiddenPlayback: hidden([c, c + 1], port.id)))
                        i += 2
                    } else {
                        cards.append(OutputCard(port: port, channels: [c], sources: left.map {
                            .init(refs: [$0.source], kind: $0.kind, evidence: $0.evidence)
                        }.sorted(by: sourceOrder), hiddenPlayback: hidden([c], port.id)))
                        i += 1
                    }
                }
            }
            return cards.isEmpty ? nil : DeviceOutputs(device: device, cards: cards)
        }
    }

    /// 电脑回放（TotalMix 的 playback 通道）。
    public static func isPlayback(_ ref: ChannelRef) -> Bool { ref.portID.hasSuffix(".playback.in") }

    static func pairSources(_ left: [Route], _ right: [Route]) -> [OutputCard.Source]? {
        // 只合并混音发送：12Mic 直通是“每个输出通道一个来源”，合并后改来源就分不清对哪个通道（第 7.3 节）。
        let allMix = (left + right).allSatisfy { if case .mixSend = $0.kind { return true } else { return false } }
        guard allMix, left.count == right.count else { return nil }
        var remaining = right
        var out: [OutputCard.Source] = []
        for l in left {
            let partner = ChannelRef(l.source.portID, l.source.channel + 1)
            guard let j = remaining.firstIndex(where: { ($0.source == partner || $0.source == l.source) && $0.kind == l.kind })
            else { return nil }
            let r = remaining.remove(at: j)
            let weaker = l.evidence.strength <= r.evidence.strength ? l.evidence : r.evidence
            out.append(.init(refs: r.source == l.source ? [l.source] : [l.source, r.source], kind: l.kind, evidence: weaker))
        }
        return out.sorted(by: sourceOrder)
    }

    /// 电平高的在前，其次按地址。
    static func sourceOrder(_ a: OutputCard.Source, _ b: OutputCard.Source) -> Bool {
        let ga = a.kind.gainDB ?? 0, gb = b.kind.gainDB ?? 0
        return ga != gb ? ga > gb : a.refs[0] < b.refs[0]
    }
}

public extension RouteKind {
    var gainDB: Double? {
        if case let .mixSend(g) = self { return g }
        return nil
    }

    /// 界面上的简短说明。
    var shortLabel: String {
        switch self {
        case let .mixSend(g): return g.map { String(format: "%.1f dB", $0) } ?? "发送"
        case .passthrough: return "直通"
        case let .blockAssign(n): return "\(n) 路块"
        }
    }
}

public extension Evidence {
    /// 可信度高低，用于“取最弱”。
    var strength: Int {
        switch self {
        case .conflict: return 0
        case .unknown: return 1
        case .inferred: return 2
        case .documented: return 3
        case .confirmed: return 4
        }
    }
}
