import SwiftUI
import RMECore

/// “输出”视图：按设备分栏，每个在用的输出一张卡，列出送进来的声音。
public struct OutputsView: View {
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        GeometryReader { geo in
            ScrollView {
                OutputsContent(outputs: model.outputs, status: model.xtStatus, lastLoaded: model.lastLoaded,
                               demoDevices: demoNames, twelveMic: model.twelveMicStatus, showPlayback: $model.showPlayback,
                               columns: max(1, Int((geo.size.width - 48) / 300)), actions: actions)
                .padding(Tokens.Space.xl)
            }
        }
        .background(Tokens.Palette.bg)
    }

    private var actions: OutputActions {
        var a = OutputActions()
        a.selectSource = { ref in
            model.traceTarget = ref
            model.section = .signalFlow
        }
        a.canEdit = { card in card.port.deviceID == "xt" && model.lastLoaded != nil }
        a.pendingGain = { src, dst in model.pendingGain(source: src, destination: dst) }
        a.stage = { src, dst, dB in model.stageGain(source: src, destination: dst, dB: dB).map(\.text) ?? quick() }
        a.stageNewSend = { src, dst in model.stageNewSend(source: src, destination: dst).map(\.text) ?? quick() }
        a.sendCandidates = { model.sendSourceCandidates }
        a.canEditRoute = { card in card.port.deviceID == "12mic" && model.twelveMicStatus == .live }
        a.canAddRoute = { device in device == "12mic" && model.twelveMicStatus == .live }
        a.pendingRoute = { dst in model.pendingTwelveMicRoute(dst) }
        a.stageRoute = { dst, src in model.stageTwelveMicRoute(destination: dst, source: src).map(\.text) ?? quick() }
        a.routeSources = { model.twelveMicRouteSources }
        a.routeOutputs = { model.twelveMicRouteOutputs }
        a.inspect = { model.inspect($0) }
        a.meters = model.meters
        return a
    }

    /// 快速方式下暂存后立即发送（第 7.4 节）；返回 nil 表示没有错误。
    private func quick() -> String? {
        Task { await model.commitIfQuick() }
        return nil
    }

    private var demoNames: [String] {
        ["12mic", "xtc"].filter(model.isDemo).compactMap { model.snapshot.topology.device($0)?.name }
    }
}

/// 可渲染的内容部分（不含 ScrollView，便于 ImageRenderer 出图检查）。
public struct OutputsContent: View {
    var outputs: [DeviceOutputs]
    var status: XTStatus
    var lastLoaded: Date?
    var demoDevices: [String]
    var twelveMic: TwelveMicStatus
    @Binding var showPlayback: Bool
    var columns: Int
    var actions: OutputActions

