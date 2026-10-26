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

    /// 一次抬高超过 20 dB 且目标高于 -20 dB（“关”按 -65 dB 计，第 7.4 节）。
    public var isLargeJump: Bool {
        let o = oldDB ?? TotalMixFader.offThresholdDB, n = newDB ?? TotalMixFader.offThresholdDB
        return n - o > AppModel.largeJumpDB && n > -20   // 目标很小声（如新建发送 -30 dB）不算
    }

    public var key: Key { Key(source: tmSource, output: tmOutput) }
    public struct Key: Hashable, Sendable { var source: TotalMixChannel; var output: TotalMixChannel }

    public static func format(_ dB: Double?) -> String {
        dB.map { String(format: "%.1f dB", $0) } ?? "关"
    }

    func label(_ ch: TotalMixChannel, _ name: String?) -> String { name.map { "\(ch)（\($0)）" } ?? "\(ch)" }
    public var totalMixLabel: String { "\(label(tmSource, tmSourceName)) → \(label(tmOutput, tmOutputName))" }
}

/// 一条待应用的前级改动（文档第 7.2 节）：XT 走 TotalMix，12Mic 走 JSON。
public struct PendingPreampChange: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var deviceID: String          // "xt"、"12mic" 或 "xtc"
    public var input: ChannelRef         // xt.mic.in:1、12mic.analog.in:3
    public var tmInput: TotalMixChannel? // 仅 XT
    public var label: String             // 界面名：标签或 “Mic n”
    public var field: PreampField
    public var old: PreampValue?
    public var new: PreampValue
    /// 仅 XTC：MIDI 设备 ID（确认框原文用）。
    public var xtcMidiDeviceID: Int? = nil

    /// 打开 48V：确认框必须先勾选“没有接带式话筒等设备”。
    public var needsPhantomAck: Bool { field == .phantom && new == .flag(true) }

    /// 切换 48V（开或关）：快速方式下也要确认（第 7.4 节）。
    public var isPhantomChange: Bool { field == .phantom }

    /// 增益一次抬高超过 20 dB。
    public var isLargeJump: Bool {
        guard case let .gain(n) = new else { return false }
        if case let .gain(o)? = old { return n - o > AppModel.largeJumpDB }
        return false
    }

    public var operation: PlannedOperation {
        PlannedOperation(id: id, deviceID: deviceID, parameter: parameter, oldValue: old?.text,
                         newValue: new.text, access: .readWrite)
    }

    /// 写入的地址：XT 为 OSC 地址，12Mic 为 JSON 路径。
    public var parameter: String {
        if let tm = tmInput { return TotalMixWrite.preamp(input: tm, field: field, value: new).message.address }
        if deviceID == "xtc" { return XTCMIDIAdapter.preampParameter(channel: input.channel, field: field) }
        return TwelveMicWriteGate.parameter(channel: input.channel, field: field)
    }

    /// 确认框里显示的原文。
    public var wireText: String {
        if let tm = tmInput { return "OSC：" + TotalMixWrite.preamp(input: tm, field: field, value: new).message.description }
        if let id = xtcMidiDeviceID {
            return XTCMIDIAdapter.preampWireText(channel: input.channel, field: field, value: new, midiDeviceID: id)
        }
        guard let body = TwelveMicWriteGate.preampBody(channel: input.channel, field: field, value: new),
              let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "JSON：（无效）" }
        return "JSON：" + text
    }

    var key: String { "\(deviceID)|\(input)|\(field.rawValue)" }
}

/// 一条待应用的 12Mic 路由改动（文档第 7.3 节）：一个输出通道换来源（nil = 断开）。
public struct PendingRouteChange: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var destination: ChannelRef   // 12mic.madi_optical.out:9
    public var jsonOutPort: String       // madi_optical
    public var old: ChannelRef?
    public var new: ChannelRef?
    public var newJSONInPort: String?    // analog

    public var parameter: String { TwelveMicWriteGate.routeParameter(outPort: jsonOutPort, outChannel: destination.channel) }

    public var operation: PlannedOperation {
        PlannedOperation(id: id, deviceID: "12mic", parameter: parameter, oldValue: Self.text(old), newValue: Self.text(new),
                         access: .readWrite)
    }

    /// 目标是耳机：直接影响监听音量。
    public var isPhones: Bool { jsonOutPort == "phones" }

    public var wireText: String {
        let src = newJSONInPort.map { ($0, new?.channel ?? 1) }
        guard let body = TwelveMicWriteGate.routeBody(outPort: jsonOutPort, outChannel: destination.channel, source: src),
              let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "JSON：（无效）" }
        return "JSON：" + text
    }

    public static func text(_ ref: ChannelRef?) -> String { ref?.description ?? "断开" }
}

