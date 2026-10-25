import Foundation
import RMECore

/// OctaMic XTC 的 MIDI SysEx 协议（文档第 6.3 节）。
/// 出处（A）：OctaMic XTC 用户手册 v1.3 第 29 章，https://www.rme-audio.de/downloads/octamicxtc_e.pdf
public enum XTCSysEx {
    public static let header: [UInt8] = [0xF0, 0x00, 0x20, 0x0D, 0x69]
    public static let end: UInt8 = 0xF7

    public enum Command: UInt8, Sendable {
        case requestAll = 0x10, requestLevels = 0x11, requestChanged = 0x12, set = 0x20, send = 0x30
    }

    /// 一个参数：索引、LSB、MSB；设置时带置位标志（只有标志里的位会被设备采纳）。
    public struct Param: Equatable, Sendable {
        public var index: UInt8
        public var lsb: UInt8
        public var msb: UInt8
        public var flags: UInt8?

        public init(index: UInt8, lsb: UInt8, msb: UInt8, flags: UInt8? = nil) {
            self.index = index
            self.lsb = lsb
            self.msb = msb
            self.flags = flags
        }
    }

    public enum CodecError: Error, Equatable {
        case deviceID(Int)
        case dataByte(UInt8)
        case notSysEx
    }

    public static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }

    /// 请求类消息（10、11、12）。
    public static func request(_ cmd: Command, device: Int) throws -> [UInt8] {
        guard (0 ... 0x7F).contains(device) else { throw CodecError.deviceID(device) }
        return header + [UInt8(device), cmd.rawValue, end]
    }

    /// 设置参数（20）：每个参数 4 字节，必须带置位标志。
    public static func set(_ params: [Param], device: Int) throws -> [UInt8] {
        guard (0 ... 0x7F).contains(device) else { throw CodecError.deviceID(device) }
        var out = header + [UInt8(device), Command.set.rawValue]
        for p in params {
            for b in [p.index, p.lsb, p.msb, p.flags ?? 0x7F] {
                guard b <= 0x7F else { throw CodecError.dataByte(b) }
                out.append(b)
            }
        }
        return out + [end]
    }

    /// 解析一条 XTC SysEx。命令 30（设备发出）按每参数 3 字节解析（手册：不带置位标志）；命令 20 按 4 字节。
    public static func parse(_ bytes: [UInt8]) -> (device: Int, command: UInt8, params: [Param])? {
        guard bytes.count >= 8, Array(bytes.prefix(5)) == header, bytes.last == end else { return nil }
        let device = Int(bytes[5]), command = bytes[6]
        let data = Array(bytes[7 ..< bytes.count - 1])
        let stride = command == Command.set.rawValue ? 4 : 3
        guard command == Command.set.rawValue || command == Command.send.rawValue else {
            return (device, command, [])
        }
        var params: [Param] = []
        var i = 0
        while i + stride <= data.count {
            params.append(Param(index: data[i], lsb: data[i + 1], msb: data[i + 2], flags: stride == 4 ? data[i + 3] : nil))
            i += stride
        }
        return (device, command, params)
    }
}

// MARK: - 参数含义

/// 数字路由的来源（手册值表 2）。
public enum XTCRoutingSource: Equatable, Hashable, Sendable {
    case mic            // Mic 1–8
    case adatIn
    case aesIn
    case madi(block: Int)       // 0…7：MADI 1–8 … 57–64
    case playback(value: Int)   // 11…15：PB 1–8、5–12、9–16、13–20、17–24

    public init?(value: Int) {
        switch value {
        case 0: self = .mic
        case 1: self = .adatIn
        case 2: self = .aesIn
        case 3 ... 10: self = .madi(block: value - 3)
        case 11 ... 15: self = .playback(value: value)
        default: return nil
        }
    }

    /// 面板上的名字（值表 2）。
    public var label: String {
        switch self {
        case .mic: return "Mic 1–8"
        case .adatIn: return "ADAT IN"
        case .aesIn: return "AES IN"
        case let .madi(b): return "MADI \(b * 8 + 1)–\(b * 8 + 8)"
        case let .playback(v): let f = (v - 11) * 4 + 1; return "PB \(f)–\(f + 7)"
        }
    }

    public var value: Int {
        switch self {
        case .mic: return 0
        case .adatIn: return 1
        case .aesIn: return 2
        case let .madi(b): return 3 + b
        case let .playback(v): return v
        }
    }

