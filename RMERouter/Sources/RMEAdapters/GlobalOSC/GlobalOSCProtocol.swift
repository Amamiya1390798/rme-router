import Foundation

/// TotalMix FX 2.1 Global OSC 的地址层。
/// 出处（A）：RME 协议表 OSCProtocoll_260721.ods，https://www.rme-audio.de/downloads/globalosc_protocol_b2.zip
/// 文档第 7 节是本文件的规范；协议表更新时先改文档再改这里。

/// 通道总线。通道参数用 input / playback / output；混音节点与电平用缩写 in / pb / out。
public enum TotalMixBus: String, CaseIterable, Codable, Sendable {
    case input, playback, output

    var shortToken: String {
        switch self {
        case .input: return "in"
        case .playback: return "pb"
        case .output: return "out"
        }
    }

    init?(shortToken: String) {
        switch shortToken {
        case "in": self = .input
        case "pb": self = .playback
        case "out": self = .output
        default: return nil
        }
    }
}

/// TotalMix 的一个通道。`number` 从 1 起（地址层规则，文档第 6.1 节不变量 7）；
/// 协议的 0 起编号只经 `wireIndex` / `init(bus:wireIndex:)` 换算，别处不得自行加减 1。
public struct TotalMixChannel: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var bus: TotalMixBus
    public var number: Int

    public init(_ bus: TotalMixBus, _ number: Int) {
        precondition(number >= 1, "TotalMix 通道号在地址层从 1 起")
        self.bus = bus
        self.number = number
    }

    init(bus: TotalMixBus, wireIndex: Int) {
        self.init(bus, wireIndex + 1)
    }

    var wireIndex: Int { number - 1 }

    public static func < (l: TotalMixChannel, r: TotalMixChannel) -> Bool {
        l.bus == r.bus ? l.number < r.number : l.bus.rawValue < r.bus.rawValue
    }

    public var description: String { "\(bus.rawValue) \(number)" }
}

/// 只读请求（协议表中“Rec.”列的 send… 触发命令）。只读客户端只能发这些。
public enum TotalMixRequest: Equatable, Sendable {
    /// `/sendall`：全部参数；activeNodesOnly 时值为 2，只发电平 > -65 dB 的混音节点。
    case sendAll(activeNodesOnly: Bool)
    /// `/sendsettings`：控制参数与效果器设置。
    case sendSettings
    /// `/sendchan/<bus>/<N>`：该通道全部参数（总线在前，alpha 7 起）。
    case sendChannel(TotalMixChannel)
    /// `/sendmix`：全部混音节点；1 = 全部，2 = 仅 > -65 dB。
    case sendMix(activeNodesOnly: Bool)
    /// `/sendsubmix/<输出>`：某个输出（Submix）的混音节点。
    case sendSubmix(output: TotalMixChannel, activeNodesOnly: Bool)
    /// `/sendstate`：全部状态消息。
    case sendState

    /// 触发类命令一律带值（文档第 7 节安全规则 2）：小于 0.5 会被 TotalMix 忽略，所以只发 1.0 或 2.0。
    public var message: OSCMessage {
        let trigger: Float = 1.0
        func level(_ activeOnly: Bool) -> Float { activeOnly ? 2.0 : 1.0 }
        switch self {
        case let .sendAll(a): return OSCMessage("/sendall", [.float(level(a))])
        case .sendSettings: return OSCMessage("/sendsettings", [.float(trigger)])
        case let .sendChannel(ch): return OSCMessage("/sendchan/\(ch.bus.rawValue)/\(ch.wireIndex)", [.float(trigger)])
        case let .sendMix(a): return OSCMessage("/sendmix", [.float(level(a))])
        case let .sendSubmix(out, a):
            precondition(out.bus == .output, "Submix 只能是输出通道")
            return OSCMessage("/sendsubmix/\(out.wireIndex)", [.float(level(a))])
        case .sendState: return OSCMessage("/sendstate", [.float(trigger)])
        }
    }
}

/// 从 TotalMix 收到的一条消息，按协议表分类。
public enum TotalMixEvent: Equatable, Sendable {
    /// `/mix/<in|pb>/<源>/<输出>/<参数>`，参数如 fader（dB）、faderlin、balpan、solo。
    case mixNode(source: TotalMixChannel, output: TotalMixChannel, parameter: String, value: OSCValue)
    /// `/<input|playback|output>/<N>/<参数>`，多级参数用 “/” 连接，如 "eq/enable"。
    case channel(TotalMixChannel, parameter: String, value: OSCValue)
    /// `/level/<in|pb|out>/<N>`：峰值电平 dB。
    case level(TotalMixChannel, dB: Double)
    /// `/status/<键>`：device（s）、connection（f）、dsp（f）。
    case status(key: String, value: OSCValue)
    /// 其余地址（控制室、混响、快照等），本 App 暂不解析。
    case other(OSCMessage)

    public static func parse(_ m: OSCMessage) -> TotalMixEvent {
        guard let value = m.arguments.first else { return .other(m) }
        let parts = m.address.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let head = parts.first else { return .other(m) }

        switch head {
        case "mix":
            guard parts.count == 5, let bus = TotalMixBus(shortToken: parts[1]), bus != .output,
                  let src = Int(parts[2]), let out = Int(parts[3]), src >= 0, out >= 0 else { return .other(m) }
            return .mixNode(source: TotalMixChannel(bus: bus, wireIndex: src),
                            output: TotalMixChannel(bus: .output, wireIndex: out),
                            parameter: parts[4], value: value)
        case "input", "playback", "output":
            guard parts.count >= 3, let bus = TotalMixBus(rawValue: head), let n = Int(parts[1]), n >= 0 else {
                return .other(m)
            }
            return .channel(TotalMixChannel(bus: bus, wireIndex: n),
                            parameter: parts[2...].joined(separator: "/"), value: value)
        case "level":
            guard parts.count == 3, let bus = TotalMixBus(shortToken: parts[1]), let n = Int(parts[2]), n >= 0,
                  let dB = value.number else { return .other(m) }
            return .level(TotalMixChannel(bus: bus, wireIndex: n), dB: dB)
        case "status":
            guard parts.count == 2 else { return .other(m) }
            return .status(key: parts[1], value: value)
        default:
            return .other(m)
        }
    }
}

/// 推子曲线（协议表 “Fader curve” 页的 CalcFaderDB / CalcFaderLin）。
public enum TotalMixFader {
    /// 节点电平不高于此值视为“关”（协议表：/sendall 2 只发 > -65 dB 的节点）。
    public static let offThresholdDB = -65.0

    public static func isOn(_ dB: Double) -> Bool { dB > offThresholdDB }

    /// faderlin（0–1）→ dB；低于 -64.9 dB 为关，返回 nil。
    public static func dB(fromLinear value: Double) -> Double? {
        let pos = value * 1023
        let dB = pos >= 649
            ? pos * 0.0320855615 - 26.8235294118
            : pos * pos * (-1.0 / 11033.0) + pos * 0.1497326203 - 65.0
        return dB < -64.9 ? nil : dB
    }

    /// dB → faderlin（0–1）。
    public static func linear(fromDB dB: Double) -> Double {
        let pos = dB >= -6
            ? (dB + 26.8235294118) * (1 / 0.0320855615)
            : 826.0 - (-34869.0 - 11033.0 * dB).squareRoot()
        return min(max(pos / 1023, 0), 1)
    }
}
