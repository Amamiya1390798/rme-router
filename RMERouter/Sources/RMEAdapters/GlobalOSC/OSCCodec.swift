import Foundation

/// OSC 1.0 编解码（与设备无关）。规范：https://opensoundcontrol.stanford.edu/spec-1_0.html
/// TotalMix Global OSC 只用到 f / s，另接受 T/F 与整数（协议表 Description 页）。

public enum OSCValue: Equatable, Sendable, CustomStringConvertible {
    case float(Float)
    case int(Int32)
    case string(String)
    case blob(Data)
    case bool(Bool)       // T / F，无数据
    case double(Double)
    case int64(Int64)
    case null             // N
    case impulse          // I

    var tag: Character {
        switch self {
        case .float: return "f"
        case .int: return "i"
        case .string: return "s"
        case .blob: return "b"
        case let .bool(b): return b ? "T" : "F"
        case .double: return "d"
        case .int64: return "h"
        case .null: return "N"
        case .impulse: return "I"
        }
    }

    /// 数值型参数统一读成 Double（TotalMix 的布尔、整数都是“数值”）。
    public var number: Double? {
        switch self {
        case let .float(v): return Double(v)
        case let .int(v): return Double(v)
        case let .double(v): return v
        case let .int64(v): return Double(v)
        case let .bool(b): return b ? 1 : 0
        default: return nil
        }
    }

    public var text: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    public var description: String {
        switch self {
        case let .float(v): return "\(v)"
        case let .int(v): return "\(v)i"
        case let .string(s): return "\"\(s)\""
        case let .blob(d): return "<\(d.count) bytes>"
        case let .bool(b): return b ? "T" : "F"
        case let .double(v): return "\(v)d"
        case let .int64(v): return "\(v)h"
        case .null: return "N"
        case .impulse: return "I"
        }
    }
}

public struct OSCMessage: Equatable, Sendable, CustomStringConvertible {
    public var address: String
    public var arguments: [OSCValue]

    public init(_ address: String, _ arguments: [OSCValue] = []) {
        self.address = address
        self.arguments = arguments
    }

    public var description: String {
        ([address] + arguments.map(\.description)).joined(separator: " ")
    }
}

public enum OSCPacket: Equatable, Sendable {
    case message(OSCMessage)
    case bundle(timeTag: UInt64, elements: [OSCPacket])

    /// 展开 bundle，按出现顺序返回全部消息。
    public var messages: [OSCMessage] {
        switch self {
        case let .message(m): return [m]
        case let .bundle(_, elements): return elements.flatMap(\.messages)
        }
    }
}

public enum OSCDecodeError: Error, Equatable {
    case truncated
    case badString
    case badAddress
    case badTypeTags
    case unsupportedTag(Character)
}

public enum OSCCodec {
    // MARK: 编码

    public static func encode(_ message: OSCMessage) -> Data {
        var out = Data()
        appendString(message.address, to: &out)
        appendString("," + String(message.arguments.map(\.tag)), to: &out)
        for arg in message.arguments {
            switch arg {
            case let .float(v): appendUInt32(v.bitPattern, to: &out)
            case let .int(v): appendUInt32(UInt32(bitPattern: v), to: &out)
            case let .string(s): appendString(s, to: &out)
            case let .blob(d):
                appendUInt32(UInt32(d.count), to: &out)
                out.append(d)
                out.append(contentsOf: [UInt8](repeating: 0, count: pad(d.count) - d.count))
            case let .double(v): appendUInt64(v.bitPattern, to: &out)
            case let .int64(v): appendUInt64(UInt64(bitPattern: v), to: &out)
            case .bool, .null, .impulse: break
            }
        }
        return out
    }

    public static func encode(_ packet: OSCPacket) -> Data {
        switch packet {
        case let .message(m): return encode(m)
        case let .bundle(timeTag, elements):
            var out = Data()
            appendString("#bundle", to: &out)
            appendUInt64(timeTag, to: &out)
            for e in elements {
                let d = encode(e)
                appendUInt32(UInt32(d.count), to: &out)
                out.append(d)
            }
            return out
        }
    }

    // MARK: 解码

