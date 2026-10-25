import Foundation
import CoreMIDI

/// 收发完整的 SysEx 报文（含 F0 … F7）。
public protocol XTCMIDITransport: AnyObject, Sendable {
    func start(onReceive: @escaping @Sendable ([UInt8]) -> Void) async throws
    func send(_ sysex: [UInt8]) async throws
    func stop()
}

public enum XTCTransportError: Error, Equatable {
    case endpointNotFound(String)
    case coreMIDI(String, Int32)
    case notStarted
}

/// UMP 7 位 SysEx 包（MIDI 1.0 协议下 CoreMIDI 用它承载 SysEx）。纯函数，便于测试。
public enum UMPSysEx7 {
    /// 一条 SysEx（含 F0/F7）拆成若干 64 位包（每包 2 个字，最多 6 个数据字节）。
    public static func pack(_ sysex: [UInt8], group: UInt8 = 0) -> [UInt32] {
        var body = sysex
        if body.first == 0xF0 { body.removeFirst() }
        if body.last == 0xF7 { body.removeLast() }
        let chunks = stride(from: 0, to: max(body.count, 1), by: 6).map { Array(body[$0 ..< min($0 + 6, body.count)]) }
        var words: [UInt32] = []
        for (i, chunk) in chunks.enumerated() {
            let status: UInt32 = chunks.count == 1 ? 0 : i == 0 ? 1 : i == chunks.count - 1 ? 3 : 2
            let b = chunk + Array(repeating: 0, count: 6 - chunk.count)
            let w0 = (0x3 << 28) | (UInt32(group & 0xF) << 24) | (status << 20) | (UInt32(chunk.count) << 16)
                | (UInt32(b[0]) << 8) | UInt32(b[1])
            let w1 = (UInt32(b[2]) << 24) | (UInt32(b[3]) << 16) | (UInt32(b[4]) << 8) | UInt32(b[5])
            words += [w0, w1]
        }
        return words
    }

    /// 把收到的 UMP 字流拼回完整 SysEx。非 SysEx 的包按长度跳过。
    public struct Assembler: Sendable {
        private var buffer: [UInt8]?
        public init() {}

        public mutating func feed(_ words: [UInt32]) -> [[UInt8]] {
            var out: [[UInt8]] = []
            var i = 0
            while i < words.count {
                let mt = words[i] >> 28
                let size: Int
                switch mt {
                case 0x0, 0x1, 0x2, 0x6, 0x7: size = 1
                case 0x3, 0x4, 0x8, 0x9, 0xA: size = 2
                case 0xB, 0xC: size = 3
                default: size = 4
                }
                defer { i += size }
                guard mt == 0x3, i + 1 < words.count else { continue }
                let w0 = words[i], w1 = words[i + 1]
                let status = (w0 >> 20) & 0xF, n = min(Int((w0 >> 16) & 0xF), 6)
                let all: [UInt8] = [UInt8((w0 >> 8) & 0xFF), UInt8(w0 & 0xFF),
                                    UInt8(w1 >> 24), UInt8((w1 >> 16) & 0xFF), UInt8((w1 >> 8) & 0xFF), UInt8(w1 & 0xFF)]
                let bytes = Array(all.prefix(n))
                switch status {
                case 0: out.append([0xF0] + bytes + [0xF7]); buffer = nil
                case 1: buffer = bytes
                case 2: buffer?.append(contentsOf: bytes)
                case 3:
                    if let b = buffer { out.append([0xF0] + b + bytes + [0xF7]) }
                    buffer = nil
                default: buffer = nil
                }
            }
            return out
        }
    }
}

/// CoreMIDI 端点的名字。
public enum MIDIEndpoints {
    public static func sources() -> [String] { (0 ..< MIDIGetNumberOfSources()).compactMap { name(MIDIGetSource($0)) } }
    public static func destinations() -> [String] {
        (0 ..< MIDIGetNumberOfDestinations()).compactMap { name(MIDIGetDestination($0)) }
    }

    static func name(_ e: MIDIEndpointRef) -> String? {
        for prop in [kMIDIPropertyDisplayName, kMIDIPropertyName] {
            var s: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(e, prop, &s) == noErr, let v = s?.takeRetainedValue() { return v as String }
        }
        return nil
    }

