import Foundation
import RMECore

public enum Severity: String, Codable, Sendable { case error, warning, info }

/// 体检结论。读不到数据时必须是 cannotDetermine，不能是 pass（第 7 节）。
public enum Verdict: Equatable, Sendable {
    case pass
    case fail(String)
    case cannotDetermine(String)

    public var isFail: Bool { if case .fail = self { return true } else { return false } }
    public var isPass: Bool { self == .pass }
    public var isUndetermined: Bool { if case .cannotDetermine = self { return true } else { return false } }
}

public struct Finding: Equatable, Sendable {
    public var ruleID: String
    public var severity: Severity
    public var subject: String      // 设备、链路或端口
    public var verdict: Verdict
}

public protocol DiagnosticRule: Sendable {
    var id: String { get }
    var severity: Severity { get }
    func evaluate(_ s: SystemSnapshot) -> [Finding]
}

extension DiagnosticRule {
    func finding(_ subject: String, _ verdict: Verdict) -> Finding {
        Finding(ruleID: id, severity: severity, subject: subject, verdict: verdict)
    }
}

public enum Diagnostics {
    public static let allRules: [any DiagnosticRule] = [
        R1SingleMaster(), R2SampleRate(), R3LinkFormat(), R4SlaveSource(), R5LockSync(),
        R6ReturnPath(), R7TerminalRate(), R8TerminalClock(), R9ControlPaths(), R10Online(),
        R11AuxMapping(), R12XTCAdatSource(), R13OutputMute(), R14SpeedInfo(),
    ]

    public static func run(_ s: SystemSnapshot, rules: [any DiagnosticRule] = allRules) -> [Finding] {
        rules.flatMap { $0.evaluate(s) }
    }

    /// 参与时钟/控制检查的设备：排除只做终端的 P16 系列。
    static func clockedDevices(_ s: SystemSnapshot) -> [Device] {
        s.topology.devices.filter { $0.model != .p16i && $0.model != .p16m }
    }

    static func isTerminal(_ s: SystemSnapshot, deviceID: String) -> TerminalConstraint? {
        s.terminals.first { $0.deviceID == deviceID }
    }
}

// MARK: - 时钟

/// R1 存在且仅有一个主时钟。
public struct R1SingleMaster: DiagnosticRule {
    public let id = "R1"; public let severity = Severity.error
    public init() {}
    public func evaluate(_ s: SystemSnapshot) -> [Finding] {
        var masters: [String] = [], unknown: [String] = []
        for d in Diagnostics.clockedDevices(s) {
            guard let snap = s.devices[d.id], snap.reachable else { unknown.append(d.name); continue }
            switch snap.clock.isMaster {
            case .some(true): masters.append(d.name)
            case .some(false): break
            case .none: unknown.append(d.name)
            }
        }
        if masters.count > 1 { return [finding("系统", .fail("有 \(masters.count) 个主时钟：\(masters.joined(separator: "、"))"))] }
        if !unknown.isEmpty { return [finding("系统", .cannotDetermine("读不到时钟源：\(unknown.joined(separator: "、"))"))] }
        if masters.isEmpty { return [finding("系统", .fail("没有主时钟，所有设备都在跟随外部信号"))] }
        return [finding("系统", .pass)]
    }
}

/// R2 同一时钟域内所有设备设置的采样率一致（含从机：S/MUX 下从机必须手动设对）。
public struct R2SampleRate: DiagnosticRule {
    public let id = "R2"; public let severity = Severity.error
    public init() {}
    public func evaluate(_ s: SystemSnapshot) -> [Finding] {
        var rates: [String: Int] = [:], unknown: [String] = []
        for d in Diagnostics.clockedDevices(s) {
            if let r = s.devices[d.id]?.clock.configuredRate.knownValue, s.devices[d.id]?.reachable == true {
                rates[d.name] = r
            } else { unknown.append(d.name) }
        }
        if Set(rates.values).count > 1 {
            let text = rates.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value) Hz" }.joined(separator: "，")
            return [finding("系统", .fail("采样率不一致：\(text)"))]
        }
        if !unknown.isEmpty { return [finding("系统", .cannotDetermine("读不到采样率：\(unknown.joined(separator: "、"))"))] }
        return [finding("系统", .pass)]
    }
}

