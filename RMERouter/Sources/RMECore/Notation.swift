import Foundation

/// 链路表示法（v3 第 6.1 节）。
///
/// 地址 = 设备.接口.方向:通道，例如 `xt.madi1.in:9`、`12mic.madi_optical.out:9-20`。
/// - 设备：xt / 12mic / xtc / 外接设备自定 ID（如 p16i）
/// - 接口：优先用设备自己协议里的名字（12Mic 用 JSON 名 madi_optical）；其次用面板名
/// - 方向：in / out
/// - 通道：1 起；`a-b` 为连续范围（立体声、8 路块都用它）
/// 名字（TotalMix 的 M1-9、用户起的“主唱”）只是别名，从不作为键。
public enum Notation {
    public struct ParseError: Error, Equatable { public let text: String }

    /// 端口 ID 的规范形式：`设备.接口.方向`。
    public static func isValidPortID(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2] == "in" || parts[2] == "out" else { return false }
        let ok = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        return parts[0...1].allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(ok.contains) }
    }

    /// 解析 `port:n` 或 `port:a-b`，返回逐通道的 ChannelRef。
    public static func parse(_ text: String) throws -> [ChannelRef] {
        let pieces = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard pieces.count == 2, isValidPortID(pieces[0]) else { throw ParseError(text: text) }
        let range = pieces[1].split(separator: "-").map(String.init)
        guard (1...2).contains(range.count), let lo = Int(range[0]), lo >= 1 else { throw ParseError(text: text) }
        let hi = range.count == 2 ? Int(range[1]) : lo
        guard let hi, hi >= lo else { throw ParseError(text: text) }
        return (lo...hi).map { ChannelRef(pieces[0], $0) }
    }

    /// 把同一端口上的连续通道压缩成范围写法。
    public static func format(_ refs: [ChannelRef]) -> [String] {
        let byPort = Dictionary(grouping: refs, by: \.portID)
        var out: [String] = []
        for port in byPort.keys.sorted() {
            let chans = Set(byPort[port]!.map(\.channel)).sorted()
            var start = chans[0], prev = chans[0]
            for c in chans.dropFirst() + [Int.max] {
                if c == prev + 1 { prev = c; continue }
                out.append(start == prev ? "\(port):\(start)" : "\(port):\(start)-\(prev)")
                start = c; prev = c
            }
        }
        return out
    }
}

/// 一条路径的一跳：设备内路由（→）或线缆（⇒）。
public enum Hop: Equatable, Sendable, CustomStringConvertible {
    case route(from: ChannelRef, to: ChannelRef, domain: ControlDomain, kind: RouteKind)
    case cable(from: ChannelRef, to: ChannelRef)

    public var from: ChannelRef {
        switch self { case let .route(f, _, _, _), let .cable(f, _): return f }
    }
    public var to: ChannelRef {
        switch self { case let .route(_, t, _, _), let .cable(_, t): return t }
    }

    public var description: String {
        switch self {
        case let .route(f, t, d, k):
            let tag: String
            switch k {
            case let .mixSend(g): tag = "\(d.rawValue) 发送 " + (g.map { String(format: "%.1f dB", $0) } ?? "? dB")
            case .passthrough: tag = "\(d.rawValue) 直通"
            case let .blockAssign(n): tag = "\(d.rawValue) \(n) 路块"
            }
            return "\(f) →[\(tag)] \(t)"
        case let .cable(f, t):
            return "\(f) ⇒ \(t)"
        }
    }
}

/// 路径的自洽性检查（第 6.1 节的不变量）。返回违反的条目，空数组表示自洽。
public enum PathInvariants {
    public static func violations(_ hops: [Hop], in topology: Topology) -> [String] {
        var out: [String] = []
        for (i, h) in hops.enumerated() {
            guard let a = topology.port(h.from.portID), let b = topology.port(h.to.portID) else {
                out.append("第 \(i + 1) 跳引用了未登记的端口"); continue
            }
            switch h {
            case .route:
                if a.deviceID != b.deviceID { out.append("第 \(i + 1) 跳：设备内路由跨了设备") }
                if a.direction != .input || b.direction != .output { out.append("第 \(i + 1) 跳：路由必须是 in → out") }
            case .cable:
                if a.deviceID == b.deviceID { out.append("第 \(i + 1) 跳：线缆两端是同一台设备") }
                if a.direction != .output || b.direction != .input { out.append("第 \(i + 1) 跳：线缆必须是 out ⇒ in") }
                if h.from.channel != h.to.channel { out.append("第 \(i + 1) 跳：线缆不改变通道号") }
                if !topology.links.contains(where: { $0.from == a.id && $0.to == b.id }) {
                    out.append("第 \(i + 1) 跳：连接表里没有这根线")
                }
            }
            if i > 0 && hops[i - 1].to != h.from { out.append("第 \(i + 1) 跳：没有接上上一跳的终点") }
            if i > 0, case .cable = h, case .cable = hops[i - 1] { out.append("第 \(i + 1) 跳：两根线缆不能直接相连") }
        }
        return out
    }
}
