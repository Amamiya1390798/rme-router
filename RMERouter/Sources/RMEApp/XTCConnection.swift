import Foundation
import RMECore
import RMEAdapters

/// XTC 连接设置（文档第 6.3 节“App 接入”）。全部默认关：不打开就不向 XTC 发任何消息。
public struct XTCSettings: Codable, Equatable, Sendable {
    /// XTC 发往电脑的 MIDI 端点（本 App 从这里收）。
    public var sourceName = ""
    /// 电脑发往 XTC 的 MIDI 端点（本 App 往这里发）。
    public var destinationName = ""
    /// XTC 面板 Options → General Settings 的 MIDI 设备 ID（0–7）。
    public var midiDeviceID = 0
    /// 打开后才向 XTC 发“请求全部参数”。
    public var readEnabled = false
    /// 用户确认 TotalMix Aux Device 与 MIDI Remote 没有在控制 XTC。
    public var auxDeviceOff = false
    /// 允许本 App 改动 XTC（需要上面两项）。
    public var writeEnabled = false

    public init() {}

    public var canWrite: Bool { readEnabled && auxDeviceOff && writeEnabled }
    public var endpointsChosen: Bool { !sourceName.isEmpty && !destinationName.isEmpty }
}

public enum XTCStatus: Equatable, Sendable {
    case off                  // 没打开“读取 XTC”：显示演示数据
    case loading
    case live
    case unreachable(String)
}

/// 一条待应用的 XTC 路由改动：一个 8 路输出块换来源块（文档第 6.3 节）。
public struct PendingXTCRouteChange: Identifiable, Equatable, Sendable {
    public var operation: PlannedOperation
    /// 输出块与来源块的首通道。
    public var destination: ChannelRef
    public var source: ChannelRef
    /// 原来的来源块首通道（撤销用）；来源没有登记端口时为 nil。
    public var oldSource: ChannelRef?
    public var wireText: String

    public var id: UUID { operation.id }
    public var title: String { "XTC 路由 \(destination.portID):\(destination.channel)–\(destination.channel + 7)" }
    public var changeText: String { "\(operation.oldValue ?? "?") → \(operation.newValue)" }
}

extension AppModel {
    /// 本 App 现在能改 XTC：用户允许，且这次读取成功。
    public var xtcWritable: Bool { xtcSettings.canWrite && xtcStatus == .live && xtcAdapter != nil }

    /// 从 XTC 读取一次（只发命令 10）。没打开“读取 XTC”时什么也不发，保留演示数据。
    public func refreshXTC() async {
        await stopRetiredXTC()
        guard xtcSettings.readEnabled else {
            dropXTCAdapter()
            await stopRetiredXTC()
            xtcStatus = .off
            restoreXTCDemo()
            return
        }
        guard xtcSettings.endpointsChosen else {
            xtcStatus = .unreachable("先在“设置 → 连接”选择 XTC 的 MIDI 输入和输出端点")
            return
        }
        xtcStatus = .loading
        let adapter = xtcAdapter ?? makeXTC(xtcSettings)
        xtcAdapter = adapter
        do {
            apply(xtc: try await adapter.snapshot())
        } catch {
            dropXTCAdapter()
            await stopRetiredXTC()
            xtcStatus = .unreachable("XTC 没有回应：检查 MIDI 端点、设备 ID（XTC 面板 Options → General Settings），以及 XTC 的 MIDI Sources 是否允许这个端口控制。")
            syncXTCCapability()
        }
    }

    /// 用读到的 XTC 快照替换演示数据，并按设置登记两条控制路径（R9 据此判断冲突）。
    public func apply(xtc: DeviceSnapshot) {
        var snap = xtc
        let endpoint = xtcSettings.destinationName
        snap.controlPaths = [
            ControlPath(controller: "this-app", transport: .coreMIDI(endpoint: endpoint), state: .online,
                        active: xtcSettings.canWrite),
            ControlPath(controller: "totalmix-aux", transport: .midiOverMadi(viaPort: "xtc.madi.in"), state: .notProbed,
                        active: !xtcSettings.auxDeviceOff),
        ]
        var devices = snapshot.devices
        devices["xtc"] = snap
        replaceDevices(devices)
        xtcStatus = .live
        syncXTCCapability()
    }

    func restoreXTCDemo() {
        guard let demo = StudioSetup.demoDevices()["xtc"] else { return }
        var devices = snapshot.devices
        devices["xtc"] = demo
        replaceDevices(devices)
        pendingXTCRoutes.removeAll()
        pendingPreamps.removeAll { $0.deviceID == "xtc" }
        syncXTCCapability()
    }

    func stopRetiredXTC() async {
        let old = xtcRetired
        xtcRetired = []
        for a in old { await a.client.stop() }
    }

    func dropXTCAdapter() {
        if let old = xtcAdapter { xtcRetired.append(old) }
        xtcAdapter = nil
    }