/// R4 从机的时钟源指向一个确实接了线的输入端口。
public struct R4SlaveSource: DiagnosticRule {
    public let id = "R4"; public let severity = Severity.error
    public init() {}
    public func evaluate(_ s: SystemSnapshot) -> [Finding] {
        Diagnostics.clockedDevices(s).compactMap { d in
            guard let snap = s.devices[d.id], snap.reachable, let src = snap.clock.source.knownValue else {
                return finding(d.name, .cannotDetermine("读不到时钟源"))
            }
            guard case let .port(p) = src else { return nil }   // 主机不检查
            return s.topology.links(into: p).isEmpty
                ? finding(d.name, .fail("锁在 \(p)，但连接表里这个口没有接线"))
                : finding(d.name, .pass)
        }
    }
}

/// R5 每条数字链路接收端 Lock 与 Sync 都为真。Lock 只表示有信号，Sync 才表示同步。
public struct R5LockSync: DiagnosticRule {
    public let id = "R5"; public let severity = Severity.warning
    public init() {}
    public func evaluate(_ s: SystemSnapshot) -> [Finding] {
        s.topology.links.compactMap { link in
            guard let to = s.topology.port(link.to), [.madiOptical, .madiCoaxial, .adat].contains(to.type),
                  Diagnostics.isTerminal(s, deviceID: to.deviceID) == nil else { return nil }
            let snap = s.devices[to.deviceID]
            guard let lock = snap?.clock.lock[to.id]?.knownValue, let sync = snap?.clock.sync[to.id]?.knownValue else {
                return finding(to.id, .cannotDetermine("读不到 Lock/Sync 状态"))
            }
            if !lock { return finding(to.id, .fail("没有有效输入信号（No Lock）")) }
            if !sync { return finding(to.id, .fail("有信号但未与当前时钟同步（Lock 但非 Sync）")) }
            return finding(to.id, .pass)
        }
    }
}

// MARK: - 链路

/// R3 链路两端格式一致，含“Lock 但速度模式解读错误”的情况（问题 1）。
public struct R3LinkFormat: DiagnosticRule {
    public let id = "R3"; public let severity = Severity.error
    public init() {}
    public func evaluate(_ s: SystemSnapshot) -> [Finding] {
        s.topology.links.compactMap { link in
            guard let from = s.topology.port(link.from), let to = s.topology.port(link.to),
                  [.madiOptical, .madiCoaxial, .adat].contains(from.type),
                  Diagnostics.isTerminal(s, deviceID: to.deviceID) == nil else { return nil }
            guard let tx = s.format(of: from.id)?.knownValue, let rx = s.format(of: to.id)?.knownValue else {
                return finding("\(from.id)→\(to.id)", .cannotDetermine("读不到一端的格式"))
            }
            let errors = FormatCheck.compare(sender: tx, receiver: rx).filter(\.isError)
            return errors.isEmpty
                ? finding("\(from.id)→\(to.id)", .pass)
                : finding("\(from.id)→\(to.id)", .fail(errors.map(\.description).joined(separator: "；")))
        }
    }
}

/// R6 MADI 收发成对。
public struct R6ReturnPath: DiagnosticRule {
    public let id = "R6"; public let severity = Severity.warning
    public init() {}
    public func evaluate(_ s: SystemSnapshot) -> [Finding] {
        let missing = s.topology.validate().filter { $0.issue == .missingReturnPath }
            .map { finding("\($0.link.from)→\($0.link.to)", .fail($0.issue.description)) }
        // 没有缺的就明确给一条通过，免得“没有结论”被当成“没有可检查的项”。
        return missing.isEmpty ? [finding("连接表", .pass)] : missing
    }
}

