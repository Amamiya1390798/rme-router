import SwiftUI
import RMECore
import RMEEngine

/// 前级视图里的一台设备。
public struct PreampSection: Identifiable {
    public var id: String               // 设备 ID
    public var deviceName: String
    public var preamps: [PreampChannel]
    /// 有真实数据可显示。
    public var available: Bool
    /// 数据来源说明（例如“XT 未连接：TotalMix 保存的配置”）。
    public var note: String?
    /// 没有数据时的说明。
    public var emptyHelp: String
    public var unreachableReason: String?
    public var loading: Bool

    public init(id: String, deviceName: String, preamps: [PreampChannel], available: Bool, note: String?,
                emptyHelp: String, unreachableReason: String?, loading: Bool) {
        self.id = id
        self.deviceName = deviceName
        self.preamps = preamps
        self.available = available
        self.note = note
        self.emptyHelp = emptyHelp
        self.unreachableReason = unreachableReason
        self.loading = loading
    }
}

/// “前级”视图：XT 自带 Mic 1–2（TotalMix，第 7.0 节）与 12Mic（JSON，第 6.2 节）的话放，只读。
/// 只显示读到的真实数据；读不到时不拿演示值充数。
public struct PreampsView: View {
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        GeometryReader { geo in
            ScrollView {
                PreampsContent(sections: sections, trace: SignalTrace(snapshot: model.snapshot),
                               columns: max(1, Int((geo.size.width - 48) / 220)), actions: actions) { ref in
                    model.traceTarget = ref
                    model.section = .signalFlow
                }
                .padding(Tokens.Space.xl)
            }
        }
        .background(Tokens.Palette.bg)
    }

    private var actions: PreampActions {
        var a = PreampActions()
        a.canEdit = { device in
            device == "xt" ? (model.xtStatus == .live || model.xtStatus == .offlineSaved) : model.twelveMicStatus == .live
        }
        a.pending = { device, input, field in model.pendingPreamp(deviceID: device, input: input, field: field) }
        a.inspect = { model.inspect($0) }
        a.stage = { device, input, field, value in
            if let e = model.stagePreamp(deviceID: device, input: input, field: field, value: value) { return e.text }
            Task { await model.commitIfQuick() }   // 快速方式下立即发送（第 7.4 节）
            return nil
        }
        return a
    }

    private var sections: [PreampSection] {
        let xtPreamps = model.snapshot.devices["xt"]?.preamps ?? []
        let xtNote: String? = {
            switch model.xtStatus {
            case .offlineSaved: return "XT 未连接：显示的是 TotalMix 保存的配置。"
            case .live: return "实时读取自 TotalMix。"
            default: return nil
            }
        }()
        var xtReason: String? = nil
        if case let .unreachable(r) = model.xtStatus { xtReason = r }
        var micReason: String? = nil
        if case let .unreachable(r) = model.twelveMicStatus { micReason = r }
        return [
            PreampSection(id: "xt", deviceName: "MADIface XT", preamps: xtPreamps,
                          available: !xtPreamps.isEmpty && (model.xtStatus == .live || model.xtStatus == .offlineSaved),
                          note: xtNote,
                          emptyHelp: "XT 前面板 Mic 1–2 的话放经 TotalMix Global OSC 读取。在“连接”页确认 TotalMix 端口，然后点“读取设备”。若 TotalMix 里隐藏了这两路，会读不到。",
                          unreachableReason: xtReason, loading: model.xtStatus == .loading),
            PreampSection(id: "12mic", deviceName: "12Mic", preamps: model.snapshot.devices["12mic"]?.preamps ?? [],
                          available: model.twelveMicStatus == .live && !(model.snapshot.devices["12mic"]?.preamps.isEmpty ?? true),
                          note: model.twelveMicStatus == .live ? "实时读取自 12Mic。" : nil,
                          emptyHelp: "接上 12Mic（网线或 USB），在“连接”页确认地址，打开设备上的 STATE → remote → HTTP Remote，然后点“读取设备”。",
                          unreachableReason: micReason, loading: model.twelveMicStatus == .loading),
        ]
    }
}

/// 可渲染的内容部分。
public struct PreampsContent: View {
    var sections: [PreampSection]
    var trace: SignalTrace
    var columns: Int
    var actions: PreampActions
    var onSelect: (ChannelRef) -> Void

