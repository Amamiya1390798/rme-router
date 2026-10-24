import Foundation
import RMECore
import RMEAdapters

/// 一条待应用的发送电平改动（文档第 7.1 节）。地址用链路表示法，同时记下 TotalMix 通道与名字供对照。
public struct PendingChange: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var source: ChannelRef
    public var destination: ChannelRef
    public var tmSource: TotalMixChannel
    public var tmOutput: TotalMixChannel
    public var tmSourceName: String?
    public var tmOutputName: String?
    /// nil = 关
    public var oldDB: Double?
    public var newDB: Double?
    /// 对照表两端中较弱的证据；inferred 时确认框要提示。
    public var mapEvidence: Evidence

    public var write: TotalMixWrite { .sendGain(source: tmSource, output: tmOutput, dB: newDB) }

    /// 与本改动一一对应的计划操作；id 相同，确认凭证按它签发。
    public var operation: PlannedOperation {
        PlannedOperation(id: id, deviceID: "xt", parameter: write.message.address,
                         oldValue: Self.format(oldDB), newValue: Self.format(newDB), access: .readWrite)
    }

    /// 抬高超过 10 dB 且目标高于 -20 dB（“关”按 -65 dB 计）。
    public var isLargeJump: Bool {
        let o = oldDB ?? TotalMixFader.offThresholdDB, n = newDB ?? TotalMixFader.offThresholdDB
        return n - o > 10 && n > -20
    }

    public var key: Key { Key(source: tmSource, output: tmOutput) }
    public struct Key: Hashable, Sendable { var source: TotalMixChannel; var output: TotalMixChannel }

    public static func format(_ dB: Double?) -> String {
        dB.map { String(format: "%.1f dB", $0) } ?? "关"
    }

    func label(_ ch: TotalMixChannel, _ name: String?) -> String { name.map { "\(ch)（\($0)）" } ?? "\(ch)" }
    public var totalMixLabel: String { "\(label(tmSource, tmSourceName)) → \(label(tmOutput, tmOutputName))" }
}

public enum VerifyOutcome: Equatable, Sendable {
    case verified
    case mismatch(readBack: Double?)
    case notReadBack
    case failed(String)

    public var text: String {
        switch self {
        case .verified: return "已核对"
        case let .mismatch(r): return "回读不一致：\(PendingChange.format(r))"
        case .notReadBack: return "未回读到"
        case let .failed(e): return "发送失败：\(e)"
        }
    }
}

public struct AppliedBatch: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var date: Date
    public var changes: [PendingChange]
    public var outcomes: [UUID: VerifyOutcome]
}

public enum StageError: Error, Equatable {
    case notMapped(ChannelRef)
    case notTotalMix
    case notLoaded

    public var text: String {
        switch self {
        case let .notMapped(r): return "\(r) 在 TotalMix 对照表里找不到，不能写入"
        case .notTotalMix: return "只有 MADIface XT（TotalMix）上的发送可以修改"
        case .notLoaded: return "还没有从 TotalMix 读取"
        }
    }
}

extension AppModel {
    // MARK: 反查

    /// 链路地址 → TotalMix 通道（只用对照表里的条目，不推算）。
    public func tmChannel(for ref: ChannelRef) -> TotalMixChannel? {
        if ref.portID == "xt.playback.in" { return TotalMixChannel(.playback, ref.channel) }
        return xtMap.entries.first { $0.value.ref == ref }?.key
    }

    /// 当前（读回的）节点电平；nil = 关或无此节点。
    public func currentGain(source: TotalMixChannel, output: TotalMixChannel) -> Double? {
        tmState.gainDB(.init(source: source, output: output))
    }

    /// 某条发送在待应用栏里的目标值：外层 nil = 没有待应用改动。
    public func pendingGain(source: ChannelRef, destination: ChannelRef) -> Double?? {
        pending.first { $0.source == source && $0.destination == destination }.map(\.newDB)
    }

    /// “送一路声音”可选的来源：对照表里有名字的 TotalMix 输入。
    public var sendSourceCandidates: [ChannelRef] {
        xtMap.entries.filter { $0.key.bus == .input }.map(\.value.ref).sorted()
    }

    // MARK: 暂存

