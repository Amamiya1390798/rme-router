import Foundation
import RMECore

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
    /// 控制室、全局静音、快照状态（第 7.9 节），键为去掉开头 “/” 的地址，如 "controlroom/dim"、"snapshot/load/2"。
    case global(key: String, value: OSCValue)
    /// 其余地址（混响、回声等），本 App 暂不解析。
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
        case "controlroom", "globalmute", "globalsolo", "snapshot":
            return .global(key: parts.joined(separator: "/"), value: value)
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

/// 通道条参数（文档第 7.8 节）。
public enum TotalMixStripParam: String, CaseIterable, Sendable, Codable {
    case volume, balpan, mute, phase
    /// 立体声合并（1）/ 拆分（0）；写在奇数号（左）通道上，改变通道布局（第 7.8 节）。
    case stereo
    /// 输出送进电脑录音同号通道（1）/ 关（0）；会顶替那一路原来的硬件输入（第 7.8 节）。
    case loopback

    /// 这一总线上有没有这个参数（协议表 + 实测：输入、回放没有 volume / balpan）。
    public func applies(to bus: TotalMixBus) -> Bool {
        switch self {
        case .volume, .balpan, .loopback: return bus == .output
        case .mute, .phase, .stereo: return true
        }
    }

    /// 协议表标 L/R：立体声右声道用 N+1 单独寻址。
    public var isPerSide: Bool { self == .phase }

    public var label: String {
        switch self {
        case .volume: return "音量"; case .balpan: return "平衡"; case .mute: return "静音"; case .phase: return "相位"
        case .stereo: return "立体声配对"
        case .loopback: return "送电脑录音"
        }
    }

    /// 截到协议允许的范围；音量 -65 dB 及以下为“关”（-300）。
    public func clamp(_ v: Double) -> Double {
        switch self {
        case .volume: return v <= TotalMixFader.offThresholdDB ? Double(TotalMixWrite.offDB) : min(v, TotalMixWrite.maxDB)
        case .balpan: return min(max(v, -1), 1)
        case .mute, .phase, .stereo, .loopback: return v >= 0.5 ? 1 : 0
        }
    }

    /// 界面文字。
    public func text(_ v: Double?) -> String {
        guard let v else { return "?" }
        switch self {
        case .volume: return TotalMixFader.isOn(v) ? String(format: "%.1f dB", v) : "关"
        case .balpan: return TotalMixWrite.panText(v)
        case .mute: return v >= 0.5 ? "静音" : "开"
        case .phase: return v >= 0.5 ? "反相" : "正相"
        case .stereo: return v >= 0.5 ? "立体声" : "单声道"
        case .loopback: return v >= 0.5 ? "送录音" : "关"
        }
    }
}

/// 控制室与快照（第 7.9 节）。只有这几项可写。
public enum TotalMixGlobal: Equatable, Hashable, Sendable {
    case dim, mainMono, globalMute
    /// 快照 1…8：调用
    case snapshot(Int)

    public var key: String {
        switch self {
        case .dim: return "controlroom/dim"
        case .mainMono: return "controlroom/mainmono"
        case .globalMute: return "globalmute"
        case let .snapshot(n): return "snapshot/load/\(n)"
        }
    }

    public var label: String {
        switch self {
        case .dim: return "Dim"
        case .mainMono: return "Main 单声道"
        case .globalMute: return "全局静音"
        case let .snapshot(n): return "调用快照 \(n)"
        }
    }

    /// 开关项的文字；快照是动作，没有开 / 关。
    public func text(_ v: Double?) -> String {
        guard let v else { return "?" }
        if case .snapshot = self { return v >= 1.5 ? (v >= 2.5 ? "已改动" : "当前") : "未用" }
        return v >= 0.5 ? "开" : "关"
    }
}

/// 写入类消息（文档第 7.1、7.2、7.8、7.9 节）：混音节点电平与声像、输入通道的前级三项、通道条参数。
/// 只能经 `TotalMixGlobalOSCClient.write` 发出，那里要求用户确认（`UserConfirmation`）。
public enum TotalMixWrite: Equatable, Sendable {
    /// 节点电平；dB 为 nil 表示关（发送 -300 dB）。超过 +6 dB 截到 +6，低于 -65 dB 视为关。
    case sendGain(source: TotalMixChannel, output: TotalMixChannel, dB: Double?)
    /// 输入通道的前级：增益（dB，截到 0–60）、48V、相位（1.0/0.0）。
    case preamp(input: TotalMixChannel, field: PreampField, value: PreampValue)
    /// 节点声像，-1（左）…+1（右）。
    case sendPan(source: TotalMixChannel, output: TotalMixChannel, pan: Double)
    /// 通道条参数（第 7.8 节）。
    case strip(channel: TotalMixChannel, param: TotalMixStripParam, value: Double)
    /// 控制室开关、全局静音、快照调用（第 7.9 节）。快照只发 1.0。
    case global(TotalMixGlobal, on: Bool)

    public static let offDB: Float = -300
    public static let maxDB = 6.0

    public var message: OSCMessage {
        switch self {
        case let .sendGain(src, out, dB):
            precondition(src.bus != .output && out.bus == .output, "节点来源须为输入/回放，目标须为输出")
            let value: Float = dB.flatMap(Self.clamp).map { Float($0) } ?? Self.offDB
            return OSCMessage("/mix/\(src.bus.shortToken)/\(src.wireIndex)/\(out.wireIndex)/fader", [.float(value)])
        case let .preamp(input, field, value):
            precondition(input.bus == .input, "前级只在输入通道上")
            let v: Float
            switch (field, value) {
            case let (.gain, .gain(g)): v = Float(min(max(g, PreampField.gainRange.lowerBound), PreampField.gainRange.upperBound))
            case let (.phantom, .flag(b)), let (.phase, .flag(b)): v = b ? 1 : 0
            default: preconditionFailure("字段与值类型不匹配：\(field) \(value)")
            }
            return OSCMessage("/input/\(input.wireIndex)/\(field.totalMixKey)", [.float(v)])
        case let .sendPan(src, out, pan):
            precondition(src.bus != .output && out.bus == .output, "节点来源须为输入/回放，目标须为输出")
            return OSCMessage("/mix/\(src.bus.shortToken)/\(src.wireIndex)/\(out.wireIndex)/balpan",
                              [.float(Float(TotalMixStripParam.balpan.clamp(pan)))])
        case let .strip(ch, param, value):
            precondition(param.applies(to: ch.bus), "\(ch.bus) 没有 \(param.rawValue)")
            return OSCMessage("/\(ch.bus.rawValue)/\(ch.wireIndex)/\(param.rawValue)", [.float(Float(param.clamp(value)))])
        case let .global(g, on):
            if case .snapshot = g { return OSCMessage("/\(g.key)", [.float(1)]) }
            return OSCMessage("/\(g.key)", [.float(on ? 1 : 0)])
        }
    }

    /// 声像文字：中、左 30、右 100。
    public static func panText(_ v: Double) -> String {
        let n = Int((v * 100).rounded())
        return n == 0 ? "中" : n < 0 ? "左 \(-n)" : "右 \(n)"
    }

    /// 截到 [-65, +6]；-65 及以下统一为关。
    static func clamp(_ dB: Double) -> Double? {
        dB <= TotalMixFader.offThresholdDB ? nil : min(dB, maxDB)
    }
}
