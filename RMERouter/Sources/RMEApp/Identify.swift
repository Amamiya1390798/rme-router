import Foundation
import RMECore
import RMEEngine

/// 一根线缆的核对结果（文档第 6.5 节）。按两端端口记，接线一改就自然作废。
public struct LinkVerification: Codable, Equatable, Sendable {
    public enum Method: String, Codable, Sendable { case signal, user }
    public var from: String
    public var to: String
    public var method: Method
    public var date: Date
    /// 核对时用的那一路，例如“12Mic Mic 3 → MADI 1 输入 11”。
    public var detail: String

    public var key: String { Self.key(from, to) }
    static func key(_ from: String, _ to: String) -> String { "\(from)→\(to)" }
}

/// 线缆的可信程度（第 6.5 节“显示规则”）。
public enum CableStatus: Equatable, Sendable {
    case verified(LinkVerification)
    /// 接收端设备读到这个口已锁定：线是通的，但不说明对端是哪个口。
    case lockSeen
    case declared

    public var text: String {
        switch self {
        case let .verified(v):
            return (v.method == .signal ? "已用信号核对" : "用户确认") + "（\(v.date.formatted(date: .abbreviated, time: .omitted))）"
        case .lockSeen: return "接收端读到锁定（未确认是哪个口）"
        case .declared: return "只是接线表里的声明，未核对"
        }
    }
}

/// 信号核对（认线）：说话或轻拍一支麦克风，看它实际出现在 XT 的哪一路输入。只读。
public struct IdentifyTest: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case match(ChannelRef)
        case elsewhere(found: ChannelRef, expected: [ChannelRef])
        case none
    }

    public var source: ChannelRef
    /// 按当前接线和路由算出的：它应该出现在 XT 的哪些输入通道。
    public var expected: [ChannelRef]
    /// 到达每个预期通道经过的线缆（两端端口）。
    public var cables: [ChannelRef: [(from: String, to: String)]]
    public var startedAt: Date
    public var baseline: [ChannelRef: Double]
    public var peak: [ChannelRef: Double] = [:]
    public var outcome: Outcome?

    public static let duration: TimeInterval = 10
    /// 判定“明显升高”：比开始时高 20 dB 以上，且高于 -50 dB。
    public static let rise = 20.0, floor = -50.0

    public static func == (a: IdentifyTest, b: IdentifyTest) -> Bool {
        a.source == b.source && a.startedAt == b.startedAt && a.peak == b.peak && a.outcome == b.outcome
    }

    /// 电平明显升高的通道，最响的在前。
    public var candidates: [ChannelRef] {
        peak.filter { ref, p in p > Self.floor && p - (baseline[ref] ?? -144) >= Self.rise }
            .sorted { $0.value > $1.value }.map(\.key)
    }
}

public enum IdentifyError: Error, Equatable {
    case noLevels
    case notTraced

    public var text: String {
        switch self {
        case .noLevels: return "收不到 \(mainName) 的电平：\(mainName) 要在线，TotalMix 的 OSC 设置里要勾 Send Level Data"
        case .notTraced: return "按当前接线和路由，这一路到不了 \(mainName)；先在“设置 → 接线”或路由里接通"
        }
    }
}

extension AppModel {
    static let verificationsKey = "link.verifications"

    /// 一个来源按当前接线和路由应该出现在 XT 的哪些输入通道，以及路上经过的线缆。
    public func expectedXTInputs(from source: ChannelRef) -> [ChannelRef: [(from: String, to: String)]] {
        let topo = snapshot.topology
        func isXTInput(_ r: ChannelRef) -> Bool {
            guard let p = topo.port(r.portID) else { return false }
            return p.deviceID == "xt" && p.direction == .input && p.type != .usb
        }
        if isXTInput(source) { return [source: []] }
        var out: [ChannelRef: [(from: String, to: String)]] = [:]
        for path in SignalTrace(snapshot: snapshot).downstream(from: source) {
            var cables: [(from: String, to: String)] = []
            for step in path {
                if case let .cable(f, t) = step.hop { cables.append((f.portID, t.portID)) }
                if isXTInput(step.hop.to) { out[step.hop.to] = cables; break }
            }
        }
        return out
    }

    /// 开始信号核对。返回错误说明；nil 表示已开始听。
    @discardableResult
    public func startIdentify(source: ChannelRef, now: Date = Date()) -> IdentifyError? {
        guard meters.receiving(now: now) else { return .noLevels }
        let expected = expectedXTInputs(from: source)
        guard !expected.isEmpty else { return .notTraced }
        identify = IdentifyTest(source: source, expected: expected.keys.sorted(), cables: expected, startedAt: now,
                                baseline: xtInputLevels())
        return nil
    }

    /// 每次取到电平后调用：记录各输入的峰值；到时间自动结束。
    public func identifySample(now: Date = Date()) {
        guard var t = identify, t.outcome == nil else { return }
        for (ref, dB) in xtInputLevels() where dB > (t.peak[ref] ?? -144) { t.peak[ref] = dB }
        identify = t
        if now.timeIntervalSince(t.startedAt) >= IdentifyTest.duration { finishIdentify() }
    }

    /// 结束并判定。一致时把路上的线缆记为“已用信号核对”。
    public func finishIdentify(now: Date = Date()) {
        guard var t = identify, t.outcome == nil else { return }
        let found = t.candidates
        if let hit = found.first(where: t.expected.contains) {
            t.outcome = .match(hit)
            for c in t.cables[hit] ?? [] {
                let v = LinkVerification(from: c.from, to: c.to, method: .signal, date: now,
                                         detail: "\(shortName(t.source)) → \(shortName(hit))")
                linkVerifications[v.key] = v
            }
        } else if let other = found.first {
            t.outcome = .elsewhere(found: other, expected: t.expected)
        } else {
            t.outcome = IdentifyTest.Outcome.none
        }
        identify = t
    }

    public func cancelIdentify() { identify = nil }

    /// XT 各输入通道当前电平（没收到的不列）。
    func xtInputLevels() -> [ChannelRef: Double] {
        let topo = snapshot.topology
        return meters.levels.filter { ref, _ in
            topo.port(ref.portID).map { $0.deviceID == "xt" && $0.direction == .input && $0.type != .usb } ?? false
        }
    }

    /// 线缆的可信程度：信号核对 / 用户确认 > 接收端读到锁定 > 声明。
    public func cableStatus(_ link: Link) -> CableStatus {
        if let v = linkVerifications[LinkVerification.key(link.from, link.to)] { return .verified(v) }
        if let to = snapshot.topology.port(link.to), let lock = snapshot.devices[to.deviceID]?.clock.lock[link.to],
           lock.evidence == .confirmed, lock.value == true { return .lockSeen }
        return .declared
    }

    /// 用户对照实物后手动确认一根线（最后手段）。
    public func confirmLinkByUser(_ link: Link, now: Date = Date()) {
        let v = LinkVerification(from: link.from, to: link.to, method: .user, date: now, detail: "用户对照实物确认")
        linkVerifications[v.key] = v
    }
}
