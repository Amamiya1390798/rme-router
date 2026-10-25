import Foundation
import RMECore
import RMEEngine
import RMEAdapters

/// 检查器的内容（阶段 B2）：选中一个通道，汇总它的全部信息。纯数据，便于测试。
public struct InspectorInfo: Equatable, Sendable {
    public struct Link: Equatable, Sendable {
        public var ref: ChannelRef
        public var via: String        // “TotalMix 发送 -6.9 dB”“12Mic 直通”“线缆”
        public var evidence: Evidence
    }

    public var ref: ChannelRef
    public var deviceName: String
    public var portName: String
    public var isInput: Bool
    /// TotalMix 里的通道与名字（仅 XT）。
    public var totalMix: String?
    public var totalMixEvidence: Evidence?
    public var preamp: PreampChannel?
    /// 直接的上一跳（送进这个通道的）。
    public var from: [Link]
    /// 直接的下一跳（这个通道送去的）。
    public var to: [Link]
    /// 沿路径走到底的终点、追到头的源头。
    public var endpoints: [ChannelRef]
    public var origins: [ChannelRef]
    /// 相关的体检结论（有问题或无法判断）。
    public var findings: [String]
    /// 涉及这个通道的待应用改动。
    public var pending: [String]
}

extension AppModel {
    /// 检查器当前看的通道：显式选中的优先，否则跟随信号流里选中的通道。
    public var inspectorTarget: ChannelRef? { inspected ?? traceTarget }

    public func inspect(_ ref: ChannelRef) {
        inspected = ref
        showInspector = true
    }

    public func inspectorInfo(_ ref: ChannelRef) -> InspectorInfo {
        let topo = snapshot.topology
        let port = topo.port(ref.portID)
        let deviceID = port?.deviceID ?? deviceID(of: ref)
        let routes = snapshot.allRoutes()

        func via(_ r: Route) -> String { "\(r.domain.displayName) \(r.kind.shortLabel)" }
        var from = routes.filter { $0.destination == ref }.map { InspectorInfo.Link(ref: $0.source, via: via($0), evidence: $0.evidence) }
        var to = routes.filter { $0.source == ref }.map { InspectorInfo.Link(ref: $0.destination, via: via($0), evidence: $0.evidence) }
        if port?.direction == .input {
            from += topo.links(into: ref.portID).map { .init(ref: ChannelRef($0.from, ref.channel), via: "线缆", evidence: .documented) }
        } else {
            to += topo.links(from: ref.portID).map { .init(ref: ChannelRef($0.to, ref.channel), via: "线缆", evidence: .documented) }
        }

        var tmText: String?, tmEvidence: Evidence?
        if deviceID == "xt", ref.portID != "xt.playback.in", let tm = tmChannel(for: ref) {
            tmText = tmState.names[tm].map { "\(tm)（\($0)）" } ?? tm.description
            tmEvidence = xtMap[tm]?.evidence
        } else if ref.portID == "xt.playback.in" {
            tmText = "playback \(ref.channel)（按定义）"
            tmEvidence = .confirmed
        }

        let trace = SignalTrace(snapshot: snapshot)
        let origins = Array(Set(trace.upstream(to: ref).compactMap { $0.first?.hop.from })).sorted()

        // 体检里主题提到这个端口或这个通道的结论。
        let findings = CheckupReport.build(snapshot).flatMap { r in
            (r.failures + r.undetermined).filter { $0.subject.contains(ref.portID) || $0.subject == ref.description }
                .map { f -> String in
                    switch f.verdict {
                    case let .fail(m): return "\(r.info.id) \(r.info.title)：\(m)"
                    case let .cannotDetermine(m): return "\(r.info.id) \(r.info.title)（无法判断）：\(m)"
                    case .pass: return ""
                    }
                }
        }

        var pendingText: [String] = []
        pendingText += pending.filter { $0.source == ref || $0.destination == ref }
            .map { "发送 \($0.source) → \($0.destination)：\(PendingChange.format($0.oldDB)) → \(PendingChange.format($0.newDB))" }
        pendingText += pendingPreamps.filter { $0.input == ref }
            .map { "\($0.field.label)：\($0.old?.text ?? "?") → \($0.new.text)" }
        pendingText += pendingRoutes.filter { $0.destination == ref || $0.new == ref || $0.old == ref }
            .map { "12Mic 路由 \($0.destination)：\(PendingRouteChange.text($0.old)) → \(PendingRouteChange.text($0.new))" }

        return InspectorInfo(
            ref: ref,
            deviceName: topo.device(deviceID)?.name ?? deviceID,
            portName: port?.name ?? ref.portID,
            isInput: port?.direction == .input,
            totalMix: tmText, totalMixEvidence: tmEvidence,
            preamp: snapshot.devices[deviceID]?.preamps.first { $0.input == ref },
            from: from.sorted { $0.ref < $1.ref }, to: to.sorted { $0.ref < $1.ref },
            endpoints: trace.destinations(of: ref).filter { $0 != ref },
            origins: origins.filter { $0 != ref },
            findings: findings, pending: pendingText)
    }
}
