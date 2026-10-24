import Foundation

/// 控制域（H4）。各域的路由各自独立，不合并成一个矩阵。
public enum ControlDomain: String, Codable, Sendable, CaseIterable {
    case totalMix   // MADIface XT 所在 Mac 上的 TotalMix FX
    case twelveMic  // 12Mic 内部路由（JSON /routing，逐通道）
    case xtc        // OctaMic XTC Digital Routing（8 通道块）
    case manual     // 线缆、终端设备等只能人工处理的部分
}

public enum RouteKind: Codable, Sendable, Hashable {
    case mixSend(gainDB: Double?)  // TotalMix 混音发送，有电平
    case passthrough               // 数字直通（12Mic /routing）
    case blockAssign(size: Int)    // 8 通道块分配（XTC）
}

/// 一条设备内部路由：源通道 → 目标通道。
public struct Route: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var domain: ControlDomain
    public var source: ChannelRef
    public var destination: ChannelRef
    public var kind: RouteKind
    public var evidence: Evidence

    public init(id: String? = nil, domain: ControlDomain, source: ChannelRef, destination: ChannelRef,
                kind: RouteKind, evidence: Evidence) {
        self.id = id ?? "\(domain.rawValue):\(source)->\(destination)"
        self.domain = domain
        self.source = source
        self.destination = destination
        self.kind = kind
        self.evidence = evidence
    }
}

public enum RoutingGranularity: Codable, Sendable, Hashable {
    case channel           // 任意输入通道 → 任意输出通道
    case block(size: Int)  // 输入块 → 输出块，块内偏移保持
}

/// 设备“能做什么样的内部路由”，路径搜索据此生成候选边。
public struct RoutingCapability: Codable, Sendable {
    public var deviceID: String
    public var domain: ControlDomain
    public var inputPorts: [String]
    public var outputPorts: [String]
    public var granularity: RoutingGranularity
    public var kindIsMix: Bool        // true = TotalMix 混音发送；false = 直通/块分配
    public var access: Access
    public var grade: SourceGrade
    public var reference: String

    public init(deviceID: String, domain: ControlDomain, inputPorts: [String], outputPorts: [String],
                granularity: RoutingGranularity, kindIsMix: Bool, access: Access,
                grade: SourceGrade, reference: String) {
        self.deviceID = deviceID
        self.domain = domain
        self.inputPorts = inputPorts
        self.outputPorts = outputPorts
        self.granularity = granularity
        self.kindIsMix = kindIsMix
        self.access = access
        self.grade = grade
        self.reference = reference
    }
}

/// 用户要求的路由变更（路径搜索的输入，也是适配器 plan() 的输入）。
public struct RouteChange: Codable, Sendable, Hashable {
    public var domain: ControlDomain
    public var source: ChannelRef
    public var destination: ChannelRef
    public var kind: RouteKind

    public init(domain: ControlDomain, source: ChannelRef, destination: ChannelRef, kind: RouteKind) {
        self.domain = domain
        self.source = source
        self.destination = destination
        self.kind = kind
    }
}