public enum VerifyOutcome: Equatable, Sendable {
    case verified
    case mismatch(readBack: Double?)
    case mismatchValue(readBack: String)
    case notReadBack
    case failed(String)

    public var text: String {
        switch self {
        case .verified: return "已核对"
        case let .mismatch(r): return "回读不一致：\(PendingChange.format(r))"
        case let .mismatchValue(r): return "回读不一致：\(r)"
        case .notReadBack: return "未回读到"
        case let .failed(e): return "发送失败：\(e)"
        }
    }
}

public struct AppliedBatch: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var date: Date
    public var changes: [PendingChange]
    public var preamps: [PendingPreampChange] = []
    public var routes: [PendingRouteChange] = []
    public var xtcRoutes: [PendingXTCRouteChange] = []
    public var strips: [PendingStripChange] = []
    public var globals: [PendingGlobalChange] = []
    public var outcomes: [UUID: VerifyOutcome]

    public var count: Int { changes.count + preamps.count + routes.count + xtcRoutes.count + strips.count + globals.count }
    public var verifiedCount: Int { outcomes.values.filter { $0 == .verified }.count }
}

public enum StageError: Error, Equatable {
    case notMapped(ChannelRef)
    case notTotalMix
    case notLoaded
    case notConnected(String)
    case unknownCurrent(String)
    case notSupported(String)
    case noSend

