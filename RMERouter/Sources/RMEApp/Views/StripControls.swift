import SwiftUI
import RMECore
import RMEAdapters

/// 通道条控件需要的读写（文档第 7.8 节）。默认全空，便于出图。
public struct StripActions {
    /// 读回的当前值；nil = 这个通道没有该参数或读不到。
    public var current: (ChannelRef, TotalMixStripParam) -> Double? = { _, _ in nil }
    public var pending: (ChannelRef, TotalMixStripParam) -> Double? = { _, _ in nil }
    /// 返回错误说明；nil 表示已加入待应用（快速方式下由调用方立即发送）。
    public var stage: (ChannelRef, TotalMixStripParam, Double) -> String? = { _, _, _ in nil }
    /// 打开 EQ 窗口（第 7.8 节）。
    public var openEQ: (ChannelRef) -> Void = { _ in }
    public init() {}
}

extension AppModel {
    /// 界面用的通道条读写。
    var stripActions: StripActions {
        var a = StripActions()
        a.current = { [unowned self] in self.stripValue($0, $1) }
        a.pending = { [unowned self] in self.pendingStrip($0, $1) }
        a.openEQ = { [unowned self] ref in
            let name = (self.xtStrips(.input) + self.xtStrips(.playback) + self.xtStrips(.output)).first { $0.ref == ref }?.name
            self.eqEditing = EQTarget(ref: ref, name: name ?? ref.description)
        }
        a.stage = { [unowned self] ref, p, v in
            if let e = self.stageStrip(ref, p, v) { return e.text }
            Task { await self.commitIfQuick() }
            return nil
        }
        return a
    }
}

/// 一排紧凑的通道条控件：静音、相位、音量、平衡（这个通道有哪个就显示哪个）。
struct StripControls: View {
    var ref: ChannelRef
    var actions: StripActions
    @State private var editingVolume = false
    @State private var editingBalance = false
    @State private var editingFX: TotalMixStripParam?
    @State private var editingWidth = false
    @State private var error: String?