    public static func decode(_ data: Data) throws -> OSCPacket {
        var r = Reader(bytes: [UInt8](data))
        return try decodePacket(&r, end: r.bytes.count)
    }

    private static func decodePacket(_ r: inout Reader, end: Int) throws -> OSCPacket {
        guard r.pos < end else { throw OSCDecodeError.truncated }
        if r.bytes[r.pos] == UInt8(ascii: "#") {
            let head = try r.string()
            guard head == "#bundle" else { throw OSCDecodeError.badAddress }
            let timeTag = try r.uint64()
            var elements: [OSCPacket] = []
            while r.pos < end {
                let size = Int(try r.uint32())
                guard size >= 0, size % 4 == 0, r.pos + size <= end else { throw OSCDecodeError.truncated }
                var sub = Reader(bytes: r.bytes, pos: r.pos)
                elements.append(try decodePacket(&sub, end: r.pos + size))
                r.pos += size
            }
            return .bundle(timeTag: timeTag, elements: elements)
        }
        let address = try r.string()
        guard address.hasPrefix("/") else { throw OSCDecodeError.badAddress }
        // 无类型标签的旧式消息：按无参数处理。
        guard r.pos < end else { return .message(OSCMessage(address)) }
        let tags = try r.string()
        guard tags.first == "," else { throw OSCDecodeError.badTypeTags }
        var args: [OSCValue] = []
        for tag in tags.dropFirst() {
            switch tag {
            case "f": args.append(.float(Float(bitPattern: try r.uint32())))
            case "i": args.append(.int(Int32(bitPattern: try r.uint32())))
            case "s", "S": args.append(.string(try r.string()))
            case "b":
                let n = Int(try r.uint32())
                guard n >= 0, r.pos + pad(n) <= r.bytes.count else { throw OSCDecodeError.truncated }
                args.append(.blob(Data(r.bytes[r.pos ..< r.pos + n])))
                r.pos += pad(n)
            case "d": args.append(.double(Double(bitPattern: try r.uint64())))
            case "h": args.append(.int64(Int64(bitPattern: try r.uint64())))
            case "T": args.append(.bool(true))
            case "F": args.append(.bool(false))
            case "N": args.append(.null)
            case "I": args.append(.impulse)
            default: throw OSCDecodeError.unsupportedTag(tag)
            }
        }
        return .message(OSCMessage(address, args))
    }

    // MARK: 工具

    static func pad(_ n: Int) -> Int { (n + 3) & ~3 }

    private static func appendString(_ s: String, to out: inout Data) {
        let bytes = Array(s.utf8)
        out.append(contentsOf: bytes)
        // 至少一个 0 结尾，再补齐到 4 字节
        out.append(contentsOf: [UInt8](repeating: 0, count: pad(bytes.count + 1) - bytes.count))
    }

    private static func appendUInt32(_ v: UInt32, to out: inout Data) {
        withUnsafeBytes(of: v.bigEndian) { out.append(contentsOf: $0) }
    }

    private static func appendUInt64(_ v: UInt64, to out: inout Data) {
        withUnsafeBytes(of: v.bigEndian) { out.append(contentsOf: $0) }
    }

    private struct Reader {
        let bytes: [UInt8]
        var pos = 0

        mutating func uint32() throws -> UInt32 {
            guard pos + 4 <= bytes.count else { throw OSCDecodeError.truncated }
            defer { pos += 4 }
            return bytes[pos ..< pos + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }

        mutating func uint64() throws -> UInt64 {
            guard pos + 8 <= bytes.count else { throw OSCDecodeError.truncated }
            defer { pos += 8 }
            return bytes[pos ..< pos + 8].reduce(0) { $0 << 8 | UInt64($1) }
        }

        mutating func string() throws -> String {
            guard let zero = bytes[pos...].firstIndex(of: 0) else { throw OSCDecodeError.badString }
            guard let s = String(bytes: bytes[pos ..< zero], encoding: .utf8) else { throw OSCDecodeError.badString }
            let next = pos + OSCCodec.pad(zero - pos + 1)
            guard next <= bytes.count else { throw OSCDecodeError.truncated }
            pos = next
            return s
        }
    }
}