/// R7 送往终端的链路采样率在终端支持范围内（P16-I：44.1/48 kHz）。
public struct R7TerminalRate: DiagnosticRule {
    public let id = "R7"; public let severity = Severity.error
    public init() {}
    public func evaluate(_ s: SystemSnapshot) -> [Finding] {
        s.topology.links.compactMap { link in
            guard let to = s.topology.port(link.to), let term = Diagnostics.isTerminal(s, deviceID: to.deviceID) else { return nil }
            guard let tx = s.format(of: link.from)?.knownValue else {
                return finding(to.id, .cannotDetermine("读不到发送端 \(link.from) 的格式"))
            }
            let issues = FormatCheck.compare(sender: tx, receiver: tx, terminalRates: term.allowedSampleRates)
                .filter(\.isError)
            return issues.isEmpty ? finding(to.id, .pass)
                                  : finding(to.id, .fail(issues.map(\.description).joined(separator: "；")))
        }
    }
}

/// R8 终端的时钟输入口（P16-I 的 ADAT A）接了线；指示灯只能人工确认。
public struct R8TerminalClock: DiagnosticRule {
    public let id = "R8"; public let severity = Severity.warning
    public init() {}
    public func evaluate(_ s: SystemSnapshot) -> [Finding] {
        s.terminals.compactMap { t in
            guard let clockPort = t.clockInputPort else { return nil }
            if s.topology.links(into: clockPort).isEmpty {
                return finding(clockPort, .fail("时钟只取自 \(clockPort)，但这个口没有接线；只接 ADAT B 不会出声"))
            }
            if let led = s.devices[t.deviceID]?.settings["\(clockPort).signalLED"]?.knownValue {
                return led == "on" ? finding(clockPort, .pass) : finding(clockPort, .fail("ADAT 状态灯未亮"))
            }
            return finding(clockPort, .cannotDetermine("已接线；请人工确认 ADAT 状态灯和通道信号灯"))
        }
    }
}

// MARK: - 控制

/// R9 控制路径并行检查，按设备策略判断（复核后替代 v2 的全局“只能一条”）。
public struct R9ControlPaths: DiagnosticRule {
    public let id = "R9"; public let severity = Severity.warning
    public init() {}
    public func evaluate(_ s: SystemSnapshot) -> [Finding] {
        Diagnostics.clockedDevices(s).compactMap { d in
            guard let snap = s.devices[d.id], snap.reachable else { return finding(d.name, .cannotDetermine("设备不可读")) }
            let active = snap.controlPaths.filter(\.active)
            guard active.count > 1 else { return finding(d.name, .pass) }
            let names = active.map(\.controller).joined(separator: "、")
            switch s.concurrency[d.id] ?? .unknown {
            case .parallelAllowed: return finding(d.name, .pass)
            case .singleControlInput: return finding(d.name, .fail("同时有 \(names) 在遥控；该设备只接受一个控制来源"))
            case .unknown: return finding(d.name, .fail("同时有 \(names) 在遥控；能否并存未经确认"))
            }
        }
    }
}

/// R10 可控设备在线；离线设备的一切状态都是“未知”。
public struct R10Online: DiagnosticRule {
    public let id = "R10"; public let severity = Severity.info
    public init() {}
    public func evaluate(_ s: SystemSnapshot) -> [Finding] {
        Diagnostics.clockedDevices(s).map { d in
            s.devices[d.id]?.reachable == true ? finding(d.name, .pass)
                                               : finding(d.name, .fail("离线或不可读，相关状态一律显示为“未知”"))
        }
    }
}

