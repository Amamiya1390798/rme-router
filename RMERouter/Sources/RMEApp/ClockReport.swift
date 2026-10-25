import Foundation
import RMECore
import RMEEngine

/// 时钟页的一台设备（文档第 3 节痛点 6）：采样率、时钟源、各数字输入的 Lock/Sync。
public struct ClockDeviceRow: Identifiable, Equatable, Sendable {
    public struct Input: Identifiable, Equatable, Sendable {
        public var portID: String
        public var portName: String
        /// 这根线从哪来，例如“MADIface XT 的 MADI 1 输出”；没接线为 nil。
        public var upstream: String?
        public var lock: Fact<Bool>?
        public var sync: Fact<Bool>?
        public var id: String { portID }
    }

    public var deviceID: String
    public var deviceName: String
    public var rate: Fact<Int>?
    /// 时钟源的说明；读不到为 nil。
    public var sourceText: String?
    public var isMaster: Bool?
    public var inputs: [Input]
    /// 设备自报的时钟状态（12Mic soundness）。
    public var soundness: String?
    /// 读不到时去哪里人工确认。
    public var manualHint: String
    public var id: String { deviceID }

    public var rateKnown: Bool { rate?.knownValue != nil }
}

public enum ClockReport {
    /// 读不到时的人工确认方法（XT 的 Global OSC 没有时钟地址；XTC 没有可读协议）。
    static let hints: [String: String] = [
        "xt": "TotalMix 的 Global OSC 读不到时钟：在 TotalMix 的 Settings（选项 → 设置）里查看 Sample Rate 与 Clock Source。",
        "12mic": "在 12Mic 的 CLOCK 页查看；或在“连接”页确认 12Mic 地址后点“读取设备”。",
        "xtc": "XTC 没有可读的控制协议：在面板 CLOCK 菜单查看采样率与时钟源。",
    ]

    public static func build(_ s: SystemSnapshot) -> [ClockDeviceRow] {
        // 参与时钟的设备：排除只做终端的 P16 系列（与体检规则一致）。
        s.topology.devices.filter { $0.model != .p16i && $0.model != .p16m }.map { d in
            let snap = s.devices[d.id]
            // 设备不可读（离线、演示数据）时，时钟一律当作读不到。
            let clock = snap?.reachable == true ? snap?.clock : nil
            let inputs = d.ports.filter { $0.direction == .input && [.madiOptical, .madiCoaxial, .adat].contains($0.type) }.map { p in
                ClockDeviceRow.Input(portID: p.id, portName: p.name, upstream: upstream(of: p.id, in: s),
                                     lock: clock?.lock[p.id], sync: clock?.sync[p.id])
            }
            return ClockDeviceRow(
                deviceID: d.id, deviceName: d.name,
                rate: clock?.configuredRate.knownValue == nil ? nil : clock?.configuredRate,
                sourceText: clock?.source.knownValue.map { describe($0, in: s) },
                isMaster: clock?.isMaster,
                inputs: inputs,
                soundness: snap?.settings["12mic.clock.soundness"]?.knownValue.map { state in
                    [state, snap?.settings["12mic.clock.soundnessCause"]?.knownValue].compactMap { $0 }.joined(separator: "：")
                },
                manualHint: hints[d.id] ?? "在设备面板上查看采样率与时钟源。")
        }
    }

    /// 时钟源的中文说明。
    static func describe(_ source: ClockSource, in s: SystemSnapshot) -> String {
        switch source {
        case .internal: return "内部时钟（主机）"
        case .wordClock: return "字时钟输入"
        case let .port(id):
            let name = s.topology.port(id)?.name ?? id
            if let up = upstream(of: id, in: s) { return "跟随\(name)（来自 \(up)）" }
            return "跟随\(name)（这个口没有登记接线）"
        }
    }

    /// 某输入口的上游：“设备名 的 端口名”。
    static func upstream(of portID: String, in s: SystemSnapshot) -> String? {
        guard let link = s.topology.links(into: portID).first, let from = s.topology.port(link.from) else { return nil }
        let device = s.topology.device(from.deviceID)?.name ?? from.deviceID
        return "\(device) 的 \(from.name)"
    }

    /// 顶部摘要用的体检规则：主时钟、采样率、从机时钟源、Lock/Sync。
    public static let summaryRules = ["R1", "R2", "R4", "R5"]

    public static func summary(_ s: SystemSnapshot) -> [RuleResult] {
        CheckupReport.build(s).filter { summaryRules.contains($0.id) }
            .sorted { summaryRules.firstIndex(of: $0.id)! < summaryRules.firstIndex(of: $1.id)! }
    }
}