    /// 来源对应的本 App 通道（8 路块的首通道）；没有登记端口的（ADAT/AES 输入、电脑回放）为 nil。
    public func firstChannel(deviceID: String = "xtc") -> ChannelRef? {
        switch self {
        case .mic: return ChannelRef("\(deviceID).mic.in", 1)
        case let .madi(b): return ChannelRef("\(deviceID).madi.in", b * 8 + 1)
        case .adatIn, .aesIn, .playback: return nil
        }
    }

    /// 由本 App 通道反查来源（必须落在 8 路块的首通道）。
    public init?(firstChannel ref: ChannelRef, deviceID: String = "xtc") {
        guard ref.offsetInBlock == 0 else { return nil }
        if ref.portID == "\(deviceID).mic.in", ref.channel == 1 { self = .mic; return }
        if ref.portID == "\(deviceID).madi.in", (0 ... 7).contains(ref.block) { self = .madi(block: ref.block); return }
        return nil
    }
}

/// 数字路由的目标（参数 14、16–19 的 LSB/MSB 半）。
public enum XTCRoutingOutput: Equatable, Hashable, Sendable {
    case adat1, adat2
    case madi(block: Int)   // 0…7：MADI 输出 1–8 … 57–64

    public var index: UInt8 {
        switch self {
        case .adat1, .adat2: return 14
        case let .madi(b): return UInt8(16 + b / 2)
        }
    }

    /// true：在 LSB（置位标志 0x01）；false：在 MSB（0x02）。
    public var isLSB: Bool {
        switch self {
        case .adat1: return true
        case .adat2: return false
        case let .madi(b): return b % 2 == 0
        }
    }

    public static let all: [XTCRoutingOutput] = [.adat1, .adat2] + (0 ... 7).map { .madi(block: $0) }

    public func port(deviceID: String = "xtc") -> String {
        switch self {
        case .adat1: return "\(deviceID).adat1.out"
        case .adat2: return "\(deviceID).adat2.out"
        case .madi: return "\(deviceID).madi.out"
        }
    }

    /// 这一块在端口上的首通道。
    public var firstChannel: Int {
        if case let .madi(b) = self { return b * 8 + 1 }
        return 1
    }

    public init?(portID: String, channel: Int, deviceID: String = "xtc") {
        let block = (channel - 1) / 8
        switch portID {
        case "\(deviceID).adat1.out" where block == 0: self = .adat1
        case "\(deviceID).adat2.out" where block == 0: self = .adat2
        case "\(deviceID).madi.out" where (0 ... 7).contains(block): self = .madi(block: block)
        default: return nil
        }
    }

    /// 设置这一块来源的参数（只置这一半的标志，另一半不变）。
    public func setParam(_ source: XTCRoutingSource) -> XTCSysEx.Param {
        let v = UInt8(source.value)
        return isLSB ? .init(index: index, lsb: v, msb: 0, flags: 0x01) : .init(index: index, lsb: 0, msb: v, flags: 0x02)
    }
}

/// XTC 一路话放（参数 0–7）。
public struct XTCMicSettings: Equatable, Sendable {
    public var gainDB: Double
    public var phase: Bool
    public var mute: Bool
    public var autoSet: Bool
    public var phantom: Bool
    public var padOrInstrument: Bool
    /// 编组：0 = 无，1…4。
    public var group: Int

    /// 增益编码：0 = 0 dB；n（1…56）= n+9 dB，即 10…65 dB。
    public static func gain(fromCode c: Int) -> Double { c == 0 ? 0 : Double(c + 9) }
    /// 0 dB 编码为 0；其余按 10…65 dB 截取后取整。
    public static func code(fromGain dB: Double) -> UInt8 {
        if dB < 0.5 { return 0 }
        return UInt8(min(max(Int(dB.rounded()), 10), 65) - 9)
    }

    /// 设置一路（mic 1…8）的参数：只给要改的字段置标志，其余字段设备不动。
    public static func setParam(mic: Int, gainDB: Double? = nil, phase: Bool? = nil, phantom: Bool? = nil) -> XTCSysEx.Param {
        var p = XTCSysEx.Param(index: UInt8(mic - 1), lsb: 0, msb: 0, flags: 0)
        if let g = gainDB { p.lsb |= code(fromGain: g); p.flags! |= 0x01 }
        if let ph = phase { if ph { p.lsb |= 0x40 }; p.flags! |= 0x02 }
        if let v = phantom { if v { p.msb |= 0x04 }; p.flags! |= 0x10 }
        return p
    }

