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
                               demoDevices: demoNames, showPlayback: $model.showPlayback,
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
        a.stage = { src, dst, dB in model.stageGain(source: src, destination: dst, dB: dB)?.text }
        a.stageNewSend = { src, dst in model.stageNewSend(source: src, destination: dst)?.text }
        a.sendCandidates = { model.sendSourceCandidates }
        return a
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
    @Binding var showPlayback: Bool
    var columns: Int
    var actions: OutputActions

    public init(outputs: [DeviceOutputs], status: XTStatus, lastLoaded: Date?, demoDevices: [String],
                showPlayback: Binding<Bool>, columns: Int, actions: OutputActions = OutputActions()) {
        self.outputs = outputs
        self.status = status
        self.lastLoaded = lastLoaded
        self.demoDevices = demoDevices
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
            StatusStrip(status: status, lastLoaded: lastLoaded, demoDevices: demoDevices)
            ForEach(outputs) { group in
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    HStack(spacing: Tokens.Space.s) {
                        Text(group.device.name).font(Tokens.Font.cardTitle).foregroundStyle(Tokens.Palette.text)
                        Text("\(group.cards.count) 个输出在用").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                        if demoDevices.contains(group.device.name) { Badge(text: "演示数据", color: Tokens.Palette.unknown) }
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
                Text(title).font(Tokens.Font.cardTitle).foregroundStyle(Tokens.Palette.text)
                Spacer(minLength: Tokens.Space.s)
                EvidenceDot(card.evidence)
            }
            Text(card.address).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
            Rectangle().fill(Tokens.Palette.border).frame(height: 1)
            ForEach(Array(card.sources.prefix(Self.visibleSources).enumerated()), id: \.offset) { _, source in
                SourceRow(source: source, destination: destination, editable: editable, actions: actions)
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
    var actions: OutputActions
    @State private var editing = false

    var body: some View {
        let pending = actions.pendingGain(source.refs[0], destination)
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
                Button("加入待应用") { onDone(isOff ? nil : value) }.keyboardShortcut(.defaultAction)
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
                Button("加入待应用（-30 dB）") {
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
