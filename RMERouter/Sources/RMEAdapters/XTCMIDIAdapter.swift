import Foundation
import RMECore

/// OctaMic XTC MIDI 适配器（文档第 6.3 节）。
///
/// - 协议出处（A）：XTC 手册第 29 章 SysEx。
/// - 读取：发“请求全部参数”（命令 10），不改设备。
/// - 写入：只有用户在“连接”页打开“由本 App 控制 XTC”（`controlEnabled`）才可写；
///   XTC 的 MIDI 控制输入只选一个来源，与 TotalMix Aux Device / MIDI Remote 互斥（A2），所以默认关闭。
public struct XTCMIDIAdapter: DeviceAdapter {
    public let deviceID: String
    public let domain = ControlDomain.xtc
    public let client: XTCClient
    public let endpointName: String
    public let controlEnabled: Bool

    static let manualURL = "https://www.rme-audio.de/downloads/octamicxtc_e.pdf 第 29 章"

    public init(deviceID: String = "xtc", client: XTCClient, endpointName: String, controlEnabled: Bool) {
        self.deviceID = deviceID
        self.client = client
        self.endpointName = endpointName
        self.controlEnabled = controlEnabled
    }

    public var capabilities: [Capability] {
        let w: Access = controlEnabled ? .readWrite : .readOnly
        return [
            Capability("preamp gain/phase/48V", access: w, grade: .a, reference: "\(Self.manualURL)，参数 0–7"),
            Capability("digital routing (ADAT/MADI out source)", access: w, grade: .a, reference: "\(Self.manualURL)，参数 14、16–19"),
            Capability("clock source / sample rate / Lock/Sync", access: .readOnly, grade: .a, reference: "\(Self.manualURL)，参数 21、25"),
            Capability("SysEx reply framing (3 bytes per param)", access: .readOnly, grade: .c, reference: "按手册推断，待实机核对"),
        ]
    }

    public func probe() async -> ControlPath {
        let ok = (try? await client.readAll()) != nil
        return ControlPath(controller: "this-app", transport: .coreMIDI(endpoint: endpointName),
                           state: ok ? .online : .offline, active: controlEnabled)
    }

    public func snapshot() async throws -> DeviceSnapshot {
        let state: XTCState
        do { state = try await client.readAll() } catch { throw AdapterError.unreachable }
        let path = ControlPath(controller: "this-app", transport: .coreMIDI(endpoint: endpointName),
                               state: .online, active: controlEnabled)
        return Self.snapshot(state, deviceID: deviceID, controlPath: path, observedAt: Date())
    }

    /// 状态 → 快照（纯函数，便于测试）。
    public static func snapshot(_ s: XTCState, deviceID: String, controlPath: ControlPath, observedAt: Date) -> DeviceSnapshot {
        let src = { (ref: String) in FactSource(deviceID: deviceID, interface: "xtc-midi", reference: ref, observedAt: observedAt) }

        let source: ClockSource? = s.clockSource.flatMap { c in
            switch c {
            case 0: return .internal
            case 1: return .wordClock
            case 2 ... 5: return .port("\(deviceID).aes\(c - 1).in")
            case 6: return .port("\(deviceID).adat.in")
            case 7: return .port("\(deviceID).madi.in")
            default: return nil
            }
        }
        var lock: [String: Fact<Bool>] = [:], sync: [String: Fact<Bool>] = [:]
        if let l = s.madiLock { lock["\(deviceID).madi.in"] = .confirmed(l, src("sysex 25 LSB bit 5")) }
        if let y = s.madiSync { sync["\(deviceID).madi.in"] = .confirmed(y, src("sysex 25 MSB bit 5")) }
        let clock = ClockState(
            configuredRate: s.sampleRate.map { .confirmed($0, src("sysex 21 MSB")) } ?? .unknown(src("sysex 21")),
            source: source.map { .confirmed($0, src("sysex 21 LSB")) } ?? .unknown(src("sysex 21")),
            lock: lock, sync: sync)

        var formats: [String: Fact<StreamFormat>] = [:]
        if let rate = s.sampleRate, let m64 = s.madi64, let f48 = s.madiFrame48k {
            let fmt = StreamFormat(sampleRate: rate, madiFrame: f48 ? .frame48k : .frame96k, channelMode: m64 ? .ch64 : .ch56)
            for port in ["\(deviceID).madi.out", "\(deviceID).madi.in"] { formats[port] = .confirmed(fmt, src("sysex 21/22")) }
        }

        // 每个输出块的来源都记一条设置，包括没有登记端口的来源（ADAT IN、AES IN、电脑回放）。
        var settings: [String: Fact<String>] = [:]
        for (out, from) in s.routing {
            settings["\(out.port(deviceID: deviceID)).\(out.firstChannel)-\(out.firstChannel + 7).source"] =
                .confirmed(from.label, src("sysex \(out.index) \(out.isLSB ? "LSB" : "MSB")"))
        }

        let preamps = s.mics.keys.sorted().map { n -> PreampChannel in
            let m = s.mics[n]!
            let r = "sysex \(n - 1)"
            return PreampChannel(input: ChannelRef("\(deviceID).mic.in", n),
                                 label: .unknown(src(r)),
                                 gainDB: .confirmed(m.gainDB, src(r)),
                                 phantom: .confirmed(m.phantom, src(r)),
                                 phase: .confirmed(m.phase, src(r)),
                                 hiZ: .confirmed(n >= 5 && m.padOrInstrument, src(r)),
                                 autoGain: .confirmed(m.autoSet, src(r)),
                                 gainGroup: .confirmed(m.group == 0 ? "无" : "\(m.group)", src(r)))
        }

        return DeviceSnapshot(deviceID: deviceID, reachable: true, clock: clock, portFormats: formats,
                              routes: s.routes(deviceID: deviceID), controlPaths: [controlPath],
                              settings: settings, preamps: preamps)
    }

