import Foundation
import RMECore
import RMEAdapters

/// 一条待应用的控制室 / 全局静音 / 快照改动（文档第 7.9 节）。
public struct PendingGlobalChange: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var control: TotalMixGlobal
    public var old: Double?
    /// 开关的目标值；快照调用固定为 true。
    public var on: Bool
    /// 主输出 / 耳机：选的输出（左声道）；开关项为 nil。
    public var output: TotalMixChannel? = nil
    /// 选的输出的名字（界面用）。
    public var outputName: String? = nil

    public var write: TotalMixWrite {
        if let output { return .controlSelect(control, output: output) }
        return .global(control, on: on)
    }

    public var operation: PlannedOperation {
        PlannedOperation(id: id, deviceID: "xt", parameter: write.message.address,
                         oldValue: control.text(old), newValue: newText, access: .readWrite)
    }

    public var isSnapshot: Bool { if case .snapshot = control { return true } else { return false } }
    public var newText: String {
        if let output { return outputName.map { "\($0)（输出 \(output.number)）" } ?? "输出 \(output.number)" }
        return isSnapshot ? "调用" : (on ? "开" : "关")
    }
    public var title: String { control.label }
    public var changeText: String { isSnapshot ? "整套混音换成快照里的" : "\(control.text(old)) → \(newText)" }
    public var wireText: String { "OSC：" + write.message.description }

    /// 值得提醒：调用快照（整套替换），或取消全局静音（会突然出声）。只在确认框里标出，快速方式下不拦（第 7.4 节）。
    public var needsExplicit: Bool { isSnapshot || isMainOutChange || isGlobalUnmute }

    /// 改主输出：监听声音换到另一对音箱（第 7.9 节），一律确认。
    public var isMainOutChange: Bool { control == .mainOut }
    var isGlobalUnmute: Bool { control == .globalMute && !on && (old ?? 0) >= 0.5 }
}

extension AppModel {
    /// 控制室开关的当前值（读回）；没收到为 nil。
    public func globalValue(_ g: TotalMixGlobal) -> Double? { tmState.globalValue(g) }

    public func pendingGlobal(_ g: TotalMixGlobal) -> PendingGlobalChange? { pendingGlobals.first { $0.control == g } }

    /// 读到的快照编号（1…8 中 TotalMix 报过状态的），以及哪个是当前。
    public var snapshots: [(number: Int, state: Double)] {
        (1 ... 8).compactMap { n in tmState.globalValue(.snapshot(n)).map { (n, $0) } }
    }

    /// 暂存一个控制室开关；改回原值时移除。快照用 `stageSnapshot`。
    @discardableResult
    public func stageGlobal(_ g: TotalMixGlobal, on: Bool) -> StageError? {
        guard lastLoaded != nil else { return .notLoaded }
        if case .snapshot = g { return stageSnapshot(0) }
        guard let old = globalValue(g) else { return .unknownCurrent(g.label) }
        if let i = pendingGlobals.firstIndex(where: { $0.control == g }) {
            if (old >= 0.5) == on { pendingGlobals.remove(at: i) } else { pendingGlobals[i].on = on }
            return nil
        }
        guard (old >= 0.5) != on else { return nil }
        pendingGlobals.append(PendingGlobalChange(id: UUID(), control: g, old: old, on: on))
        return nil
    }

    /// 暂存“调用快照 n”（1…8）。同时只留一个快照调用。
    @discardableResult
    public func stageSnapshot(_ n: Int) -> StageError? {
        guard lastLoaded != nil else { return .notLoaded }
        guard (1 ... 8).contains(n) else { return .notSupported("快照编号只有 1–8") }
        pendingGlobals.removeAll(where: \.isSnapshot)
        pendingGlobals.append(PendingGlobalChange(id: UUID(), control: .snapshot(n), old: globalValue(.snapshot(n)), on: true))
        return nil
    }

    /// 暂存主输出 / 耳机选择（第 7.9 节）；选回当前值时移除。
    @discardableResult
    public func stageMonitor(_ g: TotalMixGlobal, output: TotalMixChannel) -> StageError? {
        guard lastLoaded != nil else { return .notLoaded }
        guard g.isSelection, output.bus == .output else { return .notSupported("只能给主输出、耳机选硬件输出") }
        guard let old = globalValue(g) else { return .unknownCurrent(g.label) }
        let target = tmState.stripTarget(output, .mute)   // 立体声写左声道
        pendingGlobals.removeAll { $0.control == g }
        guard Int(old.rounded()) != target.number - 1 else { return nil }
        pendingGlobals.append(PendingGlobalChange(id: UUID(), control: g, old: old, on: true, output: target,
                                                  outputName: tmState.names[target]))
        return nil
    }

    /// 主输出、耳机当前选的输出（左声道）；未指定为 nil。
    public func monitorOutput(_ g: TotalMixGlobal) -> TotalMixChannel? {
        guard let v = globalValue(g), v >= 0 else { return nil }
        return TotalMixChannel(.output, Int(v.rounded()) + 1)
    }

    /// 对讲话筒已在 TotalMix 里指定（talkchannel ≥ 0）。
    public var talkbackReady: Bool { (tmState.globals["controlroom/talkchannel"]?.number ?? -1) >= 0 }

    public func discardGlobal(_ id: UUID) { pendingGlobals.removeAll { $0.id == id } }

    /// 发送并回读。快照调用后整套状态都变了，整体重读一次。只由 applyPending 调用。
    func applyGlobals(_ changes: [PendingGlobalChange], adapter: TotalMixOSCAdapter, confirmation: UserConfirmation,
                      outcomes: inout [UUID: VerifyOutcome]) async -> [PendingGlobalChange] {
        var sent: [PendingGlobalChange] = []
        for c in changes {
            do { try await adapter.client.write(c.write, for: c.operation, confirmation: confirmation); sent.append(c) }
            catch { outcomes[c.id] = .failed("\(error)") }
        }
        if !sent.isEmpty { _ = try? await adapter.client.refreshAll() }
        return sent
    }

    /// 回读核对：开关等于目标；快照为“当前”或“已改动”（2 或 3）。
    func verify(_ c: PendingGlobalChange) -> VerifyOutcome {
        guard let now = globalValue(c.control) else { return .notReadBack }
        if c.isSnapshot { return now >= 1.5 ? .verified : .mismatchValue(readBack: c.control.text(now)) }
        if let o = c.output { return Int(now.rounded()) == o.number - 1 ? .verified : .mismatchValue(readBack: c.control.text(now)) }
        return (now >= 0.5) == c.on ? .verified : .mismatchValue(readBack: c.control.text(now))
    }
}
