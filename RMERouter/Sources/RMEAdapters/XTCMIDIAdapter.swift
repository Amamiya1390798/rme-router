import Foundation
import RMECore

/// OctaMic XTC MIDI 适配器（骨架）。
///
/// 已查证（复核）：
/// - RME 发布 MIDI Remote 1.7 时称 XTC“所有功能”均可经 MIDI 或 MIDI over MADI 遥控，路由在 Options 面板（A2）。
/// - MIDI Remote 与 TotalMix FX Aux Device 不能同时控制 XTC（A2）。
/// - XTC 菜单里有 MIDI Sources：Control 输入只选一个来源（MADI In / USB / DIN），这是设备级的“单一控制输入”（B，论坛用户贴出的设置）。
/// - TotalMix Aux Device 能控的是增益、48V、PAD/Inst、AutoSet 等前级参数，不含 Digital Routing（A2）。
///
/// 未知（D）：SysEx 中路由与时钟参数的编号。须从 XTC 手册 MIDI 章节核对，或在 MIDI Remote 改路由时抓包。
public struct XTCMIDIAdapter: DeviceAdapter {
    public let deviceID: String
    public let domain = ControlDomain.xtc
    public let endpointName: String   // CoreMIDI 端点名，例如 USB 直连时的 XTC 端口

    public init(deviceID: String = "xtc", endpointName: String) {
        self.deviceID = deviceID
        self.endpointName = endpointName
    }

    public var capabilities: [Capability] {
        [
            Capability("preamp gain/48V/PAD/AutoSet", access: .readWrite, grade: .a2,
                       reference: "https://forum.rme-audio.de/viewtopic.php?pid=89093"),
            Capability("digital routing (ADAT/MADI/AES out source)", access: .unknown, grade: .a2,
                       reference: "https://forum.rme-audio.de/viewtopic.php?id=18893（可遥控，但协议编号未查到）"),
            Capability("SysEx parameter numbers", access: .unknown, grade: .d, reference: "XTC 手册 MIDI 章节，待核对"),
        ]
    }

    public func probe() async -> ControlPath {
        ControlPath(controller: "this-app", transport: .coreMIDI(endpoint: endpointName), state: .notProbed, active: false)
    }

    public func snapshot() async throws -> DeviceSnapshot {
        throw AdapterError.protocolUnknown("XTC SysEx 编号未查到；第一阶段先做被动抓包")
    }

    public func plan(_ change: RouteChange, current: DeviceSnapshot) -> [PlannedOperation] {
        let block = change.source.block
        return [PlannedOperation(deviceID: deviceID,
                                 parameter: "XTC Digital Routing: \(change.destination.portID) 块 \(change.destination.block + 1)",
                                 oldValue: current.settings["xtc.adatOut1.source"]?.knownValue,
                                 newValue: "\(change.source.portID) 通道 \(block * 8 + 1)-\(block * 8 + 8)",
                                 access: .manual)]
    }

    public func apply(_ op: PlannedOperation, confirmation: UserConfirmation) async throws {
        try precheck(op, confirmation)   // access 为 manual，这里一定抛 notWritable
    }

    public func verify(_ op: PlannedOperation) async throws -> VerificationResult { .unreadable }
}