    public init(outputs: [DeviceOutputs], status: XTStatus, lastLoaded: Date?, demoDevices: [String],
                twelveMic: TwelveMicStatus = .notLoaded, showPlayback: Binding<Bool>, columns: Int, actions: OutputActions = OutputActions()) {
        self.outputs = outputs
        self.status = status
        self.lastLoaded = lastLoaded
        self.demoDevices = demoDevices
        self.twelveMic = twelveMic
        self._showPlayback = showPlayback
        self.columns = columns
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            HStack(alignment: .top) {
                ViewHeader(title: "输出", subtitle: "每个在用的输出现在送出什么。点一路来源可以看它的完整路径。")
                Toggle("显示电脑回放", isOn: $showPlayback).toggleStyle(.switch).controlSize(.small)
                    .font(Tokens.Font.body).fixedSize()
            }
            StatusStrip(status: status, lastLoaded: lastLoaded, demoDevices: demoDevices, twelveMic: twelveMic)
            if let m = actions.meters { LevelHint(store: m) }
            ForEach(outputs) { group in
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    HStack(spacing: Tokens.Space.s) {
                        Text(group.device.name).font(Tokens.Font.cardTitle).foregroundStyle(Tokens.Palette.text)
                        Text("\(group.cards.count) 个输出在用").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                        if demoDevices.contains(group.device.name) { Badge(text: "演示数据", color: Tokens.Palette.unknown) }
                        if actions.canAddRoute(group.device.id) { NewRouteButton(actions: actions) }
                    }
                    Grid(alignment: .topLeading, horizontalSpacing: Tokens.Space.m, verticalSpacing: Tokens.Space.m) {
                        ForEach(Array(rows(group.cards).enumerated()), id: \.offset) { _, row in
                            GridRow {
                                ForEach(row) { OutputCardView(card: $0, actions: actions) }
                                ForEach(0 ..< (columns - row.count), id: \.self) { _ in Color.clear.gridCellUnsizedAxes([.vertical]) }
                            }
                        }
                    }
                }
            }
            if outputs.isEmpty {
                Text("还没有在用的输出。").font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rows(_ cards: [OutputCard]) -> [[OutputCard]] {
        stride(from: 0, to: cards.count, by: columns).map { Array(cards[$0 ..< min($0 + columns, cards.count)]) }
    }
}

/// 输出视图里的交互（选来源、改电平、送一路声音）。默认全空，便于出图。
public struct OutputActions {
    public var selectSource: (ChannelRef) -> Void = { _ in }
    public var canEdit: (OutputCard) -> Bool = { _ in false }
    /// 外层 nil = 没有待应用改动；内层 nil = 改成“关”。
    public var pendingGain: (ChannelRef, ChannelRef) -> Double?? = { _, _ in nil }
    /// 返回错误说明；nil 表示已加入待应用。
    public var stage: (ChannelRef, ChannelRef, Double?) -> String? = { _, _, _ in nil }
    public var stageNewSend: (ChannelRef, ChannelRef) -> String? = { _, _ in nil }
    public var sendCandidates: () -> [ChannelRef] = { [] }
    // 12Mic 路由（第 7.3 节）
    public var canEditRoute: (OutputCard) -> Bool = { _ in false }
    public var canAddRoute: (String) -> Bool = { _ in false }
    /// 外层 nil = 没有待应用改动；内层 nil = 断开。
    public var pendingRoute: (ChannelRef) -> ChannelRef?? = { _ in nil }
    public var stageRoute: (ChannelRef, ChannelRef?) -> String? = { _, _ in nil }
    public var routeSources: () -> [ChannelRef] = { [] }
    public var routeOutputs: () -> [ChannelRef] = { [] }
    /// 在检查器里打开某个通道。
    public var inspect: (ChannelRef) -> Void = { _ in }
    /// 电平（第 7.7 节）；nil 表示不显示电平条（出图时）。
    public var meters: MeterStore?
    public init() {}
}

struct OutputCardView: View {
    var card: OutputCard
    var actions: OutputActions
    static let visibleSources = 6
    @State private var addingSend = false