    var body: some View {
        let has = TotalMixStripParam.allCases.filter { actions.current(ref, $0) != nil }
        if !has.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                HStack(spacing: Tokens.Space.s) {
                    if has.contains(.mute) { muteChip }
                    if has.contains(.phase) { phaseChip }
                    if has.contains(.volume) { volumeChip }
                    if has.contains(.balpan) { balanceChip }
                    if has.contains(.loopback) { loopbackChip }
                    Spacer(minLength: 0)
                }
                // 第二行：E10（送效果、效果返回、宽度、M/S、自动增益、收对讲；第 7.8 节）
                if !has.filter(Self.secondRow.contains).isEmpty {
                    HStack(spacing: Tokens.Space.s) {
                        if has.contains(.fxsend) { fxChip(.fxsend) }
                        if has.contains(.fxreturn) { fxChip(.fxreturn) }
                        if has.contains(.width) { widthChip }
                        if has.contains(.msproc) { toggleChip(.msproc, on: "M/S 开", off: "M/S 关", help: "M/S 处理：单声道信息送左、立体声信息送右") }
                        if has.contains(.autoset) { toggleChip(.autoset, on: "自动增益 开", off: "自动增益 关", help: "自动降增益防过载，保持约 6 dB 余量") }
                        if has.contains(.eqEnable) {
                            let on = (value(.eqEnable).shown ?? 0) >= 0.5
                            chip(on ? "EQ 开…" : "EQ…", color: on ? Tokens.Palette.accent : Tokens.Palette.textMuted, pending: value(.eqEnable).pending) {
                                actions.openEQ(ref)
                            }
                            .help("打开 EQ（3 段 + 低切）")
                        }
                        if has.contains(.talkbacksel) { toggleChip(.talkbacksel, on: "收对讲", off: "不收对讲", help: "这个输出是否接收对讲信号") }
                        Spacer(minLength: 0)
                    }
                }
                if let error {
                    Text(error).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.problem)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func value(_ p: TotalMixStripParam) -> (now: Double?, shown: Double?, pending: Bool) {
        let now = actions.current(ref, p), pend = actions.pending(ref, p)
        return (now, pend ?? now, pend != nil)
    }

    private func stage(_ p: TotalMixStripParam, _ v: Double) { error = actions.stage(ref, p, v) }

    private var loopbackChip: some View {
        let v = value(.loopback), on = (v.shown ?? 0) >= 0.5
        return chip(on ? "送电脑录音" : "不送录音", color: on ? Tokens.Palette.problem : Tokens.Palette.textMuted, pending: v.pending) {
            stage(.loopback, on ? 0 : 1)
        }
        .help(on ? "关掉：录音通道恢复为原来的硬件输入" : "把这个输出的混音送进电脑同号录音通道（顶替那一路硬件输入，需要确认）")
    }

    static let secondRow: [TotalMixStripParam] = [.fxsend, .fxreturn, .width, .msproc, .autoset, .talkbacksel, .eqEnable]

    private func toggleChip(_ p: TotalMixStripParam, on onText: String, off offText: String, help: String) -> some View {
        let v = value(p), on = (v.shown ?? 0) >= 0.5
        return chip(on ? onText : offText, color: on ? Tokens.Palette.accent : Tokens.Palette.textMuted, pending: v.pending) {
            stage(p, on ? 0 : 1)
        }
        .help(help)
    }

    /// 送效果 / 效果返回：dB，用发送电平同款编辑框。
    private func fxChip(_ p: TotalMixStripParam) -> some View {
        let v = value(p)
        return chip("\(p.label) \(p.text(v.shown))", color: Tokens.Palette.text, pending: v.pending) { editingFX = p }
            .help(p == .fxsend ? "送到效果总线（混响、回声）的量" : "效果混进这个输出的量")
            .popover(isPresented: Binding(get: { editingFX == p }, set: { if !$0 { editingFX = nil } }), arrowEdge: .leading) {
                let on = v.now.flatMap { $0 > TotalMixFader.offThresholdDB ? $0 : nil }
                let initial = v.shown.flatMap { $0 > TotalMixFader.offThresholdDB ? $0 : nil }
                GainEditor(current: on, initial: initial, title: "\(ref) \(p.label)") { dB in
                    if !Self.sameVolume(dB, on) || v.pending { stage(p, dB ?? -300) }
                    editingFX = nil
                }
            }
    }

    private var widthChip: some View {
        let v = value(.width)
        return chip("宽度 \(TotalMixStripParam.width.text(v.shown))", color: Tokens.Palette.text, pending: v.pending) { editingWidth = true }
            .help("立体声宽度：+1 全立体声，0 单声道，-1 左右互换")
            .popover(isPresented: $editingWidth, arrowEdge: .leading) {
                WidthEditor(title: "\(ref) 宽度", current: v.now ?? 1, initial: v.shown ?? 1) { w in
                    if let w { stage(.width, w) }
                    editingWidth = false
                }
            }
    }

    private var muteChip: some View {
        let v = value(.mute), on = (v.shown ?? 0) >= 0.5
        return chip(on ? "静音" : "未静音", color: on ? Tokens.Palette.problem : Tokens.Palette.textMuted, pending: v.pending) {
            stage(.mute, on ? 0 : 1)
        }
        .help(on ? "取消静音（会出声，需要确认）" : "静音")
    }

    private var phaseChip: some View {
        let v = value(.phase), on = (v.shown ?? 0) >= 0.5
        return chip(on ? "Ø 反相" : "Ø 正相", color: on ? Tokens.Palette.warn : Tokens.Palette.textMuted, pending: v.pending) {
            stage(.phase, on ? 0 : 1)
        }
        .help("切换相位")
    }

    private var volumeChip: some View {
        let v = value(.volume)
        return chip("音量 \(TotalMixStripParam.volume.text(v.shown))", color: Tokens.Palette.text, pending: v.pending) {
            editingVolume = true
        }
        .help("输出总音量")
        .popover(isPresented: $editingVolume, arrowEdge: .leading) {
            let on = v.now.flatMap { TotalMixFader.isOn($0) ? $0 : nil }
            let initial = v.shown.flatMap { TotalMixFader.isOn($0) ? $0 : nil }
            GainEditor(current: on, initial: initial, title: "\(ref) 输出音量") { dB in
                if !Self.sameVolume(dB, on) || v.pending { stage(.volume, dB ?? -300) }
                editingVolume = false
            }
        }
    }

    private var balanceChip: some View {
        let v = value(.balpan)
        return chip("平衡 \(TotalMixStripParam.balpan.text(v.shown))", color: Tokens.Palette.text, pending: v.pending) {
            editingBalance = true
        }
        .help("左右平衡")
        .popover(isPresented: $editingBalance, arrowEdge: .leading) {
            PanEditor(title: "\(ref) 平衡", current: v.now ?? 0, initial: v.shown ?? 0) { pan in
                if let pan { stage(.balpan, pan) }
                editingBalance = false
            }
        }
    }

    static func sameVolume(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return abs(x - y) < 0.05
        default: return false
        }
    }