    public var text: String {
        switch self {
        case let .notMapped(r): return "\(r) 在 TotalMix 对照表里找不到，不能写入"
        case .notTotalMix: return "只有 \(mainFullName)（TotalMix）上的发送可以修改"
        case .notLoaded: return "还没有从 TotalMix 读取"
        case let .notConnected(d): return "\(d) 没有读到，不能写入"
        case let .unknownCurrent(f): return "读不到当前的\(f)，不能写入（先读一次设备）"
        case let .notSupported(t): return t
        case .noSend: return "这里还没有发送；先“送一路声音”，再调声像"
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
    public func discardAll() {
        pending.removeAll(); pendingPreamps.removeAll(); pendingRoutes.removeAll(); pendingXTCRoutes.removeAll()
        pendingStrips.removeAll(); pendingGlobals.removeAll()
    }

    static func same(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return abs(x - y) < 0.05
        default: return false
        }
    }

    // MARK: 应用

    // MARK: 前级暂存（第 7.2 节）

    /// 暂存一个前级字段的改动。改回原值时移除。
    @discardableResult
    public func stagePreamp(deviceID: String, input: ChannelRef, field: PreampField, value: PreampValue) -> StageError? {
        var value = value
        if case let .gain(g) = value {
            let r = PreampField.gainRange(device: deviceID)
            value = .gain(min(max(g, r.lowerBound), r.upperBound))
        }
        // 静音、AutoSet、PAD / Inst 只有 XTC 的前级写入接受（文档第 6.3 节）
        guard !field.xtcOnly || deviceID == "xtc" else { return .notSupported("\(field.label)只能在 XTC 上改") }
        var tmInput: TotalMixChannel? = nil
        switch deviceID {
        case "xt":
            guard lastLoaded != nil else { return .notLoaded }
            guard let tm = tmChannel(for: input), tm.bus == .input else { return .notMapped(input) }
            tmInput = tm
        case "12mic":
            guard twelveMicStatus == .live else { return .notConnected("12Mic") }
        case "xtc":
            guard xtcWritable else { return .notConnected("XTC（未允许本 App 改动）") }
            if case let .gain(g) = value { value = .gain(XTCMicSettings.effectiveGain(g)) }
        default:
            return .notConnected(deviceID)
        }
        guard let preamp = snapshot.devices[deviceID]?.preamps.first(where: { $0.input == input }),
              let old = preamp.value(field) else { return .unknownCurrent(field.label) }

        let key = "\(deviceID)|\(input)|\(field.rawValue)"
        if let i = pendingPreamps.firstIndex(where: { $0.key == key }) {
            if Self.same(pendingPreamps[i].old, value) { pendingPreamps.remove(at: i) } else { pendingPreamps[i].new = value }
            return nil
        }
        guard !Self.same(old, value) else { return nil }
        let label = preamp.label.knownValue.flatMap { $0.isEmpty ? nil : $0 } ?? "Mic \(input.channel)"
        pendingPreamps.append(PendingPreampChange(id: UUID(), deviceID: deviceID, input: input, tmInput: tmInput,
                                                  label: label, field: field, old: old, new: value,
                                                  xtcMidiDeviceID: deviceID == "xtc" ? xtcSettings.midiDeviceID : nil))
        return nil
    }

    /// 某个前级字段在待应用栏里的目标值。
    public func pendingPreamp(deviceID: String, input: ChannelRef, field: PreampField) -> PreampValue? {
        pendingPreamps.first { $0.deviceID == deviceID && $0.input == input && $0.field == field }?.new
    }

    public func discardPreamp(_ id: UUID) { pendingPreamps.removeAll { $0.id == id } }

    static func same(_ a: PreampValue?, _ b: PreampValue?) -> Bool {
        switch (a, b) {
        case let (.gain(x)?, .gain(y)?): return abs(x - y) < 0.05
        default: return a == b
        }
    }

    public var hasPending: Bool {
        !pending.isEmpty || !pendingPreamps.isEmpty || !pendingRoutes.isEmpty || !pendingXTCRoutes.isEmpty
            || !pendingStrips.isEmpty || !pendingGlobals.isEmpty
    }

    public var pendingCount: Int {
        pending.count + pendingPreamps.count + pendingRoutes.count + pendingXTCRoutes.count + pendingStrips.count
            + pendingGlobals.count
    }

    /// 待应用改动对应的全部计划操作（确认凭证按它签发）。
    public var allPendingOperations: [PlannedOperation] {
        pending.map(\.operation) + pendingPreamps.map(\.operation) + pendingRoutes.map(\.operation)
            + pendingXTCRoutes.map(\.operation) + pendingStrips.map(\.operation) + pendingGlobals.map(\.operation)
    }

    // MARK: 12Mic 路由暂存（第 7.3 节）

    /// 12Mic 某输出通道当前的来源（读回的路由）；nil = 没有路由。
    public func twelveMicSource(of destination: ChannelRef) -> ChannelRef? {
        snapshot.devices["12mic"]?.routes.first { $0.destination == destination }?.source
    }

    /// 把 12Mic 某输出通道改成 source（nil = 断开）。改回原值时移除。
    @discardableResult
    public func stageTwelveMicRoute(destination: ChannelRef, source: ChannelRef?) -> StageError? {
        guard twelveMicStatus == .live else { return .notConnected("12Mic") }
        let outMap = TwelveMicJSONAdapter.defaultPortMap, inMap = TwelveMicJSONAdapter.defaultInputPortMap
        guard let outPort = outMap.first(where: { $0.value == destination.portID })?.key,
              TwelveMicWriteGate.routeOutputs[outPort]?.contains(destination.channel) == true else { return .notMapped(destination) }
        var inPort: String? = nil
        if let source {
            guard let p = inMap.first(where: { $0.value == source.portID })?.key,
                  TwelveMicWriteGate.routeInputs[p]?.contains(source.channel) == true else { return .notMapped(source) }
            inPort = p
        }
        if let i = pendingRoutes.firstIndex(where: { $0.destination == destination }) {
            if pendingRoutes[i].old == source { pendingRoutes.remove(at: i) }
            else { pendingRoutes[i].new = source; pendingRoutes[i].newJSONInPort = inPort }
            return nil
        }
        let old = twelveMicSource(of: destination)
        guard old != source else { return nil }
        pendingRoutes.append(PendingRouteChange(id: UUID(), destination: destination, jsonOutPort: outPort,
                                                old: old, new: source, newJSONInPort: inPort))
        return nil
    }

    /// 某输出通道在待应用栏里的目标来源：外层 nil = 没有待应用改动；内层 nil = 断开。
    public func pendingTwelveMicRoute(_ destination: ChannelRef) -> ChannelRef?? {
        pendingRoutes.first { $0.destination == destination }.map(\.new)
    }

    public func discardRoute(_ id: UUID) { pendingRoutes.removeAll { $0.id == id } }

    /// “送一路声音”在 12Mic 上可选的来源：已登记输入口的全部通道。
    public var twelveMicRouteSources: [ChannelRef] {
        TwelveMicJSONAdapter.defaultInputPortMap.sorted { $0.key < $1.key }.flatMap { json, portID in
            (TwelveMicWriteGate.routeInputs[json] ?? 1 ... 0).map { ChannelRef(portID, $0) }
        }
    }

    /// 可写的 12Mic 输出通道。
    public var twelveMicRouteOutputs: [ChannelRef] {
        TwelveMicJSONAdapter.defaultPortMap.sorted { $0.key < $1.key }.flatMap { json, portID in
            (TwelveMicWriteGate.routeOutputs[json] ?? 1 ... 0).map { ChannelRef(portID, $0) }
        }
    }

    // MARK: 应用

    // MARK: 确认方式（第 7.4 节）

    /// 快速方式下仍要确认的改动（第 7.4 节，2026-10-26 收窄）：切换 48V，或一次抬高超过 20 dB。
    public var needsExplicitConfirmation: Bool {
        pending.contains(where: \.isLargeJump) || pendingPreamps.contains { $0.isPhantomChange || $0.isLargeJump }
            || pendingStrips.contains { $0.isLargeJump || $0.isLoopbackOn }
            || pendingGlobals.contains { $0.isSnapshot || $0.isMainOutChange }
    }

    /// 界面暂存改动后调用。快速方式下：需要明确确认的打开确认框，其余立即发送（用户这一下点击即确认）。
    /// 每次确认方式下什么也不做。只应由界面操作调用。
    public func commitIfQuick() async {
        guard confirmMode == .quick, hasPending, !isApplying else { return }
        if needsExplicitConfirmation {
            showConfirm = true
            return
        }
        _ = await applyPending(confirmation: ConfirmationGate.userConfirmed(allPendingOperations))
    }

    /// 按确认框签发的凭证发送全部待应用改动（发送电平 + 前级），回读核对，记入历史。只应由确认框的“确认发送”调用。
    public func applyPending(confirmation: UserConfirmation) async -> AppliedBatch? {
        guard hasPending, !isApplying else { return nil }
        isApplying = true
        defer { isApplying = false }

        let changes = pending, preamps = pendingPreamps, strips = pendingStrips, globals = pendingGlobals
        var outcomes: [UUID: VerifyOutcome] = [:]

        // 1. XT：发送电平与 XT 前级都经 TotalMix
        var sentSends: [PendingChange] = [], sentXT: [PendingPreampChange] = [], sentStrips: [PendingStripChange] = []
        var sentGlobals: [PendingGlobalChange] = []
        let xtPreamps = preamps.filter { $0.deviceID == "xt" }
        if let adapter {
            for c in changes {
                do { try await adapter.client.write(c.write, for: c.operation, confirmation: confirmation); sentSends.append(c) }
                catch { outcomes[c.id] = .failed("\(error)") }
            }
            for p in xtPreamps {
                guard let tm = p.tmInput else { outcomes[p.id] = .failed("没有 TotalMix 通道"); continue }
                do {
                    try await adapter.client.write(.preamp(input: tm, field: p.field, value: p.new), for: p.operation,
                                                   confirmation: confirmation)
                    sentXT.append(p)
                } catch { outcomes[p.id] = .failed("\(error)") }
            }
            sentStrips = await applyStrips(strips, adapter: adapter, confirmation: confirmation, outcomes: &outcomes)
            sentGlobals = await applyGlobals(globals, adapter: adapter, confirmation: confirmation, outcomes: &outcomes)
            if !sentSends.isEmpty { _ = try? await adapter.client.refreshSubmixes(sentSends.map(\.tmOutput)) }
            if !sentXT.isEmpty { _ = try? await adapter.client.refreshChannels(sentXT.compactMap(\.tmInput)) }
            if !sentSends.isEmpty || !sentXT.isEmpty || !sentStrips.isEmpty || !sentGlobals.isEmpty {
                await captureTotalMixState(from: adapter)
                apply(xt: TotalMixOSCAdapter.makeSnapshot(
                    deviceID: "xt", state: tmState, map: adapter.channelMap,
                    controlPath: ControlPath(controller: "this-app", transport: .osc(host: settings.host, port: settings.port),
                                             state: .online, active: true),
                    observedAt: Date()))
            }
        } else {
            for c in changes { outcomes[c.id] = .failed("TotalMix 未连接") }
            for p in xtPreamps { outcomes[p.id] = .failed("TotalMix 未连接") }
            for c in strips { outcomes[c.id] = .failed("TotalMix 未连接") }
            for c in globals { outcomes[c.id] = .failed("TotalMix 未连接") }
        }
        for c in sentStrips { outcomes[c.id] = verify(c) }
        for c in sentGlobals { outcomes[c.id] = verify(c) }
        for c in sentSends {
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
        for p in sentXT { outcomes[p.id] = verify(p) }

        // 2. 12Mic 前级与路由经 JSON
        let micPreamps = preamps.filter { $0.deviceID == "12mic" }
        let routes = pendingRoutes
        if !routes.isEmpty {
            if let url = URL(string: twelveMicURL), url.host != nil {
                let mic = makeTwelveMic(url)
                var sent: [PendingRouteChange] = []
                for r in routes {
                    do {
                        try await mic.writeRoute(destination: r.destination, source: r.new, for: r.operation, confirmation: confirmation)
                        sent.append(r)
                    } catch { outcomes[r.id] = .failed("\(error)") }
                }
                if !sent.isEmpty, let readBack = try? await mic.readRoutes() {
                    var devices = snapshot.devices
                    devices["12mic"]?.routes = readBack
                    replaceDevices(devices)
                    for r in sent {
                        let now = readBack.first { $0.destination == r.destination }?.source
                        outcomes[r.id] = now == r.new ? .verified : .mismatchValue(readBack: PendingRouteChange.text(now))
                    }
                } else {
                    for r in sent { outcomes[r.id] = .notReadBack }
                }
            } else {
                for r in routes { outcomes[r.id] = .failed("12Mic 地址无效") }
            }
        }
        if !micPreamps.isEmpty {
            if let url = URL(string: twelveMicURL), url.host != nil {
                let mic = makeTwelveMic(url)
                var sent: [PendingPreampChange] = []
                for p in micPreamps {
                    do {
                        try await mic.writePreamp(channel: p.input.channel, field: p.field, value: p.new,
                                                  for: p.operation, confirmation: confirmation)
                        sent.append(p)
                    } catch { outcomes[p.id] = .failed("\(error)") }
                }
                if !sent.isEmpty, let readBack = try? await mic.readPreamps() {
                    var devices = snapshot.devices
                    devices["12mic"]?.preamps = readBack
                    replaceDevices(devices)
                }
                for p in sent { outcomes[p.id] = verify(p) }
            } else {
                for p in micPreamps { outcomes[p.id] = .failed("12Mic 地址无效") }
            }
        }

        // 3. XTC 前级与路由经 MIDI SysEx（第 6.3 节）
        let xtcRoutes = pendingXTCRoutes
        await applyXTC(preamps: preamps.filter { $0.deviceID == "xtc" }, routes: xtcRoutes,
                       confirmation: confirmation, outcomes: &outcomes)

        let batch = AppliedBatch(date: Date(), changes: changes, preamps: preamps, routes: routes, xtcRoutes: xtcRoutes,
                                 strips: strips, globals: globals, outcomes: outcomes)
        history.insert(batch, at: 0)
        pending.removeAll()
        pendingPreamps.removeAll()
        pendingRoutes.removeAll()
        pendingXTCRoutes.removeAll()
        pendingStrips.removeAll()
        pendingGlobals.removeAll()
        return batch
    }

    /// 前级回读核对：快照里该字段的当前值是否等于目标值。
    func verify(_ p: PendingPreampChange) -> VerifyOutcome {
        guard let now = snapshot.devices[p.deviceID]?.preamps.first(where: { $0.input == p.input })?.value(p.field) else {
            return .notReadBack
        }
        return Self.same(now, p.new) ? .verified : .mismatchValue(readBack: now.text)
    }

    /// 撤销一批：把已发出的改动的旧值做成新的待应用改动（仍需确认）。
    public func stageUndo(_ batch: AppliedBatch) {
        for c in batch.changes {
            if case .failed = batch.outcomes[c.id] { continue }
            stageGain(source: c.source, destination: c.destination, dB: c.oldDB)
        }
        for p in batch.preamps {
            if case .failed = batch.outcomes[p.id] { continue }
            guard let old = p.old else { continue }
            stagePreamp(deviceID: p.deviceID, input: p.input, field: p.field, value: old)
        }
        for r in batch.routes {
            if case .failed = batch.outcomes[r.id] { continue }
            stageTwelveMicRoute(destination: r.destination, source: r.old)
        }
        for c in batch.strips {
            if case .failed = batch.outcomes[c.id] { continue }
            stageUndo(c)
        }
        // 开关可撤销；快照调用不可撤销（之前的整套状态没有保存）
        for c in batch.globals where !c.isSnapshot {
            if case .failed = batch.outcomes[c.id] { continue }
            if c.output != nil {
                // 选择项撤销：选回原来的输出（原来未指定的不能撤销，没有出处说 -1 可写）
                if let old = c.old, old >= 0 { stageMonitor(c.control, output: TotalMixChannel(.output, Int(old.rounded()) + 1)) }
            } else {
                stageGlobal(c.control, on: !c.on)
            }
        }
        for r in batch.xtcRoutes {
            if case .failed = batch.outcomes[r.id] { continue }
            guard let old = r.oldSource else { continue }
            stageXTCRoute(destination: r.destination, source: old)
        }
    }
}
