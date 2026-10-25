import Foundation
import RMECore
import RMEAdapters
import RMEEngine

/// “设备”页的数据（文档第 6.4 节）：TotalMix 式通道条、线缆两端、信号状态。界面无关，便于测试。
public struct XTStrip: Identifiable, Equatable, Sendable {
    public var tm: TotalMixChannel
    public var ref: ChannelRef?
    public var name: String
    /// 立体声：一条代表左右两个通道。
    public var stereo: Bool
    public var id: TotalMixChannel { tm }
}

/// 一根要画的线缆：两端都用“锚点名”表示（面板接口 `conn:<id>`，或节点 `node:<id>`）。
public struct CableSpec: Identifiable, Equatable, Sendable {
    public var id: String
    public var from: String
    public var to: String
    public var type: PortType
    public var text: String
    public var issues: [String]
}

extension AppModel {
    /// TotalMix 某一行的通道条：按序号排列，立体声右声道并进左声道，没名字的（隐藏通道）不列。
    public func xtStrips(_ bus: TotalMixBus) -> [XTStrip] {
        let names = tmState.names.filter { $0.key.bus == bus }
        return names.keys.sorted().compactMap { ch in
            if ch.number % 2 == 0, tmState.isStereo(TotalMixChannel(bus, ch.number - 1)) == true { return nil }
            let ref: ChannelRef? = bus == .playback ? ChannelRef("xt.playback.in", ch.number) : xtMap[ch]?.ref
            return XTStrip(tm: ch, ref: ref, name: names[ch] ?? "\(ch)", stereo: tmState.isStereo(ch) == true)
        }
    }

    /// 一个来源送到了哪些输出（读回的节点电平），按输出序号；立体声输出只列左声道那条。
    public func xtSends(from source: TotalMixChannel) -> [(output: TotalMixChannel, dB: Double)] {
        tmState.nodes.keys.filter { $0.source == source }.compactMap { key in
            guard let dB = tmState.gainDB(key) else { return nil }
            if key.output.number % 2 == 0, tmState.isStereo(TotalMixChannel(.output, key.output.number - 1)) == true { return nil }
            return (key.output, dB)
        }
        .sorted { $0.output < $1.output }
    }

    /// 通道的简短名字：“12Mic Mic 1”“XTC MADI 输入 9”。
    public func shortName(_ ref: ChannelRef) -> String {
        let topo = snapshot.topology
        guard let port = topo.port(ref.portID) else { return ref.description }
        let device = topo.device(port.deviceID)?.name ?? port.deviceID
        let ch = ref.portID.hasSuffix(".mic.in") || ref.portID.hasSuffix(".analog.in") ? "Mic \(ref.channel)" : "\(port.name) \(ref.channel)"
        return "\(device) \(ch)"
    }

    /// 这些通道沿接线和路由追到底的源头（第 6.4.3 节“麦克风去向”）；源头就是自己的不列。
    public func originLabels(_ refs: [ChannelRef]) -> [ChannelRef: String] {
        let trace = SignalTrace(snapshot: snapshot)
        var out: [ChannelRef: String] = [:]
        for ref in refs {
            let origins = Set(trace.upstream(to: ref).compactMap { $0.first?.hop.from }).filter { $0 != ref }.sorted()
            guard !origins.isEmpty else { continue }
            out[ref] = "← " + origins.prefix(2).map(shortName).joined(separator: "、") + (origins.count > 2 ? " 等" : "")
        }
        return out
    }

    /// 某条发送当前的电平（读回）；nil = 没有这条发送。
    public func xtSend(from source: TotalMixChannel, to output: TotalMixChannel) -> Double? {
        tmState.gainDB(.init(source: source, output: output))
    }

    /// 端口有没有信号：任一通道最近有电平即为有；收不到电平时为 nil（无法判断）。
    public func hasSignal(port portID: String) -> Bool? {
        guard meters.receiving() else { return nil }
        return meters.levels.contains { $0.key.portID == portID && $0.value > -60 }
    }

    /// 一个通道有没有信号；收不到电平时为 nil。
    public func hasSignal(_ ref: ChannelRef) -> Bool? {
        guard meters.receiving() else { return nil }
        return (meters.levels[ref] ?? -144) > -60
    }

    /// 要画的线缆：接线表里的每根线，加上 XT 到“这台 Mac”的 USB 线。只画两端在面板（或节点）上都找得到的。
    public func cables(face: PanelFace) -> [CableSpec] {
        guard face == .rear else { return [] }
        let topo = snapshot.topology
        func anchor(_ portID: String) -> String? {
            guard let port = topo.port(portID) else { return nil }
            if let (panel, c) = PanelLayout.connector(for: portID), panel.face == .rear { return "conn:\(c.id)" }
            return PanelLayout.all.contains { $0.deviceID == port.deviceID } ? nil : "node:\(port.deviceID)"
        }
        let issues = linkIssues
        var out: [CableSpec] = topo.links.compactMap { l in
            guard let a = anchor(l.from), let b = anchor(l.to), let p = topo.port(l.from) else { return nil }
            let name = { (id: String) in topo.port(id).map { "\(topo.device($0.deviceID)?.name ?? $0.deviceID) \($0.name)" } ?? id }
            return CableSpec(id: l.id, from: a, to: b, type: p.type, text: "\(name(l.from)) → \(name(l.to))",
                             issues: (issues[l.id] ?? []).map(\.description))
        }
        out.append(CableSpec(id: "usb", from: "conn:xt.usb", to: "node:mac", type: .usb, text: "MADIface XT USB 3 → 这台 Mac", issues: []))
        return out
    }
}

extension ChannelRef {
    /// 由 `端口:通道` 文字还原（拖放用）。
    public init?(text: String) {
        guard let i = text.lastIndex(of: ":"), let n = Int(text[text.index(after: i)...]) else { return nil }
        self.init(String(text[..<i]), n)
    }
}