    public init(sections: [PreampSection], trace: SignalTrace, columns: Int, actions: PreampActions = PreampActions(),
                onSelect: @escaping (ChannelRef) -> Void = { _ in }) {
        self.sections = sections
        self.trace = trace
        self.columns = columns
        self.actions = actions
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            ViewHeader(title: "前级", subtitle: "每一路话放的增益、48V、相位和标签。改动先进待应用栏，确认后才发送；点卡片空白处看这一路送到哪里。")
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    HStack(spacing: Tokens.Space.s) {
                        Text(section.deviceName).font(Tokens.Font.cardTitle).foregroundStyle(Tokens.Palette.text)
                        if section.available {
                            Text("\(section.preamps.count) 路").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                        }
                    }
                    if section.available {
                        summary(section)
                        Grid(alignment: .topLeading, horizontalSpacing: Tokens.Space.m, verticalSpacing: Tokens.Space.m) {
                            ForEach(Array(rows(section.preamps).enumerated()), id: \.offset) { _, row in
                                GridRow {
                                    ForEach(row) { p in
                                        PreampCard(preamp: p, destinations: trace.destinations(of: p.input),
                                                   deviceID: section.id, actions: actions)
                                            .onTapGesture { onSelect(p.input) }
                                    }
                                    ForEach(0 ..< (columns - row.count), id: \.self) { _ in Color.clear.gridCellUnsizedAxes([.vertical]) }
                                }
                            }
                        }
                    } else {
                        emptyState(section)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rows(_ preamps: [PreampChannel]) -> [[PreampChannel]] {
        stride(from: 0, to: preamps.count, by: columns).map { Array(preamps[$0 ..< min($0 + columns, preamps.count)]) }
    }

    /// 一行摘要：48V 与反相——开机前最容易出事的两项；再加数据来源。
    private func summary(_ section: PreampSection) -> some View {
        let p48 = section.preamps.filter { $0.phantom.knownValue == true }.map(\.input.channel)
        let phase = section.preamps.filter { $0.phase.knownValue == true }.map(\.input.channel)
        return HStack(spacing: Tokens.Space.l) {
            Text("48V 开：" + (p48.isEmpty ? "无" : p48.map { "Mic \($0)" }.joined(separator: "、")))
            Text("反相：" + (phase.isEmpty ? "无" : phase.map { "Mic \($0)" }.joined(separator: "、")))
            if let note = section.note { Text(note) }
        }
        .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
    }

    private func emptyState(_ section: PreampSection) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(spacing: Tokens.Space.s) {
                EvidenceDot(section.loading ? .inferred : .unknown)
                Text(section.loading ? "正在读取…" : "还没有读到前级").font(Tokens.Font.body)
            }
            Text("只显示从设备读到的真实数值，不显示演示值。" + section.emptyHelp)
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let reason = section.unreachableReason {
                Text(reason).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// 前级卡片上的交互。默认全空（只读，便于出图）。
public struct PreampActions {
    public var canEdit: (String) -> Bool = { _ in false }
    public var pending: (String, ChannelRef, PreampField) -> PreampValue? = { _, _, _ in nil }
    /// 返回错误说明；nil 表示已加入待应用。
    public var stage: (String, ChannelRef, PreampField, PreampValue) -> String? = { _, _, _, _ in nil }
    public var inspect: (ChannelRef) -> Void = { _ in }
    public init() {}
}

struct PreampCard: View {
    var preamp: PreampChannel
    var destinations: [ChannelRef]
    var deviceID: String = ""
    var actions: PreampActions = PreampActions()
    @State private var editingGain = false
    @State private var error: String?

    private var editable: Bool { actions.canEdit(deviceID) }
    private func pending(_ f: PreampField) -> PreampValue? { actions.pending(deviceID, preamp.input, f) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Tokens.Font.cardTitle).foregroundStyle(Tokens.Palette.text).lineLimit(1)
                Spacer(minLength: Tokens.Space.xs)
                Button { actions.inspect(preamp.input) } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.plain).foregroundStyle(Tokens.Palette.textMuted).help("在检查器里查看")
                if hasLabel {   // 没有标签时标题已经是 “Mic n”，不重复
                    Text("Mic \(preamp.input.channel)").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                }
            }
            Text(preamp.input.description).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
            if editable, preamp.gainDB.knownValue != nil {
                Button { editingGain = true } label: { gainLabel }
                    .buttonStyle(.plain)
                    .help("修改增益（先进待应用栏）")
                    .popover(isPresented: $editingGain, arrowEdge: .bottom) {
                        PreampGainEditor(title: "\(title)（\(preamp.input.description)）增益",
                                         current: preamp.gainDB.knownValue ?? 0,
                                         initial: pending(.gain).flatMap { if case let .gain(g) = $0 { return g } else { return nil } }
                                                  ?? preamp.gainDB.knownValue ?? 0) { value in
                            if let v = value { error = actions.stage(deviceID, preamp.input, .gain, .gain(v)) }
                            editingGain = false
                        }
                    }
            } else {
                gainLabel
            }
            if editable {
                HStack(spacing: Tokens.Space.xs) {
                    flagToggle(.phantom, on: "48V 开", off: "48V 关", onColor: Tokens.Palette.warn)
                    flagToggle(.phase, on: "Ø 反相", off: "Ø 正相", onColor: Tokens.Palette.accent)
                }
            }
            if let error { Text(error).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.problem) }
            HStack(spacing: Tokens.Space.xs) {
                if !editable, preamp.phantom.knownValue == true { Badge(text: "48V", color: Tokens.Palette.warn) }
                if !editable, preamp.phase.knownValue == true { Badge(text: "Ø 反相", color: Tokens.Palette.accent) }
                if preamp.hiZ.knownValue == true { Badge(text: "Hi-Z", color: Tokens.Palette.textMuted) }
                if preamp.autoGain.knownValue == true { Badge(text: "AutoSet", color: Tokens.Palette.textMuted) }
                if let g = preamp.gainGroup.knownValue, !g.isEmpty, g != "0", g.lowercased() != "none" {
                    Badge(text: "组 \(g)", color: Tokens.Palette.textMuted)
                }
            }
            if preamp.gainDB.knownValue != nil, preamp.gainDB.evidence == .inferred {
                Text("增益单位按 dB 推断，待核对").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.warn)
            }
            if !unknownFields.isEmpty {
                Text("读不到：" + unknownFields.joined(separator: "、"))
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.unknown)
            }
            Rectangle().fill(Tokens.Palette.border).frame(height: 1)
            Text(destinationText).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .card()
        .help("查看 \(preamp.input.description) 的信号流")
    }

    @ViewBuilder private var gainLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Text(gainText).font(.system(size: 22, weight: .regular, design: .monospaced).monospacedDigit())
                .foregroundStyle(preamp.gainDB.knownValue == nil ? Tokens.Palette.unknown : Tokens.Palette.text)
            if let p = pending(.gain) {
                Text("→ \(p.text)").font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.accent)
            }
        }
    }

    /// 48V / 相位开关：点一下把相反的值加入待应用；再点一下撤回。
    @ViewBuilder private func flagToggle(_ field: PreampField, on: String, off: String, onColor: Color) -> some View {
        let current: Bool? = { if case let .flag(b)? = preamp.value(field) { return b } else { return nil } }()
        let target: Bool? = { if case let .flag(b)? = pending(field) { return b } else { return nil } }()
        let shown = target ?? current
        if let current {
            Button {
                error = actions.stage(deviceID, preamp.input, field, .flag(!(target ?? current)))
            } label: {
                HStack(spacing: 2) {
                    Text(shown == true ? on : off)
                    if target != nil { Text("（待应用）") }
                }
                .font(Tokens.Font.caption)
                .foregroundStyle(target != nil ? Tokens.Palette.accent : (shown == true ? onColor : Tokens.Palette.textMuted))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(Capsule().strokeBorder((target != nil ? Tokens.Palette.accent : (shown == true ? onColor : Tokens.Palette.border)).opacity(0.7), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(field == .phantom ? "切换 48V（先进待应用栏；打开时确认框会再问一次）" : "切换相位（先进待应用栏）")
        }
    }

    private var labelText: String? {
        guard let l = preamp.label.knownValue?.trimmingCharacters(in: .whitespaces), !l.isEmpty else { return nil }
        return l
    }
    private var hasLabel: Bool { labelText != nil }
    private var title: String { labelText ?? "Mic \(preamp.input.channel)" }

    private var gainText: String {
        guard let g = preamp.gainDB.knownValue else { return "? dB" }
        return String(format: "%+.1f dB", g)
    }

    private var unknownFields: [String] {
        [("增益", preamp.gainDB.knownValue == nil), ("48V", preamp.phantom.knownValue == nil),
         ("相位", preamp.phase.knownValue == nil)].filter(\.1).map(\.0)
    }

    private var destinationText: String {
        guard !destinations.isEmpty else { return "没有送到任何地方" }
        let shown = destinations.prefix(2).map(\.description).joined(separator: "、")
        return "送到 " + shown + (destinations.count > 2 ? " 等 \(destinations.count) 处" : "")
    }
}

/// 前级增益编辑：0–60 dB（第 7.2 节）。结果只进待应用栏。
struct PreampGainEditor: View {
    var title: String
    var current: Double
    var onDone: (Double?) -> Void
    @State private var value: Double

    init(title: String, current: Double, initial: Double, onDone: @escaping (Double?) -> Void) {
        self.title = title
        self.current = current
        self.onDone = onDone
        _value = State(initialValue: min(max(initial, PreampField.gainRange.lowerBound), PreampField.gainRange.upperBound))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text(title).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
            HStack {
                Text(String(format: "%.1f dB", value)).font(Tokens.Font.cardTitle).monospacedDigit()
                Spacer()
                Text(String(format: "当前 %.1f dB", current)).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            Slider(value: $value, in: PreampField.gainRange, step: 0.5)
            HStack {
                Spacer()
                Button("取消") { onDone(nil) }
                Button(ConfirmMode.current.applyLabel) { onDone(value) }.keyboardShortcut(.defaultAction)
            }
            Text("不会立即发送；在底部“待应用”栏确认后才写入设备。范围 0–60 dB。")
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
        }
        .padding(Tokens.Space.l)
        .frame(width: 320)
    }
}
