import SwiftUI
import RMECore
import RMEAdapters

/// “设备”页（文档第 6.4.3 节）：三台设备的前后面板、实物线缆、XT 的 TotalMix 式通道条。
struct DevicesView: View {
    @Bindable var model: AppModel
    @State private var face: PanelFace = .rear
    @State private var selected: String?
    @State private var onlySignal = false
    @State private var identifying = false

    private var selectedConnector: (DevicePanel, PanelConnector)? {
        guard let id = selected else { return nil }
        for p in PanelLayout.all { if let c = p.connectors.first(where: { $0.id == id }) { return (p, c) } }
        return nil
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.l) {
                    header
                    RackView(model: model, face: face, selected: $selected)
                    ControlRoomBar(model: model)
                    XTStripsView(model: model, onlySignal: onlySignal)
                }
                .padding(Tokens.Space.xl)
                .frame(minWidth: 600, alignment: .leading)
            }
            if let (panel, c) = selectedConnector {
                Divider()
                ConnectorDetail(model: model, panel: panel, connector: c) { selected = nil }
                    .frame(width: 280)
            }
        }
        .background(Tokens.Palette.bg)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Tokens.Space.m) {
            ViewHeader(title: "设备", subtitle: "实物接口与线缆。点一个接口只看它自己的线；下面是 XT 的通道条，用法同 TotalMix。")
            Picker("面", selection: $face) { ForEach(PanelFace.allCases) { Text($0.title).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                .onChange(of: face) { selected = nil }
            Button("信号核对…") { identifying = true }
                .help("对着一支麦克风说话，看它实际进了 XT 的哪一路，核对接线")
                .sheet(isPresented: $identifying) { IdentifySheet(model: model) { identifying = false } }
            Toggle("只看有信号", isOn: $onlySignal).toggleStyle(.checkbox)
                .disabled(!model.meters.live)
                .help(model.meters.live ? "只列最近有电平的通道条" : "收不到电平（XT 未连接，或 TotalMix 没勾 Send Level Data）")
        }
    }
}

// MARK: - 机架

/// 锚点：面板接口 `conn:<id>`、节点 `node:<id>`、每一行 `row:<n>`。
struct RackAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

struct RackView: View {
    var model: AppModel
    var face: PanelFace
    @Binding var selected: String?

    /// 选中接口时：与它有线相连的接口（这些不变暗）。
    private var linked: Set<String> {
        guard let s = selected else { return [] }
        let key = "conn:\(s)"
        return Set(model.cables(face: face).flatMap { c in c.from == key || c.to == key ? [c.from, c.to] : [] })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 64) {
            unit("12mic").transformAnchorPreference(key: RackAnchorKey.self, value: .bounds) { $0["row:0"] = $1 }
            HStack(alignment: .center, spacing: Tokens.Space.l) {
                unit("xt").frame(maxWidth: 560)
                MacNodeCard(model: model)
                    .transformAnchorPreference(key: RackAnchorKey.self, value: .bounds) { $0["node:mac"] = $1 }
                NodeCard(title: "Behringer P16-I", lines: ["ADAT A 输入", "ADAT B 输入"], color: Color(hex: 0x6AA6C9))
                    .transformAnchorPreference(key: RackAnchorKey.self, value: .bounds) { $0["node:p16i"] = $1 }
                Spacer(minLength: 0)
            }
            .transformAnchorPreference(key: RackAnchorKey.self, value: .bounds) { $0["row:1"] = $1 }
            unit("xtc").transformAnchorPreference(key: RackAnchorKey.self, value: .bounds) { $0["row:2"] = $1 }
        }
        .padding(.top, Tokens.Space.l)
        .overlayPreferenceValue(RackAnchorKey.self) { anchors in
            GeometryReader { g in
                CableLayer(cables: model.cables(face: face), anchors: anchors.mapValues { g[$0] },
                           selected: selected.map { "conn:\($0)" })
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private func unit(_ deviceID: String) -> some View {
        if let panel = PanelLayout.panel(deviceID, face) {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                HStack(spacing: Tokens.Space.s) {
                    Text(model.snapshot.topology.device(deviceID)?.name ?? deviceID).font(Tokens.Font.cardTitle)
                    if model.isDemo(deviceID) { Badge(text: "演示数据", color: Tokens.Palette.unknown) }
                }
                PanelView(panel: panel, selected: selected, linked: linked, signal: { model.hasSignal(port: $0) }) { c in
                    selected = selected == c.id ? nil : c.id
                }
            }
        }
    }
}

/// 一块面板：官方产品图 + 可点的接口热区。
struct PanelView: View {
    var panel: DevicePanel
    var selected: String?
    var linked: Set<String>
    var signal: (String) -> Bool?
    var onSelect: (PanelConnector) -> Void

