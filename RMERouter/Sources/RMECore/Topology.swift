import Foundation

public enum PortType: String, Codable, Sendable {
    case madiOptical, madiCoaxial, adat, aes, analog, ultranet, usb, wordClock, ethernet
    /// 通用主卡（文档第 6.4.6 节）：不知道具体是哪种接口，和任何类型都能连。
    case mixed

    /// 哪些端口类型之间可以直接连线。MADI 光纤与 ADAT TOSLINK 都是光，但不能互通（问题 8）。
    public func canConnect(to other: PortType) -> Bool { self == other || self == .mixed || other == .mixed }
}

/// 物理连接器。SC 与 LC 都是 MADI 多模光纤，只是接头不同，需转接跳线，不算类型错误。
public enum Connector: String, Codable, Sendable {
    case sc, lc, sfp, bnc, toslink, rj45, xlr, trs, combo, dsub, usbB, usbC
    /// 通用主卡：接头未知
    case unspecified
}

public enum Direction: String, Codable, Sendable { case input, output }

public enum DeviceModel: String, Codable, Sendable {
    case madifaceXT, twelveMic, octamicXTC, p16i, p16m
    /// 通用 TotalMix FX 设备（没有型号档案，文档第 6.4.6 节）
    case genericTotalMix
}

public struct Port: Codable, Sendable, Hashable, Identifiable {
    public var id: String           // 全局唯一，例如 "xt.madi1.in"
    public var deviceID: String
    public var name: String         // 设备上的叫法，例如 "MADI 1 (optical)"
    public var type: PortType
    public var direction: Direction
    public var connector: Connector
    public var singleSpeedChannels: Int

    public init(id: String, deviceID: String, name: String, type: PortType, direction: Direction,
                connector: Connector, singleSpeedChannels: Int) {
        self.id = id
        self.deviceID = deviceID
        self.name = name
        self.type = type
        self.direction = direction
        self.connector = connector
        self.singleSpeedChannels = singleSpeedChannels
    }
}

/// 某端口上的某个通道，1 起编号。
public struct ChannelRef: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public var portID: String
    public var channel: Int

    public init(_ portID: String, _ channel: Int) {
        self.portID = portID
        self.channel = channel
    }

    /// 8 通道块编号，0 起。
    public var block: Int { (channel - 1) / 8 }
    public var offsetInBlock: Int { (channel - 1) % 8 }

    public static func < (l: ChannelRef, r: ChannelRef) -> Bool {
        l.portID == r.portID ? l.channel < r.channel : l.portID < r.portID
    }

    public var description: String { "\(portID):\(channel)" }
}

public struct Device: Codable, Sendable, Identifiable {
    public var id: String
    public var model: DeviceModel
    public var name: String
    public var ports: [Port]

    public init(id: String, model: DeviceModel, name: String, ports: [Port]) {
        self.id = id
        self.model = model
        self.name = name
        self.ports = ports
    }
}

/// 一根线，单向：输出端口 → 输入端口。MADI 光纤收发是两条 Link。
public struct Link: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var from: String
    public var to: String

    public init(id: String, from: String, to: String) {
        self.id = id
        self.from = from
        self.to = to
    }
}

public enum LinkIssue: Equatable, Sendable, CustomStringConvertible {
    case unknownPort(String)
    case wrongDirection(String)
    case mediumMismatch(PortType, PortType)          // 错误：例如 ADAT 接到 MADI 光口
    case connectorNeedsAdapter(Connector, Connector) // 警告：例如 SC ↔ LC
    case missingReturnPath                           // 警告：MADI 只接了单向

    public var isError: Bool {
        switch self {
        case .unknownPort, .wrongDirection, .mediumMismatch: return true
        case .connectorNeedsAdapter, .missingReturnPath: return false
        }
    }

    public var description: String {
        switch self {
        case let .unknownPort(id): return "连接表引用了不存在的端口 \(id)"
        case let .wrongDirection(id): return "端口 \(id) 方向不对（应为输出→输入）"
        case let .mediumMismatch(a, b): return "接口类型不符：\(a.rawValue) 不能连到 \(b.rawValue)"
        case let .connectorNeedsAdapter(a, b): return "接头不同（\(a.rawValue)↔\(b.rawValue)），需要转接跳线"
        case .missingReturnPath: return "MADI 只有单向，缺少回程；回程承载 MIDI over MADI 遥控与对端时钟状态"
        }
    }
}

public struct Topology: Codable, Sendable {
    public var devices: [Device]
    public var links: [Link]

    public init(devices: [Device], links: [Link]) {
        self.devices = devices
        self.links = links
    }

    public func port(_ id: String) -> Port? {
        for d in devices { if let p = d.ports.first(where: { $0.id == id }) { return p } }
        return nil
    }

    public func device(_ id: String) -> Device? { devices.first { $0.id == id } }

    public func links(from portID: String) -> [Link] { links.filter { $0.from == portID } }
    public func links(into portID: String) -> [Link] { links.filter { $0.to == portID } }

    /// 连接表校验（H6、问题 8、T7）。
    public func validate() -> [(link: Link, issue: LinkIssue)] {
        var out: [(link: Link, issue: LinkIssue)] = []
        for link in links {
            guard let a = port(link.from) else { out.append((link, .unknownPort(link.from))); continue }
            guard let b = port(link.to) else { out.append((link, .unknownPort(link.to))); continue }
            if a.direction != .output { out.append((link, .wrongDirection(a.id))) }
            if b.direction != .input { out.append((link, .wrongDirection(b.id))) }
            if !a.type.canConnect(to: b.type) {
                out.append((link, .mediumMismatch(a.type, b.type)))
                continue
            }
            if a.connector != b.connector && Set<Connector>([a.connector, b.connector]) != Set<Connector>([.lc, .sfp]) {
                out.append((link, .connectorNeedsAdapter(a.connector, b.connector)))
            }
            if a.type == .madiOptical || a.type == .madiCoaxial {
                let hasReturn = links.contains { other in
                    guard let x = port(other.from), let y = port(other.to) else { return false }
                    return x.deviceID == b.deviceID && y.deviceID == a.deviceID && x.type == a.type
                }
                if !hasReturn { out.append((link, .missingReturnPath)) }
            }
        }
        return out
    }
}
