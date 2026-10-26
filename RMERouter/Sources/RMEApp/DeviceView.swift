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

/// P16 行的一格：P16 第 number 路，来自主卡输出 ref（TotalMix 输出条 output），送进来的发送来源名。
public struct P16Cell: Identifiable, Equatable, Sendable {
    public var number: Int
    public var ref: ChannelRef
    public var output: TotalMixChannel?
    public var sources: [String]
    public var id: Int { number }
}

/// 源头标签：verified 为 false 时路径上有演示数据（还没从设备读到）。
public struct OriginLabel: Equatable, Sendable {
    public var text: String
    public var verified: Bool
}

/// 一根要画的线缆：两端都用“锚点名”表示（面板接口 `conn:<id>`，或节点 `node:<id>`）。
public struct CableSpec: Identifiable, Equatable, Sendable {
    public var id: String
    public var from: String
    public var to: String
    public var type: PortType
    public var text: String
    public var issues: [String]
    /// 核对状态：false 时画虚线（只是接线表里的声明）。
    public var verified: Bool = true
}

extension AppModel {
    /// TotalMix 某一行的通道条：按序号排列，立体声右声道并进左声道，没名字的（隐藏通道）不列。
    /// 按 TotalMix 读到的全部通道号列出（没名字的也列，例如拆开后的右声道），用位置给出名字。
    public func xtStrips(_ bus: TotalMixBus) -> [XTStrip] {
        let names = tmState.names
        let numbers = Set(tmState.channels.keys.filter { $0.bus == bus }.map(\.number))
        guard let maxN = numbers.max(), maxN >= 1 else { return [] }
        return (1 ... maxN).compactMap { n in
            let ch = TotalMixChannel(bus, n)
            if n % 2 == 0, tmState.isStereo(TotalMixChannel(bus, n - 1)) == true { return nil }
            let ref: ChannelRef? = bus == .playback ? ChannelRef("xt.playback.in", n) : xtMap[ch]?.ref
            guard numbers.contains(n) || (bus != .playback && ref != nil) else { return nil }
            let name = names[ch] ?? ref.map(positionName) ?? "\(n)"
            return XTStrip(tm: ch, ref: ref, name: name, stereo: tmState.isStereo(ch) == true)
        }
    }

