import Foundation
import RMECore
import RMEAdapters

/// 一条待应用的 TotalMix 通道条改动（文档第 7.8 节）：通道的音量 / 平衡 / 静音 / 相位，或一条发送的声像。
public struct PendingStripChange: Identifiable, Equatable, Sendable {
    public enum Target: Equatable, Sendable {
        case channel(ref: ChannelRef, tm: TotalMixChannel, param: TotalMixStripParam)
        case sendPan(source: ChannelRef, destination: ChannelRef, tmSource: TotalMixChannel, tmOutput: TotalMixChannel)
    }

    public let id: UUID
    public var target: Target
    /// TotalMix 里的通道名（对照用）。
    public var tmName: String?
    /// 立体声：改动作用于左右两声道。
    public var stereo: Bool
    public var old: Double?
    public var new: Double

    public var param: TotalMixStripParam {
        if case let .channel(_, _, p) = target { return p }
        return .balpan
    }

    public var write: TotalMixWrite {
        switch target {
        case let .channel(_, tm, p): return .strip(channel: tm, param: p, value: new)
        case let .sendPan(_, _, s, o): return .sendPan(source: s, output: o, pan: new)
        }
    }

    public var operation: PlannedOperation {
        PlannedOperation(id: id, deviceID: "xt", parameter: write.message.address,
                         oldValue: param.text(old), newValue: param.text(new), access: .readWrite)
    }

    public var title: String {
        switch target {
        case let .channel(ref, _, p): return "\(ref.description) \(p.label)"
        case let .sendPan(s, d, _, _): return "发送 \(s.description) → \(d.description) 声像"
        }
    }

    public var changeText: String { "\(param.text(old)) → \(param.text(new))" }
    public var wireText: String { "OSC：" + write.message.description }

    public var totalMixLabel: String {
        switch target {
        case let .channel(_, tm, _): return tmName.map { "\(tm)（\($0)）" } ?? "\(tm)"
        case let .sendPan(_, _, s, o): return "\(s) → \(o)"
        }
    }

    /// 合并或拆分立体声：改变通道布局。
    public var isLayoutChange: Bool { param == .stereo }

    /// 打开送电脑录音：顶替录音通道原来的硬件输入，一律明确确认（第 7.8 节）。
    public var isLoopbackOn: Bool { param == .loopback && (old ?? 0) < 0.5 && new >= 0.5 }

    /// 送电脑录音顶替的录音通道（同号的硬件输入），例如“录音 9/10”。
    public var loopbackRecording: String? {
        guard param == .loopback, case let .channel(_, tm, _) = target else { return nil }
        return stereo ? "录音 \(tm.number)/\(tm.number + 1)" : "录音 \(tm.number)"
    }

    /// 取消静音：会突然出声。
    public var isUnmute: Bool { param == .mute && (old ?? 0) >= 0.5 && new < 0.5 }

    /// 输出音量一次抬高超过 20 dB 且目标高于 -20 dB（“关”按 -65 dB 计，第 7.4 节）。
    public var isLargeJump: Bool {
        guard param == .volume else { return false }
        let o = old.flatMap { TotalMixFader.isOn($0) ? $0 : nil } ?? TotalMixFader.offThresholdDB
        let n = TotalMixFader.isOn(new) ? new : TotalMixFader.offThresholdDB
        return n - o > AppModel.largeJumpDB && n > -20
    }

    var key: String {
        switch target {
        case let .channel(_, tm, p): return "ch|\(tm)|\(p.rawValue)"
        case let .sendPan(_, _, s, o): return "pan|\(s)|\(o)"
        }
    }

    static func same(_ p: TotalMixStripParam, _ a: Double?, _ b: Double?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        switch p {
        case .volume: return (!TotalMixFader.isOn(a) && !TotalMixFader.isOn(b)) || abs(a - b) < 0.05
        case .balpan: return abs(a - b) < 0.005
        case .mute, .phase, .stereo, .loopback: return (a >= 0.5) == (b >= 0.5)
        }
    }
}

extension AppModel {
    /// 立体声右声道（偶数号、左声道为立体声）换成左声道；其余原样。
    func leftOfPair(_ ch: TotalMixChannel) -> TotalMixChannel {
        guard ch.number % 2 == 0 else { return ch }
        let left = TotalMixChannel(ch.bus, ch.number - 1)
        return tmState.isStereo(left) == true ? left : ch
    }

    /// XT 某通道的通道条参数当前值（读回）；没有或不适用为 nil。
    public func stripValue(_ ref: ChannelRef, _ param: TotalMixStripParam) -> Double? {
        guard let tm = tmChannel(for: ref), param.applies(to: tm.bus) else { return nil }
        return tmState.stripValue(tmState.stripTarget(tm, param), param)
    }

    /// 待应用栏里的目标值。
    public func pendingStrip(_ ref: ChannelRef, _ param: TotalMixStripParam) -> Double? {
        pendingStrips.first {
            if case let .channel(r, _, p) = $0.target { return p == param && (r == ref || $0.stereo && pairs(r, ref)) }
            return false
        }?.new
    }

    /// 一条发送当前的声像（读回）；没有这条发送为 nil。
    public func sendPan(source: ChannelRef, destination: ChannelRef) -> Double? {
        guard let s = tmChannel(for: source), let o = tmChannel(for: destination) else { return nil }
        let key = TotalMixState.NodeKey(source: leftOfPair(s), output: leftOfPair(o))
        guard tmState.gainDB(key) != nil else { return nil }
        return tmState.nodePan(key) ?? 0
    }

    public func pendingSendPan(source: ChannelRef, destination: ChannelRef) -> Double? {
        pendingStrips.first {
            if case let .sendPan(s, d, _, _) = $0.target { return s == source && d == destination }
            return false
        }?.new
    }

