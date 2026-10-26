import SwiftUI
import RMECore
import RMEAdapters

/// “设备”页（文档第 6.4.3、6.8 节）：顶部固定工具栏（面板收纳、前后、信号核对、通道条 / 信号流），
/// 下面依次是三台设备的面板与实物线缆、选中接口时的链路卡、XT 的 TotalMix 式通道条。接口详情在检查器里。
struct DevicesView: View {
    @Bindable var model: AppModel
    @AppStorage("devices.rackOpen") private var rackOpen = true
    @State private var face: PanelFace = .rear
    @State private var onlySignal = false
    @State private var identifying = false
    /// 链路卡：显示链上全部通道条（默认超过 8 路只看在用的）。
    @State private var showAll = false
    @State private var hoverEdge: StripFocus.Edge?
    /// 拖线的结果（第 6.4.4 节）。
    @State private var linkProposal: (from: String, to: String)?
    @State private var sendPreset: (from: ChannelRef, to: ChannelRef)?
    @State private var dragMessage: String?
    /// 搜索跳转（第 6.4.5 节）。
    @State private var jump: StripJump?
    @State private var searching = false

    var body: some View {
        let focus = focus
        VStack(spacing: 0) {
            toolbar.zIndex(1)   // 搜索结果浮在下面的内容上
            Divider()
            ScrollViewReader { page in
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.l) {
                    if let dragMessage {
                        Text(dragMessage).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.warn)
                    }
                    if rackOpen {
                        RackView(model: model, face: face, selected: Binding(get: { model.panelSelection }, set: select),
                                 highlightLinks: focus?.links) { a, b in
                            dragMessage = nil
                            switch model.dragIntent(from: a, to: b) {
                            case let .addLink(f, t): linkProposal = (f, t)
                            case let .send(f, t): sendPreset = (f, t)
                            case let .rejected(why): dragMessage = "拖不上：\(why)"
                            }
                        }
                    }
                    if let focus {
                        ChainCard(model: model, focus: focus, showAll: $showAll, hoverEdge: $hoverEdge) { select(nil) }
                    }
                    switch model.devicesPane {
                    case .strips:
                        ControlRoomBar(model: model)
                        XTStripsView(model: model, onlySignal: onlySignal, focus: focus, highlightEdge: hoverEdge,
                                     onFocusPick: narrow, jump: jump, allowSelectAll: !searching)
                            .equatable()
                            .id("strips")
                    case .signalFlow:
                        SignalFlowView(model: model)
                            .frame(height: 560)
                            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
                            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(Tokens.Palette.border))
                    }
                }
                .padding(Tokens.Space.xl)
                .frame(minWidth: 600, alignment: .leading)
            }
            .onChange(of: jump) {
                guard jump != nil else { return }
                DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.25)) { page.scrollTo("strips", anchor: .top) } }
            }
            }
        }
        .background(Tokens.Palette.bg)
        .onExitCommand { select(nil) }
        .onChange(of: model.panelSelection) { showAll = false; hoverEdge = nil }
        .confirmationDialog(linkProposal.map { "在接线表里加一根线：\(name($0.from)) ⇒ \(name($0.to))？" } ?? "",
                            isPresented: Binding(get: { linkProposal != nil }, set: { if !$0 { linkProposal = nil } })) {
            Button("加这根线") {
                if let p = linkProposal { dragMessage = model.addLink(from: p.from, to: p.to).map { "没加上：\($0)" } }
                linkProposal = nil
            }
            Button("取消", role: .cancel) { linkProposal = nil }
        } message: {
            Text("只改接线表（记录实物怎么接的），不会向设备发送任何东西。接好后可以用“信号核对”确认。")
        }
        .sheet(isPresented: Binding(get: { sendPreset != nil }, set: { if !$0 { sendPreset = nil } })) {
            if let p = sendPreset {
                SendAcrossSheet(model: model, initialSource: p.from, initialDest: p.to) { sendPreset = nil }
            }
        }
    }

    /// 点接口：选中它（详情进检查器），通道条高亮它的整条链；再点一次取消。
    private func select(_ id: String?) {
        model.panelChannel = nil
        model.panelSelection = id
        if id != nil { model.showInspector = true }
    }

    /// 选中接口时点了一条高亮的通道条：属于这个接口就只看这一路；否则退出接口选择，交给通道条照常选中。
    private func narrow(_ s: XTStrip) -> Bool {
        guard let ref = s.ref, let (_, c) = model.selectedConnector else { return false }
        if c.ports.contains(ref.portID), c.channel == nil {
            model.panelChannel = model.panelChannel == ref.channel ? nil : ref.channel
            model.inspect(ref)
            return true
        }
        select(nil)
        return false
    }

    private func name(_ portID: String) -> String {
        let topo = model.snapshot.topology
        return topo.port(portID).map { "\(topo.device($0.deviceID)?.name ?? $0.deviceID) \($0.name)" } ?? portID
    }

    /// 选中的接口在通道条上的链路（只看音频接口）。
    private var focus: StripFocus? {
        guard let (_, c) = model.selectedConnector, c.routes else { return nil }
        return model.stripFocus(connector: c, channel: model.panelChannel, activeOnly: showAll ? false : nil)
    }

    /// 顶部固定的一条：面板收纳、前后、信号核对；右边是通道条 / 信号流、只看有信号。
    private var toolbar: some View {
        HStack(spacing: Tokens.Space.m) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { rackOpen.toggle() }
            } label: {
                Label(rackOpen ? "收起面板" : "展开面板", systemImage: rackOpen ? "chevron.up" : "chevron.down")
            }
            .fixedSize()
            .help(rackOpen ? "收起设备面板，通道条占满页面" : "展开设备面板")
            if rackOpen {
                Picker("面", selection: $face) { ForEach(PanelFace.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .onChange(of: face) { select(nil) }
            }
            Button("信号核对…") { identifying = true }.fixedSize()
                .help("对着一支麦克风说话，看它实际进了 \(mainName) 的哪一路，核对接线")
                .sheet(isPresented: $identifying) { IdentifySheet(model: model) { identifying = false } }
            Spacer()
            StripSearchField(model: model, editing: $searching) { tm in
                let next = StripJump(target: tm, nonce: (jump?.nonce ?? 0) + 1)
                if model.devicesPane == .strips { jump = next } else {
                    // 先切回通道条，等它建出来再跳（新建的视图收不到建之前的变化）
                    model.devicesPane = .strips
                    DispatchQueue.main.async { jump = next }
                }
            }
            Picker("下方", selection: $model.devicesPane) {
                ForEach(DevicesPane.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Toggle("只看有信号", isOn: $onlySignal).toggleStyle(.checkbox).fixedSize()
                .disabled(!model.meters.live || model.devicesPane != .strips)
                .help(model.meters.live ? "只列最近有电平的通道条" : "收不到电平（\(mainName) 未连接，或 TotalMix 没勾 Send Level Data）")
        }
        .padding(.horizontal, Tokens.Space.xl).padding(.vertical, Tokens.Space.s)
        .background(Tokens.Palette.bg)
    }
}

extension AppModel {
    /// 设备页选中的接口和它所在的面板。
    var selectedConnector: (DevicePanel, PanelConnector)? {
        guard let id = panelSelection else { return nil }
        for p in PanelLayout.all { if let c = p.connectors.first(where: { $0.id == id }) { return (p, c) } }
        return nil
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
    /// 选接口看链路（第 6.4.4 节）：非 nil 时只亮这些线缆。
    var highlightLinks: Set<String>? = nil
    var onPick: () -> Void = {}
    /// 从一个接口拖到另一个接口。
    var drop: (PanelConnector, PanelConnector) -> Void = { _, _ in }

    /// 选中接口时：与它有线相连的接口（这些不变暗）。
    private var linked: Set<String> {
        guard let s = selected else { return [] }
        let key = "conn:\(s)"
        return Set(model.cables(face: face).flatMap { c in c.from == key || c.to == key ? [c.from, c.to] : [] })
    }

    /// 三行（第 6.8 节）：12Mic；XT 与“这台 Mac”、P16-I；XTC。线缆在行与行之间的缝里走。
    var body: some View {
        VStack(alignment: .leading, spacing: 64) {
            unit("12mic").transformAnchorPreference(key: RackAnchorKey.self, value: .bounds) { $0["row:0"] = $1 }
            HStack(alignment: .center, spacing: Tokens.Space.l) {
                if PanelLayout.panel("xt", face) != nil {
                    unit("xt").frame(maxWidth: 560)
                } else {
                    // 通用主卡（第 6.4.6 节）：没有面板图，显示一张卡片
                    NodeCard(title: model.snapshot.devices["xt"]?.settings["totalmix.device"]?.knownValue ?? model.studioConfig.mainCard.deviceName,
                             lines: model.studioConfig.mainCard == .ufx3
                                ? ["Line 1–8、Mic 9–12、AES、ADAT 1/2、MADI", "还没有面板图；接线在“设置 → 接线”里改"]
                                : ["通用主卡：TotalMix 第 n 路 = 主卡第 n 路", "没有面板图；接线在“设置 → 接线”里加"],
                             color: Tokens.Palette.accent)
                        .frame(width: 300)
                }
                MacNodeCard(model: model).frame(width: 170)
                    .transformAnchorPreference(key: RackAnchorKey.self, value: .bounds) { $0["node:mac"] = $1 }
                if model.studioConfig.has("p16i") {
                    NodeCard(title: "Behringer P16-I", lines: ["ADAT A 输入", "ADAT B 输入"], color: Color(hex: 0x6AA6C9))
                        .frame(width: 170)
                        .transformAnchorPreference(key: RackAnchorKey.self, value: .bounds) { $0["node:p16i"] = $1 }
                }
                Spacer(minLength: 0)
            }
            .transformAnchorPreference(key: RackAnchorKey.self, value: .bounds) { $0["row:1"] = $1 }
            unit("xtc").transformAnchorPreference(key: RackAnchorKey.self, value: .bounds) { $0["row:2"] = $1 }
        }
        .padding(.top, Tokens.Space.l)
        .overlayPreferenceValue(RackAnchorKey.self) { anchors in
            GeometryReader { g in
                let points = anchors.mapValues { g[$0] }
                CableLayer(cables: model.cables(face: face), anchors: points,
                           selected: highlightLinks == nil ? selected.map { "conn:\($0)" } : nil,
                           highlight: highlightLinks)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private func unit(_ deviceID: String) -> some View {
        // 设备组成里关掉的不显示（第 6.4.6 节）
        if model.studioConfig.has(deviceID), let panel = PanelLayout.panel(deviceID, face) {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                HStack(spacing: Tokens.Space.s) {
                    Text(model.snapshot.topology.device(deviceID)?.name ?? deviceID).font(Tokens.Font.cardTitle)
                    if model.isDemo(deviceID) { Badge(text: "演示数据", color: Tokens.Palette.unknown) }
                    // 12Mic（HTTP 地址）、XTC（MIDI 端点、设备 ID）的连接设置在“设置 → 连接”
                    if deviceID == "12mic" || deviceID == "xtc" {
                        Button("连接设置…") {
                            model.settingsTab = .connection
                            model.section = .settings
                        }
                        .buttonStyle(.link).font(Tokens.Font.caption)
                        .help(deviceID == "xtc" ? "XTC 的 MIDI 端点、设备 ID、读取与改动开关" : "12Mic 的地址（网线 / USB）")
                    }
                }
                PanelView(panel: panel, selected: selected, linked: linked,
                          signal: { model.hasSignal(port: $0) },
                          drop: { id, target in
                              guard let src = PanelLayout.all.flatMap(\.connectors).first(where: { "conn:\($0.id)" == id }) else { return false }
                              drop(src, target)
                              return true
                          }) { c in
                    // 点接口：选中它，通道条高亮它的整条链；再点一次取消
                    selected = selected == c.id ? nil : c.id
                    onPick()
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
    var drop: (String, PanelConnector) -> Bool = { _, _ in false }
    var onSelect: (PanelConnector) -> Void
    @State private var dropTarget: String?

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
            .strokeBorder(isSel || dropTarget == c.id ? Tokens.Palette.accent
                          : (linked.contains("conn:\(c.id)") ? Tokens.Palette.accent.opacity(0.5) : .clear), lineWidth: 2)
            .background(Circle().fill(Color.white.opacity(0.001)))
            .overlay(alignment: .topTrailing) {
                if hasSig { Circle().fill(Tokens.Palette.ok).frame(width: 7, height: 7).shadow(color: Tokens.Palette.ok, radius: 3) }
            }
            .frame(width: d, height: d)
            .contentShape(Circle())
            .anchorPreference(key: RackAnchorKey.self, value: .bounds) { ["conn:\(c.id)": $0] }
            .onTapGesture { onSelect(c) }
            .draggable("conn:\(c.id)") {
                Text(c.name).font(Tokens.Font.caption).padding(6).background(RoundedRectangle(cornerRadius: 4).fill(Tokens.Palette.surface))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let id = items.first, id.hasPrefix("conn:") else { return false }
                return drop(id, c)
            } isTargeted: { dropTarget = $0 ? c.id : (dropTarget == c.id ? nil : dropTarget) }
            .help(c.routes ? "\(c.name)\n点：看路径或详情；拖到另一个接口：接线或送一路声音" : "\(c.name)（不参与路由）")
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
    /// 路径模式：只亮这些线（接线表 id）。
    var highlight: Set<String>? = nil

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
        let routed = Self.route(cables, anchors: anchors, rows: Self.rows(anchors))
        ZStack {
            ForEach(routed, id: \.cable.id) { r in
                let on = highlight.map { $0.contains(r.cable.id) } ?? (selected == nil || r.cable.from == selected || r.cable.to == selected)
                // 未核对（只是接线表里的声明）画虚线
                Self.path(r.points)
                    .stroke(Self.color(r.cable.type).opacity(on ? 0.95 : 0.12),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: r.cable.verified ? [] : [7, 5]))
                ForEach(Array([r.points.first, r.points.last].compactMap { $0 }.enumerated()), id: \.offset) { _, p in
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

    /// 各行的框；只剩一行（扩展设备都关了）时在下面虚拟一行，线照样从下方的缝走。
    static func rows(_ anchors: [String: CGRect]) -> [CGRect] {
        let rows = (0 ..< rowCount).compactMap { anchors["row:\($0)"] }
        guard rows.count == 1, let r = rows.first else { return rows }
        return rows + [CGRect(x: r.minX, y: r.maxY + 64, width: r.width, height: 1)]
    }

    struct Routed { var cable: CableSpec; var points: [CGPoint]; var labelAt: CGPoint }

    static let rowCount = 3

    /// 每根线：起点垂直走到一条缝，在缝里横走，再垂直进终点。
    /// 两端在不同行时走上面那台设备下方的缝；同一行时走这一行下方的缝（最后一行走上方）。
    /// 节点卡片（Mac、P16-I）从靠近那条缝的一边进：缝在上就进上沿，否则进下沿。
    static func route(_ cables: [CableSpec], anchors: [String: CGRect], rows: [CGRect]) -> [Routed] {
        guard rows.count >= 2 else { return [] }
        func rowOf(_ y: CGFloat) -> Int? { rows.firstIndex { y >= $0.minY - 4 && y <= $0.maxY + 4 } }
        var lanes: [Int: Int] = [:]
        // 同一张节点卡片上的多根线（P16 的 ADAT A、B）错开进，免得叠成一根
        var nodeUse: [String: Int] = [:]
        return cables.compactMap { c in
            guard let fa = anchors[c.from], let fb = anchors[c.to] else { return nil }
            guard let ra = rowOf(fa.midY), let rb = rowOf(fb.midY) else { return nil }
            let gap = ra == rb ? min(ra, rows.count - 2) : min(ra, rb)
            lanes[gap, default: 0] += 1
            let mid = (rows[gap].maxY + rows[gap + 1].minY) / 2
            let gy = mid + CGFloat((lanes[gap] ?? 1) - 3) * 7
            func end(_ f: CGRect, _ id: String) -> CGPoint {
                guard id.hasPrefix("node:") else { return CGPoint(x: f.midX, y: f.midY) }
                let k = nodeUse[id, default: 0]
                nodeUse[id] = k + 1
                return CGPoint(x: min(f.minX + 28 + CGFloat(k) * 40, f.maxX - 12), y: gy < f.minY ? f.minY : f.maxY)
            }
            let a = end(fa, c.from), b = end(fb, c.to)
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
    var showPath: (ChannelRef) -> Void = { _ in }
    var close: () -> Void

    var body: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var explain: String {
        switch connector.kind {
        case .clock: return "字时钟接口，不参与路由。时钟状态在“体检 → 时钟”。"
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
                // 轻量格子：64 格各带一个按钮和提示会让检查器重建变慢，改为文字 + 点按
                Text("\(ch)").font(.system(size: 9, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 18)
                    .background(RoundedRectangle(cornerRadius: 3).fill(
                        sig ? Tokens.Palette.ok.opacity(0.45) : routed.contains(ch) ? Tokens.Palette.border : Tokens.Palette.bg))
                    .foregroundStyle(routed.contains(ch) || sig ? Tokens.Palette.text : Tokens.Palette.textMuted)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showPath(ref)
                        model.inspect(ref)
                    }
            }
        }
        .help("点一格：通道条只看这一路，下面显示它的详情")
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// 出图检查用（`--render`）：设备页面板机架。
public enum RackRender {
    @MainActor public static func rear(_ model: AppModel) -> some View { RackView(model: model, face: .rear, selected: .constant(nil)) }
}