/// R11 12Mic 输出到 MADI 的位置与 TotalMix Aux Device 的通道配置一致。
/// 12Mic 没有“偏移”参数：位置由 /routing 逐通道决定（官方 JSON 手册）。
public struct R11AuxMapping: DiagnosticRule {
    public let id = "R11"; public let severity = Severity.error
    public init() {}
    public func evaluate(_ s: SystemSnapshot) -> [Finding] {
        s.auxDeviceFirstChannel.compactMap { deviceID, auxFirst in
            guard let snap = s.devices[deviceID], snap.reachable else {
                return finding(deviceID, .cannotDetermine("设备不可读，无法核对 Aux Device 映射"))
            }
            // 找“输入 1”送到哪个 MADI 输出通道，再沿线缆看它落在 XT 的哪个输入通道。
            guard let r = snap.routes.first(where: { $0.source.channel == 1 && Self.isMadiOut(s, $0.destination.portID) }),
                  let link = s.topology.links(from: r.destination.portID).first else {
                return finding(deviceID, .cannotDetermine("没有读到输入 1 的 MADI 路由"))
            }
            let landed = ChannelRef(link.to, r.destination.channel)
            return landed == auxFirst
                ? finding(deviceID, .pass)
                : finding(deviceID, .fail("输入 1 实际落在 \(landed)，Aux Device 按 \(auxFirst) 遥控，前级遥控会作用到错位的通道"))
        }
    }

    static func isMadiOut(_ s: SystemSnapshot, _ portID: String) -> Bool {
        guard let p = s.topology.port(portID) else { return false }
        return p.direction == .output && (p.type == .madiOptical || p.type == .madiCoaxial)
    }
}

/// R12 设备专有设置是否符合用户声明的期望（首要是 XTC 的 ADAT Out 源）。
public struct R12XTCAdatSource: DiagnosticRule {
    public let id = "R12"; public let severity = Severity.warning
    public init() {}
    public func evaluate(_ s: SystemSnapshot) -> [Finding] {
        s.expectations.sorted { $0.key < $1.key }.map { key, expected in
            let actual = s.devices.values.compactMap { $0.settings[key] }.first
            guard let v = actual?.knownValue else { return finding(key, .cannotDetermine("读不到，需在设备面板上人工确认")) }
            return v == expected ? finding(key, .pass) : finding(key, .fail("当前为 \(v)，预期 \(expected)"))
        }
    }
}

/// R13 目标输出没有被静音。
public struct R13OutputMute: DiagnosticRule {
    public let id = "R13"; public let severity = Severity.warning
    public init() {}
    public func evaluate(_ s: SystemSnapshot) -> [Finding] {
        s.devices.values.flatMap { snap in
            snap.outputMuted.sorted { $0.key < $1.key }.map { ch, fact in
                guard let muted = fact.knownValue else { return finding(ch.description, .cannotDetermine("读不到静音状态")) }
                return muted ? finding(ch.description, .fail("输出被静音，路径通也不会有声音")) : finding(ch.description, .pass)
            }
        }
    }
}

/// R14 双速/四速时提示每口通道数减半或减到四分之一。
public struct R14SpeedInfo: DiagnosticRule {
    public let id = "R14"; public let severity = Severity.info
    public init() {}
    public func evaluate(_ s: SystemSnapshot) -> [Finding] {
        let rates = s.devices.values.compactMap { $0.clock.configuredRate.knownValue }
        // 一个采样率都读不到时不能算通过（读不到 = 无法判断）。
        guard !rates.isEmpty else { return [finding("系统", .cannotDetermine("读不到任何设备的采样率"))] }
        guard let high = rates.compactMap(SpeedMode.init(sampleRate:)).max(), high != .single else { return [finding("系统", .pass)] }
        return [finding("系统", .fail("当前为 \(high == .double ? "双速" : "四速")：MADI 每口最多 \(64 / high.rawValue) 路，ADAT 每口 \(8 / high.rawValue) 路，请重新检查路由"))]
    }
}