    var body: some View {
        Group {
            if let img = PanelLayout.image(panel.image) {
                Image(nsImage: img).resizable().aspectRatio(panel.aspect, contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Tokens.Palette.surface).aspectRatio(panel.aspect, contentMode: .fit)
                    .overlay(Text("面板图缺失").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted))
            }
        }
        .overlay {
            GeometryReader { g in
                ForEach(panel.connectors) { c in
                    hotspot(c, diameter: g.size.width * c.size)
                        .position(x: g.size.width * c.x, y: g.size.height * c.y)
                }
            }
        }
    }

    private func hotspot(_ c: PanelConnector, diameter d: CGFloat) -> some View {
        let isSel = selected == c.id
        let hasSig = c.ports.contains { signal($0) == true }
        return Circle()
            .strokeBorder(isSel ? Tokens.Palette.accent : (linked.contains("conn:\(c.id)") ? Tokens.Palette.accent.opacity(0.5) : .clear), lineWidth: 2)
            .background(Circle().fill(Color.white.opacity(0.001)))
            .overlay(alignment: .topTrailing) {
                if hasSig { Circle().fill(Tokens.Palette.ok).frame(width: 7, height: 7).shadow(color: Tokens.Palette.ok, radius: 3) }
            }
            .frame(width: d, height: d)
            .contentShape(Circle())
            .anchorPreference(key: RackAnchorKey.self, value: .bounds) { ["conn:\(c.id)": $0] }
            .onTapGesture { onSelect(c) }
            .help(c.routes ? c.name : "\(c.name)（不参与路由）")
    }
}

struct NodeCard: View {
    var title: String
    var lines: [String]
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(title).font(Tokens.Font.cardTitle)
            ForEach(lines, id: \.self) { l in
                HStack(spacing: Tokens.Space.xs) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(l).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                }
            }
        }
        .padding(Tokens.Space.m)
        .frame(width: 170, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(Tokens.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(Tokens.Palette.border))
    }
}

// MARK: - 线缆

/// 线缆：从接口垂直引出，在两行之间的缝里横走（每根线一条走道），再垂直进入目标。
struct CableLayer: View {
    var cables: [CableSpec]
    var anchors: [String: CGRect]
    var selected: String?

    static func color(_ t: PortType) -> Color {
        switch t {
        case .madiOptical: return Color(hex: 0xD97757)
        case .madiCoaxial: return Color(hex: 0xC9A46A)
        case .adat: return Color(hex: 0x6AA6C9)
        case .usb: return Color(hex: 0x9B8BD6)
        default: return Tokens.Palette.textMuted
        }
    }

    var body: some View {
        let rows = (0 ..< 3).compactMap { anchors["row:\($0)"] }
        let routed = Self.route(cables, anchors: anchors, rows: rows)
        ZStack {
            ForEach(routed, id: \.cable.id) { r in
                let on = selected == nil || r.cable.from == selected || r.cable.to == selected
                // 未核对（只是接线表里的声明）画虚线
                Self.path(r.points)
                    .stroke(Self.color(r.cable.type).opacity(on ? 0.95 : 0.12),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: r.cable.verified ? [] : [7, 5]))
                ForEach(Array([r.points.first!, r.points.last!].enumerated()), id: \.offset) { _, p in
                    Circle().fill(Self.color(r.cable.type).opacity(on ? 1 : 0.15)).frame(width: 8, height: 8).position(p)
                }
                if on, let warn = r.cable.issues.first {
                    // 没选中时只标 ⚠，避免同一问题的两根线文字叠在一起；选中这根线时写全
                    Text(selected == nil ? "⚠" : "⚠ \(warn)").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.warn)
                        .fixedSize().position(x: selected == nil ? r.points[1].x + 10 : r.labelAt.x, y: r.labelAt.y - 9)
                }
            }
        }
    }

    struct Routed { var cable: CableSpec; var points: [CGPoint]; var labelAt: CGPoint }

    static func route(_ cables: [CableSpec], anchors: [String: CGRect], rows: [CGRect]) -> [Routed] {
        guard rows.count == 3 else { return [] }
        func rowOf(_ y: CGFloat) -> Int? { rows.firstIndex { y >= $0.minY - 4 && y <= $0.maxY + 4 } }
        var lanes: [Int: Int] = [:]
        return cables.compactMap { c in
            guard let fa = anchors[c.from], let fb = anchors[c.to] else { return nil }
            let a = CGPoint(x: fa.midX, y: fa.midY)
            let toNode = c.to.hasPrefix("node:")
            let b = toNode ? CGPoint(x: fb.minX + 28, y: fb.maxY) : CGPoint(x: fb.midX, y: fb.midY)
            guard let ra = rowOf(a.y), let rb = rowOf(toNode ? fb.midY : b.y) else { return nil }
            let gap = min(ra == rb ? ra : min(ra, rb), 1)
            lanes[gap, default: 0] += 1
            let mid = (rows[gap].maxY + rows[gap + 1].minY) / 2
            let gy = mid + CGFloat(lanes[gap]! - 3) * 7
            return Routed(cable: c, points: [a, CGPoint(x: a.x, y: gy), CGPoint(x: b.x, y: gy), b],
                          labelAt: CGPoint(x: max(a.x, b.x) + 150, y: gy))
        }
    }

    /// 直角折线，拐角用圆角。
    static func path(_ pts: [CGPoint]) -> Path {
        Path { p in
            p.move(to: pts[0])
            for i in 1 ..< pts.count - 1 {
                p.addArc(tangent1End: pts[i], tangent2End: pts[i + 1], radius: 8)
            }
            p.addLine(to: pts[pts.count - 1])
        }
    }
}

