import Foundation
import RMECore
import RMEAdapters

/// 通道条的屏蔽与搜索（文档第 6.4.5 节）。只影响本 App 的显示，不向设备发送任何东西。
extension AppModel {
    public func hideStrips(_ chs: Set<TotalMixChannel>) {
        let new = hiddenStrips.union(chs)
        if new != hiddenStrips { hiddenStrips = new }
    }

    public func unhideStrips(_ chs: Set<TotalMixChannel>) {
        let new = hiddenStrips.subtracting(chs)
        if new != hiddenStrips { hiddenStrips = new }
    }

    public func unhideAllStrips() {
        if !hiddenStrips.isEmpty { hiddenStrips = [] }
    }

    /// 搜索通道条：名字、源头（“12Mic Mic 1”）、通道号（“输入 9”“回放 3”“输出 7”，也认 in / pb / out）。
    /// 名字开头匹配的排前面；最多 limit 条。被屏蔽的也能搜到。
    public func searchStrips(_ query: String, limit: Int = 8) -> [StripHit] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let words = q.split(separator: " ").map(String.init)
        var hits: [(rank: Int, hit: StripHit)] = []
        for bus in [TotalMixBus.input, .playback, .output] {
            let strips = xtStrips(bus)
            let origins = bus == .input ? originLabels(strips.compactMap(\.ref)) : [:]
            for s in strips {
                let origin = s.ref.flatMap { origins[$0]?.text }
                let numbers = s.stereo ? [s.tm.number, s.tm.number + 1] : [s.tm.number]
                let busNames = bus == .input ? ["输入", "in", "录音"] : bus == .playback ? ["回放", "pb", "playback"] : ["输出", "out"]
                var keys = [s.name.lowercased()] + (origin.map { [$0.lowercased()] } ?? [])
                for n in numbers { keys += busNames.flatMap { ["\($0) \(n)", "\($0)\(n)"] } }
                // 每个词都要在某个键里出现（“mic 1”“输入 9”这类两段词也行）
                let joined = keys.joined(separator: " | ")
                guard words.allSatisfy({ joined.contains($0) }) || keys.contains(where: { $0.contains(q) }) else { continue }
                let rank = s.name.lowercased() == q ? 0 : s.name.lowercased().hasPrefix(q) ? 1 : keys.contains { $0.hasPrefix(q) } ? 2 : 3
                hits.append((rank, StripHit(strip: s, origin: origin, hidden: hiddenStrips.contains(s.tm))))
            }
        }
        return hits.sorted { ($0.rank, $0.hit.strip.tm) < ($1.rank, $1.hit.strip.tm) }.prefix(limit).map(\.hit)
    }
}

public struct StripHit: Identifiable, Equatable, Sendable {
    public var strip: XTStrip
    public var origin: String?
    public var hidden: Bool
    public var id: TotalMixChannel { strip.tm }

    /// 列表里第二行：“输入 9 · ← 12Mic Mic 1”。
    public var detail: String {
        let bus = strip.tm.bus == .input ? "输入" : strip.tm.bus == .playback ? "回放" : "输出"
        let n = strip.stereo ? "\(strip.tm.number)/\(strip.tm.number + 1)" : "\(strip.tm.number)"
        return ["\(bus) \(n)", origin, hidden ? "已屏蔽" : nil].compactMap { $0 }.joined(separator: " · ")
    }
}