    private var destination: ChannelRef { ChannelRef(card.port.id, card.channels[0]) }
    private var editable: Bool { actions.canEdit(card) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Button { actions.inspect(destination) } label: {
                    Text(title).font(Tokens.Font.cardTitle).foregroundStyle(Tokens.Palette.text)
                }
                .buttonStyle(.plain)
                .help("在检查器里查看这个输出")
                Spacer(minLength: Tokens.Space.s)
                EvidenceDot(card.evidence)
            }
            HStack {
                Text(card.address).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
                Spacer(minLength: Tokens.Space.s)
                // 只有 XT（TotalMix）有电平数据
                if let m = actions.meters, card.port.deviceID == "xt" { MeterBar(store: m, ref: destination) }
            }
            Rectangle().fill(Tokens.Palette.border).frame(height: 1)
            ForEach(Array(card.sources.prefix(Self.visibleSources).enumerated()), id: \.offset) { _, source in
                SourceRow(source: source, destination: destination, editable: editable,
                          routeEditable: actions.canEditRoute(card), actions: actions)
            }
            if card.sources.count > Self.visibleSources {
                Text("还有 \(card.sources.count - Self.visibleSources) 路")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            if card.hiddenPlayback > 0 {
                Text("另有 \(card.hiddenPlayback) 路电脑回放")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            if editable {
                Button { addingSend = true } label: {
                    Label("送一路声音", systemImage: "plus").font(Tokens.Font.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Tokens.Palette.accent)
                .popover(isPresented: $addingSend, arrowEdge: .bottom) {
                    AddSendEditor(destination: destination,
                                  candidates: actions.sendCandidates().filter { c in !card.sources.contains { $0.refs.contains(c) } },
                                  stage: { actions.stageNewSend($0, destination) },
                                  close: { addingSend = false })
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var title: String {
        let chans = card.channels.count == 2 ? "\(card.channels[0])/\(card.channels[1])" : "\(card.channels[0])"
        return "\(card.port.name) · \(chans)"
    }
}

/// 卡片里的一路来源：点名字看信号流，点电平改电平（只在 TotalMix 输出上）。
struct SourceRow: View {
    var source: OutputCard.Source
    var destination: ChannelRef
    var editable: Bool
    var routeEditable: Bool = false
    var actions: OutputActions
    @State private var editing = false
    @State private var editingRoute = false

    var body: some View {
        let pending = actions.pendingGain(source.refs[0], destination)
        let pendingRoute = actions.pendingRoute(destination)
        HStack(spacing: Tokens.Space.s) {
            Button { actions.selectSource(source.refs[0]) } label: {
                HStack(spacing: Tokens.Space.s) {
                    EvidenceDot(source.evidence)
                    Text(source.label).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.text)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Tokens.Space.s)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("查看信号流")

            if editable, source.kind.gainDB != nil || pending != nil {
                Button { editing = true } label: {
                    gainLabel(pending)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Tokens.Palette.border.opacity(editing ? 1 : 0.5)))
                }
                .buttonStyle(.plain)
                .help("修改电平（先进待应用栏）")
                // 电平按钮在卡片最右侧：向左弹出，窗口窄时也不会伸出窗口右边。
                .popover(isPresented: $editing, arrowEdge: .leading) {
                    GainEditor(current: source.kind.gainDB, initial: pending ?? source.kind.gainDB,
                               title: "\(source.label) → \(destination)") { dB in
                        _ = actions.stage(source.refs[0], destination, dB)
                        editing = false
                    }
                }
            } else if routeEditable, source.kind == .passthrough {
                Button { editingRoute = true } label: {
                    Group {
                        if let target = pendingRoute {
                            Text("→ \(PendingRouteChange.text(target))").foregroundStyle(Tokens.Palette.accent)
                        } else {
                            Text("直通").foregroundStyle(Tokens.Palette.textMuted)
                        }
                    }
                    .font(Tokens.Font.mono)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Tokens.Palette.border.opacity(editingRoute ? 1 : 0.5)))
                }
                .buttonStyle(.plain)
                .help("改这个输出通道的来源（先进待应用栏）")
                .popover(isPresented: $editingRoute, arrowEdge: .leading) {
                    RouteEditor(destination: destination, current: source.refs[0],
                                initial: pendingRoute ?? source.refs[0], candidates: actions.routeSources()) { result in
                        if let choice = result { _ = actions.stageRoute(destination, choice) }
                        editingRoute = false
                    }
                }
            } else {
                Text(source.kind.shortLabel).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
            }
        }
    }

    @ViewBuilder private func gainLabel(_ pending: Double??) -> some View {
        if let target = pending {
            Text("\(source.kind.shortLabel) → \(PendingChange.format(target))")
                .font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.accent)
        } else {
            Text(source.kind.shortLabel).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
        }
    }
}

/// 电平编辑：-65（关）… +6 dB。结果只进待应用栏。
struct GainEditor: View {
    var current: Double?
    var title: String
    var onDone: (Double?) -> Void
    @State private var value: Double

    init(current: Double?, initial: Double?, title: String, onDone: @escaping (Double?) -> Void) {
        self.current = current
        self.title = title
        self.onDone = onDone
        _value = State(initialValue: initial ?? -65)
    }

    private var isOff: Bool { value <= TotalMixFaderUI.off }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text(title).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
            HStack {
                Text(isOff ? "关" : String(format: "%.1f dB", value)).font(Tokens.Font.cardTitle).monospacedDigit()
                Spacer()
                Text("当前 \(PendingChange.format(current))").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            Slider(value: $value, in: TotalMixFaderUI.off ... 6, step: 0.5)
            HStack {
                Button("关") { value = TotalMixFaderUI.off }
                Button("0 dB") { value = 0 }
                Spacer()
                Button("取消") { onDone(current) }
                Button(ConfirmMode.current.applyLabel) { onDone(isOff ? nil : value) }.keyboardShortcut(.defaultAction)
            }
            Text("不会立即发送；在底部“待应用”栏确认后才写入 TotalMix。")
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
        }
        .padding(Tokens.Space.l)
        .frame(width: 340)
    }
}

