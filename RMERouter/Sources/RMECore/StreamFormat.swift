import Foundation

public enum SpeedMode: Int, Codable, Sendable, Comparable {
    case single = 1, double = 2, quad = 4

    public init?(sampleRate: Int) {
        switch sampleRate {
        case 32_000...48_000: self = .single
        case 64_000...96_000: self = .double
        case 128_000...192_000: self = .quad
        default: return nil
        }
    }

    public static func < (l: SpeedMode, r: SpeedMode) -> Bool { l.rawValue < r.rawValue }
}

public enum MadiFrame: String, Codable, Sendable { case frame48k, frame96k }
public enum MadiChannelMode: Int, Codable, Sendable { case ch56 = 56, ch64 = 64 }

/// 一个端口当前“配置成”的流格式。发送端与接收端各有一份，链路检查比较两者。
/// 速度模式由采样率推出，不单独存，避免 v2 草案里 sampleRate 与 speedMode 互相矛盾。
public struct StreamFormat: Codable, Sendable, Hashable {
    public var sampleRate: Int
    public var madiFrame: MadiFrame?          // 仅 MADI
    public var channelMode: MadiChannelMode?  // 仅 MADI

    public init(sampleRate: Int, madiFrame: MadiFrame? = nil, channelMode: MadiChannelMode? = nil) {
        self.sampleRate = sampleRate
        self.madiFrame = madiFrame
        self.channelMode = channelMode
    }

    public var speed: SpeedMode? { SpeedMode(sampleRate: sampleRate) }

    /// 双速且用 48K 帧，即 S/MUX2。接收端无法从信号本身识别（RME 12Mic/M-1610 手册 MADI Inputs）。
    public var isSMUX: Bool {
        guard let s = speed else { return false }
        return s == .quad || (s == .double && madiFrame != .frame96k)
    }

    /// 该格式下一个端口实际承载的音频通道数。
    public func audioChannels(on type: PortType) -> Int? {
        guard let s = speed else { return nil }
        switch type {
        case .madiOptical, .madiCoaxial:
            let base = (channelMode ?? .ch64).rawValue
            return base / s.rawValue                    // 64/32/16 或 56/28/14
        case .adat:
            return 8 / s.rawValue                       // 8/4/2（S/MUX）
        case .aes:
            return 2
        case .analog, .ultranet, .usb, .wordClock, .ethernet:
            return nil
        }
    }

    /// 同一根 MADI/ADAT 线上看起来一样的“线上速率”（基础频率）。
    public var wireBaseRate: Int {
        guard let s = speed else { return sampleRate }
        if madiFrame == .frame96k && s == .double { return sampleRate }  // 96K 帧本身就是双速格式
        return sampleRate / s.rawValue
    }
}

/// 发送端与接收端格式比对的结果。
public enum FormatIssue: Equatable, Sendable, CustomStringConvertible {
    /// 两端采样率不同（问题 1 的直接表现）。
    case sampleRateMismatch(sender: Int, receiver: Int)
    /// 线上基础频率相同，但接收端按另一种速度模式解读——典型：XT 发 48 kHz 单速，XTC 设成 96 kHz。
    /// 这种情况下接收端照样显示 Lock，最危险。
    case speedMisinterpreted(sender: SpeedMode, receiver: SpeedMode)
    /// 发送端用 S/MUX，接收端必须手动设成相同速度（无法自动识别）。
    case smuxRequiresManualReceiverRate
    case channelModeMismatch(sender: MadiChannelMode, receiver: MadiChannelMode)
    /// 终端设备（如 P16-I）不支持该采样率。
    case unsupportedByTerminal(rate: Int, allowed: [Int])

    public var isError: Bool {
        switch self {
        case .channelModeMismatch, .smuxRequiresManualReceiverRate: return false
        default: return true
        }
    }

    public var description: String {
        switch self {
        case let .sampleRateMismatch(s, r): return "发送端 \(s) Hz，接收端设为 \(r) Hz"
        case let .speedMisinterpreted(s, r): return "线上基础频率一致，但接收端按 \(r) 速解读发送端的 \(s) 速信号"
        case .smuxRequiresManualReceiverRate: return "S/MUX 无法被接收端自动识别，接收端采样率必须手动设成一致"
        case let .channelModeMismatch(s, r): return "56/64 通道模式不一致（发 \(s.rawValue)，收 \(r.rawValue)）"
        case let .unsupportedByTerminal(rate, allowed):
            return "终端不接受 \(rate) Hz（只接受 \(allowed.map(String.init).joined(separator: "/")) Hz）"
        }
    }
}

public enum FormatCheck {
    /// 比较一条链路两端的配置。terminalRates 非空时附加终端约束（H2）。
    public static func compare(sender: StreamFormat, receiver: StreamFormat,
                               terminalRates: Set<Int> = []) -> [FormatIssue] {
        var issues: [FormatIssue] = []
        if sender.sampleRate != receiver.sampleRate {
            // 接收端看到的是发送端的线上基础频率；接收端自己的帧设置只影响它的输出。
            // 发送端不是 96K 帧时，接收端按自身速度设置解读，基础频率相同就会“Lock 但速率错”。
            if let s = sender.speed, let r = receiver.speed, s != r,
               sender.madiFrame != .frame96k,
               sender.sampleRate / s.rawValue == receiver.sampleRate / r.rawValue {
                issues.append(.speedMisinterpreted(sender: s, receiver: r))
            } else {
                issues.append(.sampleRateMismatch(sender: sender.sampleRate, receiver: receiver.sampleRate))
            }
        } else if sender.isSMUX {
            issues.append(.smuxRequiresManualReceiverRate)
        }
        if let s = sender.channelMode, let r = receiver.channelMode, s != r {
            issues.append(.channelModeMismatch(sender: s, receiver: r))
        }
        if !terminalRates.isEmpty && !terminalRates.contains(sender.sampleRate) {
            issues.append(.unsupportedByTerminal(rate: sender.sampleRate, allowed: terminalRates.sorted()))
        }
        return issues
    }
}
