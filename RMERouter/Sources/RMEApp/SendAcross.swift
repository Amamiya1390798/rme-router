import Foundation
import RMECore
import RMEEngine

/// 跨设备“送一路声音”的计划（文档第 7.5 节）：按信号顺序列出每一段怎么处理。
public struct SendPlan: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// 自动：TotalMix 新建发送（安静起步）
        case totalMixSend(source: ChannelRef, destination: ChannelRef, dB: Double)
        /// 自动：12Mic 路由
        case twelveMicRoute(source: ChannelRef, destination: ChannelRef)
        /// 沿用已有路由
        case existing(Route)
        /// 线缆（只显示）
        case cable(from: ChannelRef, to: ChannelRef)
        /// 人工：设备面板上设置（XTC 等）
        case manual(String)
    }

    public struct Step: Equatable, Sendable, Identifiable {
        public var id: Int
        public var action: Action
        /// 这一步会覆盖的已有路由。
        public var overrides: [Route]
    }

    public var source: ChannelRef
    public var destination: ChannelRef
    public var steps: [Step]

    public var overrides: [Route] { steps.flatMap(\.overrides) }
    public var manualSteps: [String] {
        steps.compactMap { if case let .manual(t) = $0.action { return t } else { return nil } }
    }
    public var autoCount: Int {
        steps.filter {
            switch $0.action { case .totalMixSend, .twelveMicRoute: return true; default: return false }
        }.count
    }
}

public enum SendPlanResult: Equatable, Sendable {
    case found([SendPlan])
    case infeasible(reasons: [String])
}

/// 需要在设备上手动完成的一步（XTC 面板等）。
public struct ManualTask: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var text: String
}

public enum SendAcross {
    /// 新建 TotalMix 发送的起始电平：安静起步（第 7.1、7.5 节）。
    public static let newSendDB = -30.0

    /// 在快照上为 source → destination 搜路径并翻译成计划。pair 为 true 时左右各算一次（s, s+1 → d, d+1）。
    public static func plan(_ snapshot: SystemSnapshot, from source: ChannelRef, to destination: ChannelRef,
                            pair: Bool = false) -> SendPlanResult {
        let pairs = pair ? [(source, destination), (ChannelRef(source.portID, source.channel + 1),
                                                    ChannelRef(destination.portID, destination.channel + 1))]
                         : [(source, destination)]
        var plans: [SendPlan] = []
        var reasons: [String] = []
        for (s, d) in pairs {
            switch PathFinder(snapshot: snapshot).find(from: s, to: d) {
            case let .found(route): plans.append(translate(route, from: s, to: d, in: snapshot))
            case let .infeasible(r): reasons += r.map { "\(s) → \(d)：\($0)" }
            }
        }
        return reasons.isEmpty ? .found(plans) : .infeasible(reasons: reasons)
    }

    static func translate(_ route: RoutePlan, from source: ChannelRef, to destination: ChannelRef,
                          in snapshot: SystemSnapshot) -> SendPlan {
        var steps: [SendPlan.Step] = []
        for (i, edge) in route.edges.enumerated() {
            switch edge.kind {
            case .cable:
                steps.append(.init(id: i, action: .cable(from: edge.from, to: edge.to), overrides: []))
            case let .existingRoute(r):
                steps.append(.init(id: i, action: .existing(r), overrides: []))
            case let .newRoute(change, access, overrides):
                let action: SendPlan.Action
                switch (change.domain, access) {
                case (.totalMix, .readWrite):
                    action = .totalMixSend(source: change.source, destination: change.destination, dB: newSendDB)
                case (.twelveMic, .readWrite):
                    action = .twelveMicRoute(source: change.source, destination: change.destination)
                default:
                    action = .manual(manualText(change, in: snapshot))
                }
                steps.append(.init(id: i, action: action, overrides: overrides))
            }
        }
        return SendPlan(source: source, destination: destination, steps: steps)
    }

    /// 人工步骤的说明：设备名、面板菜单、目标块与来源块。
    static func manualText(_ c: RouteChange, in snapshot: SystemSnapshot) -> String {
        let device = snapshot.topology.port(c.destination.portID).flatMap { snapshot.topology.device($0.deviceID)?.name }
            ?? c.destination.portID
        let outName = snapshot.topology.port(c.destination.portID)?.name ?? c.destination.portID
        let inName = snapshot.topology.port(c.source.portID)?.name ?? c.source.portID
        if case let .blockAssign(size) = c.kind {
            let outFirst = c.destination.block * size + 1, inFirst = c.source.block * size + 1
            return "在 \(device) 面板 Digital Routing 菜单：把“\(outName)”通道 \(outFirst)–\(outFirst + size - 1) 的来源设为“\(inName)”通道 \(inFirst)–\(inFirst + size - 1)"
        }
        return "在 \(device) 上手动设置：\(c.source) → \(c.destination)"
    }
}

extension AppModel {
    /// 把计划里的自动步骤加入待应用（快速方式由界面再调 commitIfQuick）；人工步骤进“需人工完成”清单。
    /// 返回出错说明（有一条就整体不加入）。
    @discardableResult
    public func stageSendPlan(_ plans: [SendPlan]) -> [String] {
        let savedPending = pending, savedRoutes = pendingRoutes
        var errors: [String] = []
        for plan in plans {
            for step in plan.steps {
                switch step.action {
                case let .totalMixSend(s, d, dB):
                    if let e = stageGain(source: s, destination: d, dB: dB) { errors.append("\(s) → \(d)：\(e.text)") }
                case let .twelveMicRoute(s, d):
                    if let e = stageTwelveMicRoute(destination: d, source: s) { errors.append("\(s) → \(d)：\(e.text)") }
                default:
                    break
                }
            }
        }
        if !errors.isEmpty {
            pending = savedPending
            pendingRoutes = savedRoutes
            return errors
        }
        for text in plans.flatMap(\.manualSteps) where !manualTasks.contains(where: { $0.text == text }) {
            manualTasks.append(ManualTask(id: UUID(), text: text))
        }
        return []
    }

    public func completeManualTask(_ id: UUID) { manualTasks.removeAll { $0.id == id } }

    /// “送一路声音”可选的来源端口：有路由能力的输入口。
    public var sendSourcePorts: [RMECore.Port] {
        let ids = Set(snapshot.capabilities.flatMap(\.inputPorts))
        return snapshot.topology.devices.flatMap(\.ports).filter { ids.contains($0.id) }
    }

    /// 可选的去处端口：有路由能力的输出口，加上终端设备（P16）的输入口。
    public var sendDestinationPorts: [RMECore.Port] {
        let outs = Set(snapshot.capabilities.flatMap(\.outputPorts))
        let terminals = Set(snapshot.terminals.map(\.deviceID))
        return snapshot.topology.devices.flatMap(\.ports).filter {
            outs.contains($0.id) || (terminals.contains($0.deviceID) && $0.direction == .input)
        }
    }
}
