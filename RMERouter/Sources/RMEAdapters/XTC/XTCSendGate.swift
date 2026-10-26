import Foundation

/// 发往 XTC 的最后一道闸门（文档第 6.3 节）。所有 SysEx 都经过这里；不在白名单里的一律拦截。
/// 发往设备方向的索引 23（MIDI 来源）、25（预设加载/保存）、26（编组增益）等危险参数绝不放行。
public enum XTCSendGate {
    public enum Rejection: Error, Equatable {
        case notXTCSysEx
        case command(UInt8)
        case malformed
        case index(UInt8)
        case flags(index: UInt8, flags: UInt8)
        case value(index: UInt8)
    }

    /// 前级允许的置位标志：增益 0x01、反相 0x02、静音 0x04、AutoSet 0x08、48V 0x10、PAD / Inst 0x20（编组 0x40 不放行）。
    static let micFlags: UInt8 = 0x01 | 0x02 | 0x04 | 0x08 | 0x10 | 0x20
    /// 路由的两块：0x01 / 0x02。
    static let routingFlags: UInt8 = 0x01 | 0x02
    static let routingIndices: Set<UInt8> = [14, 16, 17, 18, 19]
    /// 60 dB 的增益编码（第 7.2 节：增益先限定 0–60 dB）。
    static let maxGainCode = XTCMicSettings.code(fromGain: 60)

    public static func check(_ bytes: [UInt8]) throws {
        guard bytes.count >= 8, Array(bytes.prefix(5)) == XTCSysEx.header, bytes.last == XTCSysEx.end,
              bytes[5] <= 0x7F else { throw Rejection.notXTCSysEx }
        guard bytes.dropFirst().dropLast().allSatisfy({ $0 <= 0x7F }) else { throw Rejection.malformed }
        let cmd = bytes[6]
        switch cmd {
        case XTCSysEx.Command.requestAll.rawValue, XTCSysEx.Command.requestLevels.rawValue,
             XTCSysEx.Command.requestChanged.rawValue:
            guard bytes.count == 8 else { throw Rejection.malformed }
        case XTCSysEx.Command.set.rawValue:
            let data = bytes.count - 8
            guard data > 0, data % 4 == 0, let msg = XTCSysEx.parse(bytes) else { throw Rejection.malformed }
            for p in msg.params { try check(p) }
        default:
            throw Rejection.command(cmd)
        }
    }

    static func check(_ p: XTCSysEx.Param) throws {
        let flags = p.flags ?? 0
        switch p.index {
        case 0 ... 7:
            guard flags != 0, flags & ~micFlags == 0 else { throw Rejection.flags(index: p.index, flags: flags) }
            if flags & 0x01 != 0, p.lsb & 0x3F > maxGainCode { throw Rejection.value(index: p.index) }
        case let i where routingIndices.contains(i):
            guard flags != 0, flags & ~routingFlags == 0 else { throw Rejection.flags(index: p.index, flags: flags) }
            if flags & 0x01 != 0, XTCRoutingSource(value: Int(p.lsb)) == nil { throw Rejection.value(index: p.index) }
            if flags & 0x02 != 0, XTCRoutingSource(value: Int(p.msb)) == nil { throw Rejection.value(index: p.index) }
        default:
            throw Rejection.index(p.index)
        }
    }
}