    /// 本 App 的前级字段 → 设置参数；类型不匹配为 nil。
    public static func setParam(mic: Int, field: PreampField, value: PreampValue) -> XTCSysEx.Param? {
        switch (field, value) {
        case let (.gain, .gain(g)): return setParam(mic: mic, gainDB: g)
        case let (.phase, .flag(b)): return setParam(mic: mic, phase: b)
        case let (.phantom, .flag(b)): return setParam(mic: mic, phantom: b)
        default: return nil
        }
    }

    /// XTC 实际能设的增益（0 dB 或 10–65 dB 的整数）。
    public static func effectiveGain(_ dB: Double) -> Double { gain(fromCode: Int(code(fromGain: dB))) }

    public init(lsb: UInt8, msb: UInt8) {
        gainDB = Self.gain(fromCode: Int(lsb & 0x3F))
        phase = lsb & 0x40 != 0
        mute = msb & 0x01 != 0
        autoSet = msb & 0x02 != 0
        phantom = msb & 0x04 != 0
        padOrInstrument = msb & 0x08 != 0
        group = Int((msb >> 4) & 0x07)
    }
}

/// 从一次“请求全部参数”的回包解出的 XTC 状态。
public struct XTCState: Equatable, Sendable {
    public var mics: [Int: XTCMicSettings] = [:]           // 1…8
    public var routing: [XTCRoutingOutput: XTCRoutingSource] = [:]
    public var clockSource: Int?                            // 0 internal、1 WCK、2–5 AES1–4、6 ADAT、7 MADI
    public var sampleRate: Int?
    public var madi64: Bool?
    public var madiFrame48k: Bool?
    public var lock: UInt8?
    public var sync: UInt8?

    public static let sampleRates = [32_000, 44_100, 48_000, 64_000, 88_200, 96_000, 128_000, 176_400, 192_000]

    public init() {}

    /// 应用设备发出（命令 30）的参数。注意索引 25、26 在发出方向分别是 Lock/Sync 与电平（手册）。
    public mutating func apply(_ params: [XTCSysEx.Param]) {
        for p in params {
            switch p.index {
            case 0 ... 7:
                mics[Int(p.index) + 1] = XTCMicSettings(lsb: p.lsb, msb: p.msb)
            case 14, 16 ... 19:
                let outs: (XTCRoutingOutput, XTCRoutingOutput) = p.index == 14
                    ? (.adat1, .adat2)
                    : (.madi(block: Int(p.index - 16) * 2), .madi(block: Int(p.index - 16) * 2 + 1))
                routing[outs.0] = XTCRoutingSource(value: Int(p.lsb & 0x0F))
                routing[outs.1] = XTCRoutingSource(value: Int(p.msb & 0x0F))
            case 21:
                clockSource = Int(p.lsb & 0x0F)
                let i = Int(p.msb & 0x0F)
                sampleRate = Self.sampleRates.indices.contains(i) ? Self.sampleRates[i] : nil
            case 22:
                madi64 = p.lsb & 0x04 != 0
                madiFrame48k = p.lsb & 0x08 != 0
            case 25:
                lock = p.lsb
                sync = p.msb
            default:
                break
            }
        }
    }

    /// 数字路由翻译成本 App 的路由：每块 8 条，块内偏移不变（第 6.1 节不变量 5）。
    public func routes(deviceID: String = "xtc") -> [Route] {
        routing.flatMap { out, src -> [Route] in
            guard let first = src.firstChannel(deviceID: deviceID) else { return [] }
            return (0 ..< 8).map { k in
                Route(domain: .xtc, source: ChannelRef(first.portID, first.channel + k),
                      destination: ChannelRef(out.port(deviceID: deviceID), out.firstChannel + k),
                      kind: .blockAssign(size: 8), evidence: .confirmed)
            }
        }
        .sorted { $0.destination == $1.destination ? $0.source < $1.source : $0.destination < $1.destination }
    }

    /// MADI 输入的 Lock/Sync（位 5）。
    public var madiLock: Bool? { lock.map { $0 & 0x20 != 0 } }
    public var madiSync: Bool? { sync.map { $0 & 0x20 != 0 } }
}

/// 电平字节解码（参数 26–31）：126 = OVR（记 0 dB 以上），0 = 下溢（nil）。
public enum XTCLevel {
    public static func dB(_ v: UInt8) -> Double? {
        switch v {
        case 126: return 0.1
        case 95 ... 125: return (Double(v) - 125) * 0.2
        case 23 ... 94: return (Double(v) - 107) * 0.5
        case 1 ... 22: return Double(v) - 65
        default: return nil
        }
    }
}