    /// 把一条发送改到 dB（nil = 关）。改回原值时从待应用栏移除。
    @discardableResult
    public func stageGain(source: ChannelRef, destination: ChannelRef, dB: Double?) -> StageError? {
        guard lastLoaded != nil else { return .notLoaded }
        guard deviceID(of: destination) == "xt" else { return .notTotalMix }
        guard let tmSrc = tmChannel(for: source) else { return .notMapped(source) }
        guard let tmOut = tmChannel(for: destination) else { return .notMapped(destination) }
        let target = dB.flatMap { $0 <= TotalMixFader.offThresholdDB ? nil : min($0, TotalMixWrite.maxDB) }
        let key = PendingChange.Key(source: tmSrc, output: tmOut)

        if let i = pending.firstIndex(where: { $0.key == key }) {
            if Self.same(pending[i].oldDB, target) { pending.remove(at: i) } else { pending[i].newDB = target }
            return nil
        }
        let old = currentGain(source: tmSrc, output: tmOut)
        guard !Self.same(old, target) else { return nil }
        let weakest = [xtMap[tmSrc]?.evidence ?? .confirmed, xtMap[tmOut]?.evidence ?? .unknown]
            .min { $0.strength < $1.strength } ?? .unknown
        pending.append(PendingChange(
            id: UUID(), source: source, destination: destination, tmSource: tmSrc, tmOutput: tmOut,
            tmSourceName: tmState.names[tmSrc], tmOutputName: tmState.names[tmOut] ?? tmState.names[TotalMixChannel(.playback, tmOut.number)],
            oldDB: old, newDB: target, mapEvidence: weakest))
        return nil
    }

    /// “送一路声音”：新建发送，默认 -30 dB（安静起步，文档第 7.1 节）。
    @discardableResult
    public func stageNewSend(source: ChannelRef, destination: ChannelRef, dB: Double = -30) -> StageError? {
        stageGain(source: source, destination: destination, dB: dB)
    }

    public func discard(_ id: UUID) { pending.removeAll { $0.id == id } }
    public func discardAll() { pending.removeAll() }

    static func same(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return abs(x - y) < 0.05
        default: return false
        }
    }

    // MARK: 应用

    /// 按确认框签发的凭证发送全部待应用改动，回读核对，记入历史。只应由确认框的“确认发送”调用。
    public func applyPending(confirmation: UserConfirmation) async -> AppliedBatch? {
        guard let adapter, !pending.isEmpty, !isApplying else { return nil }
        isApplying = true
        defer { isApplying = false }

        let changes = pending
        var outcomes: [UUID: VerifyOutcome] = [:]
        var sent: [PendingChange] = []
        for c in changes {
            do {
                try await adapter.client.write(c.write, for: c.operation, confirmation: confirmation)
                sent.append(c)
            } catch {
                outcomes[c.id] = .failed("\(error)")
            }
        }
        _ = try? await adapter.client.refreshSubmixes(sent.map(\.tmOutput))
        await captureTotalMixState(from: adapter)
        for c in sent {
            let readBack = currentGain(source: c.tmSource, output: c.tmOutput)
            let hasNode = tmState.nodes[.init(source: c.tmSource, output: c.tmOutput)] != nil
            if !hasNode {
                outcomes[c.id] = c.newDB == nil ? .verified : .notReadBack
            } else if let want = c.newDB {
                outcomes[c.id] = readBack.map { abs($0 - want) <= 0.1 } == true ? .verified : .mismatch(readBack: readBack)
            } else {
                outcomes[c.id] = readBack == nil ? .verified : .mismatch(readBack: readBack)
            }
        }

        // 用回读后的状态重建 XT 快照。
        let xt = TotalMixOSCAdapter.makeSnapshot(
            deviceID: "xt", state: tmState, map: adapter.channelMap,
            controlPath: ControlPath(controller: "this-app", transport: .osc(host: settings.host, port: settings.port),
                                     state: .online, active: true),
            observedAt: Date())
        apply(xt: xt)

        let batch = AppliedBatch(date: Date(), changes: changes, outcomes: outcomes)
        history.insert(batch, at: 0)
        pending.removeAll()
        return batch
    }

    /// 撤销一批：把已发出的改动的旧值做成新的待应用改动（仍需确认）。
    public func stageUndo(_ batch: AppliedBatch) {
        for c in batch.changes {
            if case .failed = batch.outcomes[c.id] { continue }
            stageGain(source: c.source, destination: c.destination, dB: c.oldDB)
        }
    }
}