    /// 没有名字时按接口给名字：“AES 2”“MADI 1·10”“Mic 2”。
    func positionName(_ ref: ChannelRef) -> String {
        let iface = ref.portID.split(separator: ".").dropFirst().first.map(String.init) ?? ref.portID
        switch iface {
        case "mic": return "Mic \(ref.channel)"
        case "aes": return "AES \(ref.channel)"
        case "an": return "AN \(ref.channel)"
        case "phones": return "PH \(ref.channel)"
        case "playback": return "回放 \(ref.channel)"
        default: return iface.hasPrefix("madi") ? "MADI \(iface.dropFirst(4))·\(ref.channel)" : ref.description
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

    /// P16 行（文档第 6.4.6 节）：P16 第 n 路 = 接到 P16 的主卡 ADAT 输出第 n 路（ADAT A 1–8、B 9–16）。
    /// 接线里没有“主卡 ADAT 输出 → P16”时返回 nil（例如 XT 档案经 XTC 送过去）。
    public func p16Cells() -> [P16Cell]? {
        guard studioConfig.has("p16i") else { return nil }
        let links = snapshot.topology.links
        var tmOf: [ChannelRef: TotalMixChannel] = [:]
        for (ch, e) in xtMap.entries where ch.bus == .output { tmOf[e.ref] = ch }
        var cells: [P16Cell] = []
        for (k, inPort) in ["p16i.adat_a.in", "p16i.adat_b.in"].enumerated() {
            guard let l = links.first(where: { $0.to == inPort }), l.from.hasPrefix("xt.adat"), l.from.hasSuffix(".out") else { continue }
            let n = snapshot.topology.port(l.from)?.singleSpeedChannels ?? 8
            for c in stride(from: 1, through: min(n, 8), by: 1) {
                let ref = ChannelRef(l.from, c)
                let tm = tmOf[ref]
                // 立体声对的右声道：发送记在左声道上
                let key = tm.map { t in t.number % 2 == 0 && tmState.isStereo(TotalMixChannel(.output, t.number - 1)) == true
                    ? TotalMixChannel(.output, t.number - 1) : t }
                let sources = key.map { o in
                    tmState.nodes.keys.filter { $0.output == o && tmState.gainDB($0) != nil }
                        .sorted { $0.source < $1.source }
                        .map { tmState.names[$0.source] ?? $0.source.description }
                } ?? []
                cells.append(P16Cell(number: k * 8 + c, ref: ref, output: key, sources: sources))
            }
        }
        return cells.isEmpty ? nil : cells
    }

    /// 通道的简短名字：“12Mic Mic 1”“XTC MADI 输入 9”。
    public func shortName(_ ref: ChannelRef) -> String {
        let topo = snapshot.topology
        guard let port = topo.port(ref.portID) else { return ref.description }
        let device = topo.device(port.deviceID)?.name ?? port.deviceID
        let ch = ref.portID.hasSuffix(".mic.in") || ref.portID.hasSuffix(".analog.in") ? "Mic \(ref.channel)" : "\(port.name) \(ref.channel)"
        return "\(device) \(ch)"
    }

    /// XT 全部输入通道沿接线和路由追到底的源头（第 6.4.3 节“麦克风去向”），按快照版本缓存。
    /// 路径上有一步是演示数据（证据 unknown），标签标为未核对；源头就是自己的不列。
    public func originLabels(_ refs: [ChannelRef]) -> [ChannelRef: OriginLabel] {
        if originCache?.version != snapshotVersion {
            let trace = SignalTrace(snapshot: snapshot)
            var all: [ChannelRef: OriginLabel] = [:]
            let inputs = snapshot.topology.devices.first { $0.id == "xt" }?.ports.filter { $0.direction == .input && $0.type != .usb } ?? []
            for port in inputs {
                for ch in stride(from: 1, through: port.singleSpeedChannels, by: 1) {   // 0 路的口（通用主卡没读到前）不能写 1 ... 0
                    let ref = ChannelRef(port.id, ch)
                    let paths = trace.upstream(to: ref).filter { $0.first?.hop.from != ref }
                    let origins = Set(paths.compactMap { $0.first?.hop.from }).sorted()
                    guard !origins.isEmpty else { continue }
                    // 已核对：路由不是演示数据，且经过的每根线都核对过（信号或用户确认）
                    let verified = paths.allSatisfy { $0.allSatisfy { step in
                        if case let .cable(f, t) = step.hop { return linkVerifications[LinkVerification.key(f.portID, t.portID)] != nil }
                        return step.evidence != .unknown
                    } }
                    all[ref] = OriginLabel(text: "← " + origins.prefix(2).map(shortName).joined(separator: "、") + (origins.count > 2 ? " 等" : ""),
                                           verified: verified)
                }
            }
            originCache = (snapshotVersion, all)
        }
        let labels = originCache!.labels
        return Dictionary(uniqueKeysWithValues: refs.compactMap { r in labels[r].map { (r, $0) } })
    }

    /// 某条发送当前的电平（读回）；nil = 没有这条发送。
    public func xtSend(from source: TotalMixChannel, to output: TotalMixChannel) -> Double? {
        tmState.gainDB(.init(source: source, output: output))
    }

    /// 端口有没有信号：任一通道最近有电平即为有；收不到电平时为 nil（无法判断）。
    public func hasSignal(port portID: String) -> Bool? {
        guard meters.live else { return nil }
        return meters.active.contains { $0.portID == portID }
    }

    /// 一个通道有没有信号；收不到电平时为 nil。
    public func hasSignal(_ ref: ChannelRef) -> Bool? {
        guard meters.live else { return nil }
        return meters.active.contains(ref)
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
            let status = cableStatus(l)
            return CableSpec(id: l.id, from: a, to: b, type: p.type, text: "\(name(l.from)) → \(name(l.to))",
                             issues: (issues[l.id] ?? []).map(\.description), verified: status != .declared)
        }
        // 主卡的 USB 口 → 这台 Mac（按当前主卡面板找 USB 接口；没有面板图的主卡不画）
        if let usb = PanelLayout.panel("xt", .rear)?.connectors.first(where: { $0.kind == .computer && $0.name.contains("USB") }) {
            out.append(CableSpec(id: "usb", from: "conn:\(usb.id)", to: "node:mac", type: .usb,
                                 text: "\(StudioConfig.current.mainCard.deviceName) USB → 这台 Mac", issues: []))
        }
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

/// 通道条对应的源头话放（文档第 6.4.3 节“通道条上调增益”）。
public struct StripPreamp: Equatable, Sendable {
    public var deviceID: String
    public var preamp: PreampChannel
}

extension AppModel {
    /// 硬件输入条的源头话放：XT 自己的 Mic，或沿接线、路由追到的 12Mic / XTC 话放。追到多个话放时为 nil（避免改错）。
    public func stripPreamp(_ ref: ChannelRef) -> StripPreamp? {
        if stripPreampCache?.version != snapshotVersion {
            var byInput: [ChannelRef: StripPreamp] = [:]
            for (dev, d) in snapshot.devices {
                for p in d.preamps { byInput[p.input] = StripPreamp(deviceID: dev, preamp: p) }
            }
            let trace = SignalTrace(snapshot: snapshot)
            var map: [ChannelRef: StripPreamp] = [:]
            for s in xtStrips(.input) {
                guard let r = s.ref else { continue }
                if let direct = byInput[r] { map[r] = direct; continue }
                let origins = Set(trace.upstream(to: r).compactMap { $0.first?.hop.from }).filter { byInput[$0] != nil }
                if origins.count == 1, let o = origins.first { map[r] = byInput[o] }
            }
            stripPreampCache = (snapshotVersion, map)
        }
        return stripPreampCache?.map[ref]
    }
}
