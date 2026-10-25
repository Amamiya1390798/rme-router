import Foundation
import RMECore
import RMEAdapters

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
