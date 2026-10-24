import Foundation

/// 设计期的文档证据等级（第 4 节）。A2 是本次复核新增：RME 工作人员在官方论坛的答复。
public enum SourceGrade: String, Codable, Sendable, CaseIterable {
    case a = "A"    // 厂商资料或手册原文
    case a2 = "A2"  // RME 工作人员在官方论坛的答复
    case b = "B"    // 论坛用户、评测、经销商页面
    case c = "C"    // 推测
    case d = "D"    // 未知
}

/// 运行期一个值的可信状态（H7）。只读/可写是另一个维度，见 `Access`。
public enum Evidence: String, Codable, Sendable {
    case confirmed   // 本次从设备读回
    case documented  // 只有文档依据，没有读回
    case inferred    // 由其他已知值推出
    case unknown     // 读不到或没有依据
    case conflict    // 两个来源互相矛盾
}

/// 一个参数能否由本 App 修改。
public enum Access: String, Codable, Sendable {
    case readWrite
    case readOnly
    case manual      // 只能在设备面板或厂商软件上人工设置
    case unknown     // 未查到依据，按不可写处理
}

/// 值从哪里来：哪台设备、哪个接口、哪个地址、什么时候。
public struct FactSource: Codable, Sendable, Equatable {
    public var deviceID: String?
    public var interface: String      // "12mic-json" / "totalmix-osc" / "xtc-midi" / "manual" / "doc"
    public var reference: String?     // JSON 路径、OSC 地址、SysEx 参数号或文档 URL
    public var observedAt: Date?

    public init(deviceID: String? = nil, interface: String, reference: String? = nil, observedAt: Date? = nil) {
        self.deviceID = deviceID
        self.interface = interface
        self.reference = reference
        self.observedAt = observedAt
    }

    public static let manual = FactSource(interface: "manual")
}

/// 每个读到或推出的值都包一层 Fact。
public struct Fact<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public var value: Value?
    public var evidence: Evidence
    public var source: FactSource

    public init(_ value: Value?, _ evidence: Evidence, source: FactSource) {
        self.value = value
        self.evidence = evidence
        self.source = source
    }

    public static func unknown(_ source: FactSource = .manual) -> Fact<Value> {
        Fact(nil, .unknown, source: source)
    }

    public static func confirmed(_ value: Value, _ source: FactSource) -> Fact<Value> {
        Fact(value, .confirmed, source: source)
    }

    /// 只有 confirmed / documented / inferred 且有值时才算“已知”。
    public var knownValue: Value? {
        switch evidence {
        case .confirmed, .documented, .inferred: return value
        case .unknown, .conflict: return nil
        }
    }
}

/// 设计期登记的设备能力（每项带出处与等级）。
public struct Capability: Codable, Sendable, Equatable {
    public var name: String
    public var access: Access
    public var grade: SourceGrade
    public var reference: String

    public init(_ name: String, access: Access, grade: SourceGrade, reference: String) {
        self.name = name
        self.access = access
        self.grade = grade
        self.reference = reference
    }
}
