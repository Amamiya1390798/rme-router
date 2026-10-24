import Foundation
import RMECore

/// 一次计划中的单个硬件操作。
public struct PlannedOperation: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var deviceID: String
    public var parameter: String        // 例如 JSON 路径 "routing/madi_optical/9"
    public var oldValue: String?        // 回滚用
    public var newValue: String
    public var access: Access

    public init(id: UUID = UUID(), deviceID: String, parameter: String, oldValue: String?, newValue: String, access: Access) {
        self.id = id
        self.deviceID = deviceID
        self.parameter = parameter
        self.oldValue = oldValue
        self.newValue = newValue
        self.access = access
    }
}

public enum VerificationResult: Equatable, Sendable {
    case matches
    case differs(readBack: String)
    case unreadable                     // 读不回 → 计划里标“未验证”
}

/// H8 的类型级保证：apply() 只接受 UserConfirmation，而它只能由 ConfirmationGate 在用户
/// 看过预览后签发。适配器和引擎都无法自己伪造确认。
public struct UserConfirmation: Sendable {
    public let operationIDs: Set<UUID>
    public let confirmedAt: Date
    fileprivate init(operationIDs: Set<UUID>) {
        self.operationIDs = operationIDs
        self.confirmedAt = Date()
    }
    public func covers(_ op: PlannedOperation) -> Bool { operationIDs.contains(op.id) }
}

/// 只应由 UI 层（预览对话框的“确认”按钮）调用。
@MainActor
public enum ConfirmationGate {
    public static func userConfirmed(_ ops: [PlannedOperation]) -> UserConfirmation {
        UserConfirmation(operationIDs: Set(ops.map(\.id)))
    }
}

public enum AdapterError: Error, Equatable {
    case notConfirmed
    case notWritable(String)            // access 不是 readWrite
    case unreachable
    case protocolUnknown(String)        // 协议细节未查到（证据等级 D）
    case badResponse(String)
}

/// 设备适配器：统一向引擎暴露。所有方法默认只读；apply 需要确认凭证。
public protocol DeviceAdapter: Sendable {
    var deviceID: String { get }
    var domain: ControlDomain { get }
    /// 每项能力带证据等级与出处。
    var capabilities: [Capability] { get }

    /// 探测控制链路是否在线（R10），不改任何东西。
    func probe() async -> ControlPath
    /// 读取完整只读快照。
    func snapshot() async throws -> DeviceSnapshot
    /// 只计划，不执行：把路由变更翻译成本设备的参数写入。
    func plan(_ change: RouteChange, current: DeviceSnapshot) -> [PlannedOperation]
    /// 仅在用户确认后执行；实现必须先检查 confirmation.covers(op) 与 op.access。
    func apply(_ op: PlannedOperation, confirmation: UserConfirmation) async throws
    /// 写后回读。
    func verify(_ op: PlannedOperation) async throws -> VerificationResult
}

extension DeviceAdapter {
    /// 各适配器 apply() 开头调用。
    public func precheck(_ op: PlannedOperation, _ confirmation: UserConfirmation) throws {
        guard confirmation.covers(op) else { throw AdapterError.notConfirmed }
        guard op.access == .readWrite else { throw AdapterError.notWritable(op.parameter) }
    }
}