/// 送一路声音：选来源，默认 -30 dB 加入待应用。
struct AddSendEditor: View {
    var destination: ChannelRef
    var candidates: [ChannelRef]
    var stage: (ChannelRef) -> String?
    var close: () -> Void
    @State private var choice: ChannelRef?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("送一路声音到 \(destination.description)").font(Tokens.Font.cardTitle)
            if candidates.isEmpty {
                Text("没有可选的来源（对照表里没有可用的 TotalMix 输入）。").font(Tokens.Font.body)
            } else {
                Picker("来源", selection: $choice) {
                    Text("选择…").tag(ChannelRef?.none)
                    ForEach(candidates, id: \.self) { Text($0.description).font(Tokens.Font.mono).tag(ChannelRef?.some($0)) }
                }
            }
            if let error { Text(error).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.problem) }
            HStack {
                Spacer()
                Button("取消", action: close)
                Button(ConfirmMode.current.applyLabel + "（-30 dB）") {
                    guard let c = choice else { return }
                    if let e = stage(c) { error = e } else { close() }
                }
                .disabled(choice == nil)
                .keyboardShortcut(.defaultAction)
            }
            Text("新建发送从 -30 dB 安静起步，之后可在卡片上再调。").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
        }
        .padding(Tokens.Space.l)
        .frame(width: 360)
    }
}

enum TotalMixFaderUI {
    /// 滑块最左端 = 关（与 TotalMixFader.offThresholdDB 一致）。
    static let off = -65.0
}

/// 改 12Mic 一个输出通道的来源（第 7.3 节）。结果：nil = 取消；.some(nil) = 断开；.some(ref) = 新来源。
struct RouteEditor: View {
    var destination: ChannelRef
    var current: ChannelRef?
    var candidates: [ChannelRef]
    var onDone: (ChannelRef??) -> Void
    @State private var choice: ChannelRef?

    init(destination: ChannelRef, current: ChannelRef?, initial: ChannelRef?, candidates: [ChannelRef],
         onDone: @escaping (ChannelRef??) -> Void) {
        self.destination = destination
        self.current = current
        self.candidates = candidates
        self.onDone = onDone
        _choice = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text(verbatim: "\(destination.description) 的来源").font(Tokens.Font.cardTitle)
            Text(verbatim: "当前：\(PendingRouteChange.text(current))").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            SourcePicker(choice: $choice, candidates: candidates)
            HStack {
                Spacer()
                Button("取消") { onDone(nil) }
                Button(ConfirmMode.current.applyLabel) { onDone(.some(choice)) }.keyboardShortcut(.defaultAction)
            }
            Text("12Mic 每个输出通道只有一个来源，改了会替换原来的来源。确认后才写入。")
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Space.l)
        .frame(width: 360)
    }
}

/// 来源选择：按输入口分组，第一项是“断开”。
struct SourcePicker: View {
    @Binding var choice: ChannelRef?
    var candidates: [ChannelRef]

    var body: some View {
        Picker("来源", selection: $choice) {
            Text("断开（unrouted）").tag(ChannelRef?.none)
            ForEach(groups, id: \.0) { port, refs in
                Section(port) {
                    ForEach(refs, id: \.self) { Text(verbatim: $0.description).tag(ChannelRef?.some($0)) }
                }
            }
        }
    }

    private var groups: [(String, [ChannelRef])] {
        var order: [String] = []
        var map: [String: [ChannelRef]] = [:]
        for r in candidates {
            if map[r.portID] == nil { order.append(r.portID) }
            map[r.portID, default: []].append(r)
        }
        return order.map { ($0, map[$0]!) }
    }
}

/// 12Mic 分栏标题上的“新建路由”：选一个输出通道和来源。
struct NewRouteButton: View {
    var actions: OutputActions
    @State private var open = false
    @State private var output: ChannelRef?
    @State private var source: ChannelRef?
    @State private var error: String?

    var body: some View {
        Button { open = true } label: {
            Label("新建 12Mic 路由", systemImage: "plus").font(Tokens.Font.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Tokens.Palette.accent)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                Text("新建 12Mic 路由").font(Tokens.Font.cardTitle)
                Picker("输出通道", selection: $output) {
                    Text("选择…").tag(ChannelRef?.none)
                    ForEach(actions.routeOutputs(), id: \.self) { Text(verbatim: $0.description).tag(ChannelRef?.some($0)) }
                }
                SourcePicker(choice: $source, candidates: actions.routeSources())
                if let error { Text(error).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.problem) }
                HStack {
                    Spacer()
                    Button("取消") { open = false }
                    Button(ConfirmMode.current.applyLabel) {
                        guard let output else { return }
                        if let e = actions.stageRoute(output, source) { error = e } else { open = false }
                    }
                    .disabled(output == nil)
                    .keyboardShortcut(.defaultAction)
                }
                Text("如果这个输出通道已有来源，会被替换；确认框里会显示原来的来源。")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            .padding(Tokens.Space.l)
            .frame(width: 380)
        }
    }
}
