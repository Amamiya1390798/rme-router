import Foundation

/// 模拟的 XTC（测试与演示用，不碰真实设备）：按手册第 29 章应答“请求全部参数”，按置位标志采纳“设置参数”。
/// 也记录它收到的每一条报文，测试用来确认发了什么、没发什么。
public final class FakeXTC: XTCMIDITransport, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable ([UInt8]) -> Void)?
    private var _received: [[UInt8]] = []
    /// 参数表：索引 → (LSB, MSB)。
    private var params: [UInt8: (UInt8, UInt8)]
    public let midiDeviceID: UInt8
    /// 为 true 时不应答（模拟没接上）。
    public var silent = false
    /// 为 true 时收下设置但不采纳（模拟设备拒绝）。
    public var ignoreSets = false

    /// 默认状态：Mic 1–8 0 dB；ADAT1 ← MADI 1–8、ADAT2 ← MADI 9–16；MADI 输出 1–8 ← Mic；时钟 MADI、48 kHz；MADI 64 通道 48K 帧、已锁定同步。
    public init(midiDeviceID: UInt8 = 0) {
        self.midiDeviceID = midiDeviceID
        var p: [UInt8: (UInt8, UInt8)] = [:]
        for i in UInt8(0) ... 7 { p[i] = (0, 0) }
        p[14] = (3, 4)
        p[15] = (0, 0)
        p[16] = (0, 0); p[17] = (0, 0); p[18] = (0, 0); p[19] = (0, 0)
        p[21] = (7, 2)
        p[22] = (0x0C, 0)
        p[25] = (0x20, 0x20)
        params = p
    }

    public var received: [[UInt8]] { lock.withLock { _received } }

    public func value(_ index: UInt8) -> (lsb: UInt8, msb: UInt8)? { lock.withLock { params[index].map { ($0.0, $0.1) } } }

    public func setValue(_ index: UInt8, lsb: UInt8, msb: UInt8) { lock.withLock { params[index] = (lsb, msb) } }

    public func start(onReceive: @escaping @Sendable ([UInt8]) -> Void) async throws {
        lock.withLock { handler = onReceive }
    }

    public func stop() { lock.withLock { handler = nil } }

    public func send(_ sysex: [UInt8]) async throws {
        try XTCSendGate.check(sysex)
        let h: (@Sendable ([UInt8]) -> Void)? = lock.withLock {
            _received.append(sysex)
            return handler
        }
        guard let h else { throw XTCTransportError.notStarted }
        guard let msg = XTCSysEx.parse(sysex), msg.device == Int(midiDeviceID), !silent else { return }
        switch msg.command {
        case XTCSysEx.Command.requestAll.rawValue:
            h(dump())
        case XTCSysEx.Command.set.rawValue where !ignoreSets:
            lock.withLock {
                for p in msg.params {
                    var (l, m) = params[p.index] ?? (0, 0)
                    let f = p.flags ?? 0
                    if p.index <= 7 {
                        if f & 0x01 != 0 { l = (l & ~0x3F) | (p.lsb & 0x3F) }
                        if f & 0x02 != 0 { l = (l & ~0x40) | (p.lsb & 0x40) }
                        if f & 0x10 != 0 { m = (m & ~0x04) | (p.msb & 0x04) }
                    } else {
                        if f & 0x01 != 0 { l = p.lsb }
                        if f & 0x02 != 0 { m = p.msb }
                    }
                    params[p.index] = (l, m)
                }
            }
        default:
            break
        }
    }

    /// 命令 30：所有参数，每个 3 字节。
    func dump() -> [UInt8] {
        let body = lock.withLock { params.keys.sorted().flatMap { [$0, params[$0]!.0, params[$0]!.1] } }
        return XTCSysEx.header + [midiDeviceID, XTCSysEx.Command.send.rawValue] + body + [XTCSysEx.end]
    }
}