// MARK: - 接口详情

struct ConnectorDetail: View {
    var model: AppModel
    var panel: DevicePanel
    var connector: PanelConnector
    var close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                HStack {
                    Text(connector.name).font(Tokens.Font.cardTitle).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Tokens.Palette.textMuted)
                }
                Text(verbatim: "\(model.snapshot.topology.device(panel.deviceID)?.name ?? panel.deviceID) · \(panel.face.title)")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                if !connector.routes {
                    Text(explain).font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(connector.ports, id: \.self) { portSection($0) }
            }
            .padding(Tokens.Space.l)
        }
        .background(Tokens.Palette.surface)
    }

    private var explain: String {
        switch connector.kind {
        case .clock: return "字时钟接口，不参与路由。时钟状态在“时钟”页。"
        case .computer: return "连接电脑的接口，不参与路由。"
        default: return "电源、网络或控制接口，不参与路由，只用来对照实物。"
        }
    }

    @ViewBuilder private func portSection(_ portID: String) -> some View {
        let topo = model.snapshot.topology
        if let port = topo.port(portID) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text(verbatim: "\(port.name)（\(port.direction == .input ? "输入" : "输出")，\(port.singleSpeedChannels) 路）")
                    .font(Tokens.Font.body.weight(.semibold))
                Text(verbatim: portID).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
                let links = topo.links.filter { $0.from == portID || $0.to == portID }
                if links.isEmpty {
                    Text("未接线").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                }
                ForEach(links, id: \.id) { l in
                    let other = l.from == portID ? l.to : l.from
                    let status = model.cableStatus(l)
                    Text(verbatim: "⇄ \(topo.port(other).map { "\(topo.device($0.deviceID)?.name ?? "") \($0.name)" } ?? other)")
                        .font(Tokens.Font.caption)
                    HStack(spacing: Tokens.Space.xs) {
                        EvidenceDot(status == .declared ? .inferred : .confirmed)
                        Text(status.text).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if status == .declared || status == .lockSeen {
                        Button("我对照实物确认过了") { model.confirmLinkByUser(l) }
                            .font(Tokens.Font.caption).buttonStyle(.link)
                            .help("最好先用“信号核对”；这里只在无法用信号核对时使用")
                    }
                    ForEach((model.linkIssues[l.id] ?? []).map(\.description), id: \.self) {
                        Text("⚠ \($0)").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.warn)
                    }
                }
                channelGrid(port)
            }
        }
    }

    /// 通道格：8 列；有路由的格实心，有信号的格绿色。点一格在检查器里看这一路。
    private func channelGrid(_ port: RMECore.Port) -> some View {
        let n = connector.channel.map { _ in 1 } ?? port.singleSpeedChannels
        let first = connector.channel ?? 1
        let routed = Set(model.snapshot.allRoutes().flatMap { [$0.source, $0.destination] }.filter { $0.portID == port.id }.map(\.channel))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 8), spacing: 3) {
            ForEach(first ..< first + n, id: \.self) { ch in
                let ref = ChannelRef(port.id, ch)
                let sig = model.hasSignal(ref) == true
                Button {
                    model.inspect(ref)
                    model.showInspector = true
                } label: {
                    Text("\(ch)").font(.system(size: 9, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 18)
                        .background(RoundedRectangle(cornerRadius: 3).fill(
                            sig ? Tokens.Palette.ok.opacity(0.45) : routed.contains(ch) ? Tokens.Palette.border : Tokens.Palette.bg))
                        .foregroundStyle(routed.contains(ch) || sig ? Tokens.Palette.text : Tokens.Palette.textMuted)
                }
                .buttonStyle(.plain)
                .help("\(ref.description)：点开看完整去向")
            }
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