    // MARK: - 写入（路由）

    /// 一次块分配的参数地址，例如 "sysex/16/lsb"。
    static func parameter(_ out: XTCRoutingOutput) -> String { "sysex/\(out.index)/\(out.isLSB ? "lsb" : "msb")" }

    public func plan(_ change: RouteChange, current: DeviceSnapshot) -> [PlannedOperation] {
        // 块分配不改块内偏移（第 6.1 节不变量 5）。
        guard change.source.offsetInBlock == change.destination.offsetInBlock,
              let out = XTCRoutingOutput(portID: change.destination.portID, channel: change.destination.channel, deviceID: deviceID),
              let from = XTCRoutingSource(firstChannel: ChannelRef(change.source.portID, change.source.block * 8 + 1), deviceID: deviceID)
        else { return [] }
        let key = "\(out.port(deviceID: deviceID)).\(out.firstChannel)-\(out.firstChannel + 7).source"
        return [PlannedOperation(deviceID: deviceID, parameter: Self.parameter(out),
                                 oldValue: current.settings[key]?.knownValue, newValue: from.label,
                                 access: controlEnabled ? .readWrite : .manual)]
    }

    public func apply(_ op: PlannedOperation, confirmation: UserConfirmation) async throws {
        try precheck(op, confirmation)
        guard controlEnabled else { throw AdapterError.notWritable(op.parameter) }
        guard let (out, from) = Self.decode(op) else { throw AdapterError.badResponse(op.parameter) }
        try await client.set([out.setParam(from)])
    }

    public func verify(_ op: PlannedOperation) async throws -> VerificationResult {
        guard let (out, from) = Self.decode(op) else { return .unreadable }
        guard let state = try? await client.readAll() else { return .unreadable }
        guard let now = state.routing[out] else { return .unreadable }
        return now == from ? .matches : .differs(readBack: now.label)
    }

    // MARK: - 写入（前级）

    /// 前级参数地址，例如 "sysex/0/gain"。
    public static func preampParameter(channel: Int, field: PreampField) -> String { "sysex/\(channel - 1)/\(field.rawValue)" }

    /// 确认框里显示的原文。
    public static func preampWireText(channel: Int, field: PreampField, value: PreampValue, midiDeviceID: Int) -> String {
        guard let p = XTCMicSettings.setParam(mic: channel, field: field, value: value),
              let bytes = try? XTCSysEx.set([p], device: midiDeviceID) else { return "SysEx：（无效）" }
        return "SysEx：" + XTCSysEx.hex(bytes)
    }

    /// 改一路前级（mic 1…8）。需要确认凭证覆盖 op，且已允许本 App 改动 XTC。
    public func writePreamp(channel: Int, field: PreampField, value: PreampValue,
                            for op: PlannedOperation, confirmation: UserConfirmation) async throws {
        try precheck(op, confirmation)
        guard controlEnabled, (1 ... 8).contains(channel), op.parameter == Self.preampParameter(channel: channel, field: field),
              let p = XTCMicSettings.setParam(mic: channel, field: field, value: value) else {
            throw AdapterError.notWritable(op.parameter)
        }
        if case let .gain(g) = value, !PreampField.gainRange.contains(g) { throw AdapterError.notWritable(op.parameter) }
        try await client.set([p])
    }

    /// 路由改动的原文。
    public func routeWireText(_ op: PlannedOperation) -> String {
        guard let (out, from) = Self.decode(op), let bytes = try? XTCSysEx.set([out.setParam(from)], device: client.midiDeviceID)
        else { return "SysEx：（无效）" }
        return "SysEx：" + XTCSysEx.hex(bytes)
    }

    static func decode(_ op: PlannedOperation) -> (XTCRoutingOutput, XTCRoutingSource)? {
        guard let out = XTCRoutingOutput.all.first(where: { parameter($0) == op.parameter }),
              let from = (0 ... 15).compactMap(XTCRoutingSource.init(value:)).first(where: { $0.label == op.newValue })
        else { return nil }
        return (out, from)
    }
}
