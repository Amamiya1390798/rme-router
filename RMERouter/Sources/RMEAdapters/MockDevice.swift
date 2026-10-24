import Foundation
import RMECore

/// 用快照夹具模拟一台设备。可注入离线、写入失败等情况（T6、T9）。
public actor MockDevice {
    public private(set) var state: DeviceSnapshot
    public var failOnParameters: Set<String> = []
    public private(set) var writeLog: [PlannedOperation] = []

    public init(_ state: DeviceSnapshot) { self.state = state }

    public func setReachable(_ r: Bool) { state.reachable = r }
    public func failWrites(to parameters: Set<String>) { failOnParameters = parameters }

    public func read() throws -> DeviceSnapshot {
        guard state.reachable else { throw AdapterError.unreachable }
        return state
    }

    /// 模拟写：参数形如 "route:<srcPort>#<ch>-><dstPort>#<ch>" 或 "setting:<key>"。
    public func write(_ op: PlannedOperation) throws {
        guard state.reachable else { throw AdapterError.unreachable }
        if failOnParameters.contains(op.parameter) { throw AdapterError.badResponse("injected failure") }
        writeLog.append(op)
        if op.parameter.hasPrefix("setting:") {
            let key = String(op.parameter.dropFirst("setting:".count))
            state.settings[key] = .confirmed(op.newValue, FactSource(deviceID: state.deviceID, interface: "mock"))
        }
    }
}

/// 执行器：逐步写入、回读；中途失败时回滚已执行步骤（T9）。
public enum PlanExecutor {
    public struct Outcome: Equatable, Sendable {
        public var applied: [UUID]
        public var rolledBack: [UUID]
        public var failed: UUID?
        public var warnings: [String]
    }

    public static func run(_ ops: [PlannedOperation], on device: MockDevice,
                           confirmation: UserConfirmation) async -> Outcome {
        var applied: [PlannedOperation] = []
        for op in ops {
            guard confirmation.covers(op), op.access == .readWrite else {
                return Outcome(applied: applied.map(\.id), rolledBack: [], failed: op.id,
                               warnings: ["\(op.parameter) 未确认或不可远程写入，已停止"])
            }
            do {
                try await device.write(op)
                applied.append(op)
            } catch {
                var rolled: [UUID] = [], warnings: [String] = []
                for done in applied.reversed() {
                    guard let old = done.oldValue else {
                        warnings.append("\(done.parameter) 没有旧值，无法回滚，请人工检查")
                        continue
                    }
                    let undo = PlannedOperation(deviceID: done.deviceID, parameter: done.parameter,
                                                oldValue: done.newValue, newValue: old, access: .readWrite)
                    if (try? await device.write(undo)) != nil { rolled.append(done.id) }
                    else { warnings.append("\(done.parameter) 回滚失败，请人工检查") }
                }
                return Outcome(applied: applied.map(\.id), rolledBack: rolled, failed: op.id, warnings: warnings)
            }
        }
        return Outcome(applied: applied.map(\.id), rolledBack: [], failed: nil, warnings: [])
    }
}