    private func pairs(_ a: ChannelRef, _ b: ChannelRef) -> Bool {
        a.portID == b.portID && (a.channel - 1) / 2 == (b.channel - 1) / 2
    }

    /// 暂存一个通道条参数（第 7.8 节）。改回原值时移除。
    @discardableResult
    public func stageStrip(_ ref: ChannelRef, _ param: TotalMixStripParam, _ value: Double) -> StageError? {
        guard lastLoaded != nil else { return .notLoaded }
        guard deviceID(of: ref) == "xt" else { return .notTotalMix }
        guard let tm0 = tmChannel(for: ref) else { return .notMapped(ref) }
        guard param.applies(to: tm0.bus) else { return .notSupported("\(ref) 没有\(param.label)（只有输出有）") }
        let tm = tmState.stripTarget(tm0, param)
        let target = param.clamp(value)
        let stereo = param != .stereo && (tm != tm0 || (!param.isPerSide && tmState.isStereo(tm) == true))
        let change = PendingStripChange(id: UUID(), target: .channel(ref: ref, tm: tm, param: param),
                                        tmName: tmState.names[tm], stereo: stereo, old: nil, new: target)
        return stage(change) { tmState.stripValue(tm, param) ?? (param == .stereo ? 0 : nil) }
    }

    /// 暂存一条发送的声像（-1…+1）。只能改已有的发送。
    @discardableResult
    public func stageSendPan(source: ChannelRef, destination: ChannelRef, pan: Double) -> StageError? {
        guard lastLoaded != nil else { return .notLoaded }
        guard deviceID(of: destination) == "xt" else { return .notTotalMix }
        guard let s0 = tmChannel(for: source) else { return .notMapped(source) }
        guard let o0 = tmChannel(for: destination) else { return .notMapped(destination) }
        let s = leftOfPair(s0), o = leftOfPair(o0)
        let key = TotalMixState.NodeKey(source: s, output: o)
        guard tmState.gainDB(key) != nil else { return .noSend }
        let change = PendingStripChange(id: UUID(), target: .sendPan(source: source, destination: destination, tmSource: s, tmOutput: o),
                                        tmName: nil, stereo: s != s0 || o != o0 || tmState.isStereo(s) == true,
                                        old: nil, new: TotalMixStripParam.balpan.clamp(pan))
        return stage(change) { tmState.nodePan(key) ?? 0 }
    }

    private func stage(_ change: PendingStripChange, current: () -> Double?) -> StageError? {
        var change = change
        if let i = pendingStrips.firstIndex(where: { $0.key == change.key }) {
            if PendingStripChange.same(change.param, pendingStrips[i].old, change.new) { pendingStrips.remove(at: i) }
            else { pendingStrips[i].new = change.new }
            return nil
        }
        guard let old = current() else { return .unknownCurrent(change.param.label) }
        guard !PendingStripChange.same(change.param, old, change.new) else { return nil }
        change.old = old
        pendingStrips.append(change)
        return nil
    }

    public func discardStrip(_ id: UUID) { pendingStrips.removeAll { $0.id == id } }

    /// 发送通道条改动并回读核对。只由 applyPending 调用。
    func applyStrips(_ strips: [PendingStripChange], adapter: TotalMixOSCAdapter, confirmation: UserConfirmation,
                     outcomes: inout [UUID: VerifyOutcome]) async -> [PendingStripChange] {
        var sent: [PendingStripChange] = []
        for c in strips {
            do { try await adapter.client.write(c.write, for: c.operation, confirmation: confirmation); sent.append(c) }
            catch { outcomes[c.id] = .failed("\(error)") }
        }
        var channels: [TotalMixChannel] = [], outputs: [TotalMixChannel] = []
        for c in sent {
            switch c.target {
            case let .channel(_, tm, p):
                channels.append(tm)
                if p == .stereo { channels.append(TotalMixChannel(tm.bus, tm.number + 1)) }   // 右声道的名字、配对也会变
            case let .sendPan(_, _, _, o): outputs.append(o)
            }
        }
        if !channels.isEmpty { _ = try? await adapter.client.refreshChannels(channels) }
        if !outputs.isEmpty { _ = try? await adapter.client.refreshSubmixes(outputs) }
        return sent
    }

    /// 回读核对（tmState 已更新后调用）。
    func verify(_ c: PendingStripChange) -> VerifyOutcome {
        let now: Double?
        switch c.target {
        case let .channel(_, tm, p): now = tmState.stripValue(tm, p)
        case let .sendPan(_, _, s, o): now = tmState.nodePan(.init(source: s, output: o))
        }
        guard let now else { return .notReadBack }
        return PendingStripChange.same(c.param, now, c.new) ? .verified : .mismatchValue(readBack: c.param.text(now))
    }

    /// 撤销用：把改动的旧值重新暂存。
    func stageUndo(_ c: PendingStripChange) {
        guard let old = c.old else { return }
        switch c.target {
        case let .channel(ref, _, p): stageStrip(ref, p, old)
        case let .sendPan(s, d, _, _): stageSendPan(source: s, destination: d, pan: old)
        }
    }
}

extension AppModel {
    /// 打开了送电脑录音、占用录音通道 n 的输出（第 7.8 节）；没有则为 nil。
    public func loopbackSource(recording n: Int) -> XTStrip? {
        xtStrips(.output).first { o in
            guard let ref = o.ref, (stripValue(ref, .loopback) ?? 0) >= 0.5 else { return false }
            return o.tm.number == n || (o.stereo && o.tm.number + 1 == n)
        }
    }
}