    /// XTC 路由能力：可写时“自动”，否则“人工”（跨设备送声据此决定步骤）。
    func syncXTCCapability() {
        let access: Access = xtcWritable ? .readWrite : .manual
        guard let i = snapshot.capabilities.firstIndex(where: { $0.deviceID == "xtc" }),
              snapshot.capabilities[i].access != access else { return }
        snapshot.capabilities[i].access = access
        snapshot.capabilities[i].grade = access == .readWrite ? .a : .a2
        snapshot.capabilities[i].reference = access == .readWrite
            ? "XTC MIDI SysEx 参数 14、16–19（第 6.3 节）"
            : "XTC Digital Routing：未允许本 App 改动 XTC，只能在面板上设置"
        if access != .readWrite {
            pendingXTCRoutes.removeAll()
            pendingPreamps.removeAll { $0.deviceID == "xtc" }
        }
    }

    // MARK: 路由暂存

    /// XTC 某输出块当前的来源块首通道。
    public func xtcSource(ofBlock destination: ChannelRef) -> ChannelRef? {
        snapshot.devices["xtc"]?.routes.first { $0.destination == destination }?.source
    }

    /// 把 XTC 的一个输出块改成来自 source 所在的块（两边都按块首通道）。改回原值时移除。
    @discardableResult
    public func stageXTCRoute(destination: ChannelRef, source: ChannelRef) -> StageError? {
        guard xtcWritable, let adapter = xtcAdapter, let current = snapshot.devices["xtc"] else { return .notConnected("XTC（未允许本 App 改动）") }
        let dst = ChannelRef(destination.portID, destination.block * 8 + 1)
        let src = ChannelRef(source.portID, source.block * 8 + 1)
        let change = RouteChange(domain: .xtc, source: src, destination: dst, kind: .blockAssign(size: 8))
        guard let op = adapter.plan(change, current: current).first, op.access == .readWrite else { return .notMapped(destination) }
        let old = xtcSource(ofBlock: dst)

        if let i = pendingXTCRoutes.firstIndex(where: { $0.destination == dst }) {
            if pendingXTCRoutes[i].oldSource == src { pendingXTCRoutes.remove(at: i); return nil }
            var op2 = op
            op2.oldValue = pendingXTCRoutes[i].operation.oldValue
            pendingXTCRoutes[i] = PendingXTCRouteChange(operation: op2, destination: dst, source: src,
                                                        oldSource: pendingXTCRoutes[i].oldSource,
                                                        wireText: Self.xtcRouteWire(op2, adapter))
            return nil
        }
        guard old != src else { return nil }
        pendingXTCRoutes.append(PendingXTCRouteChange(operation: op, destination: dst, source: src, oldSource: old,
                                                      wireText: Self.xtcRouteWire(op, adapter)))
        return nil
    }

    static func xtcRouteWire(_ op: PlannedOperation, _ adapter: XTCMIDIAdapter) -> String { adapter.routeWireText(op) }

    public func discardXTCRoute(_ id: UUID) { pendingXTCRoutes.removeAll { $0.id == id } }

    // MARK: 应用

    /// 发送 XTC 的前级与路由改动，再读一次核对。只由 applyPending 调用。
    func applyXTC(preamps: [PendingPreampChange], routes: [PendingXTCRouteChange],
                  confirmation: UserConfirmation, outcomes: inout [UUID: VerifyOutcome]) async {
        guard !preamps.isEmpty || !routes.isEmpty else { return }
        guard xtcWritable, let adapter = xtcAdapter else {
            for p in preamps { outcomes[p.id] = .failed("XTC 未连接或未允许改动") }
            for r in routes { outcomes[r.id] = .failed("XTC 未连接或未允许改动") }
            return
        }
        var sentP: [PendingPreampChange] = [], sentR: [PendingXTCRouteChange] = []
        for p in preamps {
            do {
                try await adapter.writePreamp(channel: p.input.channel, field: p.field, value: p.new,
                                              for: p.operation, confirmation: confirmation)
                sentP.append(p)
            } catch { outcomes[p.id] = .failed("\(error)") }
        }
        for r in routes {
            do { try await adapter.apply(r.operation, confirmation: confirmation); sentR.append(r) }
            catch { outcomes[r.id] = .failed("\(error)") }
        }
        guard !sentP.isEmpty || !sentR.isEmpty else { return }
        if let snap = try? await adapter.snapshot() {
            apply(xtc: snap)
            for p in sentP { outcomes[p.id] = verify(p) }
            for r in sentR {
                let now = xtcSource(ofBlock: r.destination)
                let label = snap.settings.first { $0.key.hasPrefix("\(r.destination.portID).\(r.destination.channel)-") }?.value.knownValue
                outcomes[r.id] = now == r.source ? .verified : .mismatchValue(readBack: label ?? "?")
            }
        } else {
            for p in sentP { outcomes[p.id] = .notReadBack }
            for r in sentR { outcomes[r.id] = .notReadBack }
        }
    }
}