    private func chip(_ text: String, color: Color, pending: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(Tokens.Font.caption)
                .foregroundStyle(pending ? Tokens.Palette.accent : color)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(Tokens.Palette.border.opacity(pending ? 1 : 0.5)))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.chip).stroke(pending ? Tokens.Palette.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// 声像 / 平衡编辑：左 100 … 中 … 右 100。结果只进待应用栏。
struct PanEditor: View {
    var title: String
    var current: Double
    var onDone: (Double?) -> Void
    @State private var value: Double

    init(title: String, current: Double, initial: Double, onDone: @escaping (Double?) -> Void) {
        self.title = title
        self.current = current
        self.onDone = onDone
        _value = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text(title).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
            HStack {
                Text(TotalMixWrite.panText(value)).font(Tokens.Font.cardTitle).monospacedDigit()
                Spacer()
                Text("当前 \(TotalMixWrite.panText(current))").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            HStack(spacing: Tokens.Space.s) {
                Text("左").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                Slider(value: $value, in: -1 ... 1, step: 0.01)
                Text("右").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            HStack {
                Button("居中") { value = 0 }
                Spacer()
                Button("取消") { onDone(nil) }
                Button(ConfirmMode.current.applyLabel) { onDone(value) }.keyboardShortcut(.defaultAction)
            }
            Text("不会立即发送；在底部“待应用”栏确认后才写入 TotalMix。")
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
        }
        .padding(Tokens.Space.l)
        .frame(width: 320)
    }
}

/// 立体声宽度编辑：-1（左右互换）… 0（单声道）… +1（全立体声）。结果只进待应用栏。
struct WidthEditor: View {
    var title: String
    var current: Double
    var onDone: (Double?) -> Void
    @State private var value: Double

    init(title: String, current: Double, initial: Double, onDone: @escaping (Double?) -> Void) {
        self.title = title
        self.current = current
        self.onDone = onDone
        _value = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text(title).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
            HStack {
                Text(String(format: "%+.2f", value)).font(Tokens.Font.cardTitle).monospacedDigit()
                Spacer()
                Text(String(format: "当前 %+.2f", current)).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            HStack(spacing: Tokens.Space.s) {
                Text("互换").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                Slider(value: $value, in: -1 ... 1, step: 0.01)
                Text("全宽").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            HStack {
                Button("单声道 0") { value = 0 }
                Button("全宽 +1") { value = 1 }
                Spacer()
                Button("取消") { onDone(nil) }
                Button(ConfirmMode.current.applyLabel) { onDone(value) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Space.l)
        .frame(width: 340)
    }
}