    static func source(named n: String) -> MIDIEndpointRef? {
        (0 ..< MIDIGetNumberOfSources()).map(MIDIGetSource).first { name($0) == n }
    }

    static func destination(named n: String) -> MIDIEndpointRef? {
        (0 ..< MIDIGetNumberOfDestinations()).map(MIDIGetDestination).first { name($0) == n }
    }
}

/// CoreMIDI 上的收发：从 `sourceName` 端点收，向 `destinationName` 端点发。
/// 发送前一律经过 `XTCSendGate`（这里是最后一层，适配器之外也绕不过去）。
public final class CoreMIDIXTCTransport: XTCMIDITransport, @unchecked Sendable {
    public let sourceName: String
    public let destinationName: String

    private let lock = NSLock()
    private var client = MIDIClientRef()
    private var inPort = MIDIPortRef()
    private var outPort = MIDIPortRef()
    private var destination: MIDIEndpointRef?
    private var assembler = UMPSysEx7.Assembler()

    public init(sourceName: String, destinationName: String) {
        self.sourceName = sourceName
        self.destinationName = destinationName
    }

    public func start(onReceive: @escaping @Sendable ([UInt8]) -> Void) async throws {
        guard let src = MIDIEndpoints.source(named: sourceName) else { throw XTCTransportError.endpointNotFound(sourceName) }
        guard let dst = MIDIEndpoints.destination(named: destinationName) else {
            throw XTCTransportError.endpointNotFound(destinationName)
        }
        var c = MIDIClientRef()
        try check(MIDIClientCreateWithBlock("RME Router XTC" as CFString, &c, nil), "MIDIClientCreate")
        var ip = MIDIPortRef(), op = MIDIPortRef()
        try check(MIDIInputPortCreateWithProtocol(c, "XTC in" as CFString, ._1_0, &ip) { [weak self] list, _ in
            guard let self else { return }
            for words in Self.words(list) {
                let messages = self.lock.withLock { self.assembler.feed(words) }
                messages.forEach(onReceive)
            }
        }, "MIDIInputPortCreate")
        try check(MIDIOutputPortCreate(c, "XTC out" as CFString, &op), "MIDIOutputPortCreate")
        try check(MIDIPortConnectSource(ip, src, nil), "MIDIPortConnectSource")
        lock.withLock { client = c; inPort = ip; outPort = op; destination = dst }
    }

    public func send(_ sysex: [UInt8]) async throws {
        try XTCSendGate.check(sysex)
        let (port, dst) = lock.withLock { (outPort, destination) }
        guard let dst, port != 0 else { throw XTCTransportError.notStarted }
        let status = Self.withEventList(UMPSysEx7.pack(sysex)) { MIDISendEventList(port, dst, $0) }
        try check(status, "MIDISendEventList")
    }

    public func stop() {
        lock.withLock {
            if client != 0 { MIDIClientDispose(client) }
            client = 0; inPort = 0; outPort = 0; destination = nil
        }
    }

    deinit { stop() }

    private func check(_ s: OSStatus, _ what: String) throws {
        if s != noErr { throw XTCTransportError.coreMIDI(what, s) }
    }

    /// 事件列表里每个包的字。
    static func words(_ list: UnsafePointer<MIDIEventList>) -> [[UInt32]] {
        list.unsafeSequence().map { pkt in
            let n = Int(pkt.pointee.wordCount)
            return withUnsafeBytes(of: pkt.pointee.words) { Array($0.bindMemory(to: UInt32.self).prefix(n)) }
        }
    }

    /// 把字流装进一个 MIDIEventList（每个 SysEx 包单独一个事件）。
    static func withEventList<R>(_ words: [UInt32], _ body: (UnsafePointer<MIDIEventList>) -> R) -> R {
        let size = 1024 + words.count * 8
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: MIDIEventList.self, capacity: 1)
        var pkt = MIDIEventListInit(list, ._1_0)
        var i = 0
        while i < words.count {
            let chunk = Array(words[i ..< min(i + 2, words.count)])
            pkt = chunk.withUnsafeBufferPointer { MIDIEventListAdd(list, size, pkt, 0, chunk.count, $0.baseAddress!) }
            i += 2
        }
        return body(list)
    }
}
