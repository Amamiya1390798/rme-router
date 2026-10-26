import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RMECore
import RMEAdapters

/// MADIface XT 的 TotalMix 式通道条（文档第 6.4.2、6.4.3 节）：
/// 硬件输入（= 电脑录音）、软件回放（DAW 送来）、硬件输出三行。
/// - 点输出：上两行显示送到它的电平（同 TotalMix）；
/// - 点输入 / 回放：画出它送到哪些输出（线上标电平），输入还画到“电脑录音 n”；
/// - 把上面一条拖到下面一条 = 新建发送（-30 dB，进待应用栏）；
/// - ⌘ / ⇧ 单击多选，屏蔽（只影响显示）与取消屏蔽；搜索跳转（第 6.4.5 节）。
struct XTStripsView: View, Equatable {
    @Bindable var model: AppModel
    var onlySignal: Bool
    /// 在面板上选中接口时：要高亮的通道条和它们之间的线（第 6.4.4 节）。
    var focus: StripFocus? = nil
    /// 链路卡上鼠标停着的那条发送：加亮它，其余线变淡。
    var highlightEdge: StripFocus.Edge? = nil
    /// 选中接口时点了一条通道条：返回 true 表示已处理（缩小到这一路），false 则照常选中。
    var onFocusPick: ((XTStrip) -> Bool)? = nil
    /// 搜索跳转：每次跳转 nonce 加一。
    var jump: StripJump? = nil
    /// 搜索框没在输入时才接管 ⌘A（否则 ⌘A 要留给搜索框全选文字）。
    var allowSelectAll = true
    /// 只比较会变的参数（回调每次都是新的闭包）：模型里的变化由 Observation 自己触发重绘。
    static func == (a: Self, b: Self) -> Bool {
        a.model === b.model && a.onlySignal == b.onlySignal && a.focus == b.focus && a.highlightEdge == b.highlightEdge
            && a.jump == b.jump && a.allowSelectAll == b.allowSelectAll
    }

    @State private var output: TotalMixChannel?
    @State private var source: TotalMixChannel?
    /// 多选（第 6.4.5 节）：⌘ 单击加选、⇧ 单击连选。
    @State private var picked: Set<TotalMixChannel> = []
    @State private var pickAnchor: TotalMixChannel?
    @State private var showHidden = false
    /// 搜索跳到的被屏蔽条：临时显示，直到下次跳转。
    @State private var revealed: Set<TotalMixChannel> = []
    @State private var flash: TotalMixChannel?
    @State private var batchGain = false
    @State private var batchError: String?

    var body: some View {
        // 每次重绘只算一次（以前每条通道条都重新算一遍输出列表）
        let allOutputs = model.xtStrips(.output)
        let current = allOutputs.first { $0.tm == output } ?? allOutputs.first
        let outputs = unhidden(allOutputs)
        let inputs = filtered(model.xtStrips(.input)), playbacks = filtered(model.xtStrips(.playback))
        let all = inputs + playbacks
        let selectedSource = all.first { $0.tm == source }
        let sends = selectedSource.map { model.xtSends(from: $0.tm) } ?? []
        let origins = model.originLabels(inputs.compactMap(\.ref))
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            header(selectedSource, sends: sends, outputs: allOutputs, current: current)
            StripShortcuts(enabled: allowSelectAll, hasPicks: !picked.isEmpty,
                           selectAll: { picked = Set((inputs + playbacks + outputs).map(\.tm)) },
                           hide: hidePicked, unhide: unhidePicked, clear: { picked = [] })
            if allOutputs.isEmpty {
                Text("还没有从 TotalMix 读到通道。在“设置 → 连接”确认端口后点“读取设备”。")
                    .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
            } else {
                row("硬件输入", sub: "= 电脑录音", ids: inputs.map(\.tm)) {
                    ForEach(inputs) { s in strip(s, origin: s.ref.flatMap { origins[$0] }, current: current, row: inputs).id(s.tm) }
                }
                row("软件回放", sub: "DAW 送来", ids: playbacks.map(\.tm)) {
                    if focus == nil, let s = selectedSource, s.tm.bus == .input { RecordingGhost(strip: s) }
                    ForEach(playbacks) { s in strip(s, origin: nil, current: current, row: playbacks).id(s.tm) }
                }
                row("硬件输出", sub: nil, ids: outputs.map(\.tm)) {
                    ForEach(outputs) { s in
                        let lit = focus.map { $0.outputs.contains(s.tm) }
                        OutputStrip(model: model, strip: s, selected: focus == nil && selectedSource == nil && s.tm == current?.tm,
                                    routedDB: focus == nil && selectedSource != nil ? sends.first { $0.output == s.tm }?.dB : nil,
                                    lit: lit, picked: picked.contains(s.tm), flash: flash == s.tm,
                                    hiddenMark: model.hiddenStrips.contains(s.tm)) {
                            if pickClick(s, row: outputs) { return }
                            output = s.tm
                            source = nil
                        }
                        .transformAnchorPreference(key: StripAnchorKey.self, value: .bounds) { $0["out:\(s.tm.number)"] = $1 }
                        .id(s.tm)
                    }
                }
            }
        }
        .padding(Tokens.Space.m)
        .overlayPreferenceValue(StripAnchorKey.self) { anchors in
            GeometryReader { g in
                if let focus {
                    // 选中接口：画链上每条“来源条 → 输出条”的线
                    ForEach(Array(focus.edges.prefix(StripFocus.maxEdges).enumerated()), id: \.offset) { _, e in
                        if let a = anchors["src:\(e.from.bus.rawValue):\(e.from.number)"], let b = anchors["out:\(e.to.number)"] {
                            RouteLines(from: g[a], targets: [(g[b], e.dB)],
                                       opacity: highlightEdge == nil || highlightEdge == e ? 1 : 0.2)
                        }
                    }
                } else if let s = selectedSource, let from = anchors["src"].map({ g[$0] }) {
                    RouteLines(from: from, targets: sends.compactMap { t in anchors["out:\(t.output.number)"].map { (g[$0], t.dB) } }
                               + (s.tm.bus == .input ? (anchors["rec"].map { [(g[$0], Double?.none)] } ?? []) : []))
                }
            }
            .allowsHitTesting(false)
            .clipped()
        }
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(Tokens.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(Tokens.Palette.border))
        .onChange(of: jump) { if let j = jump { go(to: j.target) } }
    }

    // MARK: 多选、屏蔽、跳转（第 6.4.5 节）

    /// ⌘ 单击加选 / 取消，⇧ 单击连选同一行；返回 true 表示这次点击只是在选。普通单击清掉多选。
    private func pickClick(_ s: XTStrip, row: [XTStrip]) -> Bool {
        // 用这次点击事件自己带的修饰键（比读键盘当前状态可靠）
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        if flags.contains(.command) {
            if picked.contains(s.tm) { picked.remove(s.tm) } else { picked.insert(s.tm) }
            pickAnchor = s.tm
            return true
        }
        if flags.contains(.shift) {
            let ids = row.map(\.tm)
            if let a = pickAnchor, let i = ids.firstIndex(of: a), let j = ids.firstIndex(of: s.tm) {
                picked.formUnion(ids[min(i, j) ... max(i, j)])
            } else {
                picked.insert(s.tm)
            }
            pickAnchor = s.tm
            return true
        }
        if !picked.isEmpty { picked = [] }
        pickAnchor = s.tm
        return false
    }

    private func hidePicked() {
        model.hideStrips(picked)
        if let s = source, picked.contains(s) { source = nil }
        revealed.subtract(picked)
        picked = []
    }

    private func unhidePicked() {
        model.unhideStrips(picked)
        picked = []
    }

    private func batchMute(_ on: Bool) {
        batchError = model.stageBatchMute(picked, on: on)
        Task { await model.commitIfQuick() }
    }

    private func batchSend(_ dB: Double?, to output: XTStrip) {
        batchError = model.stageBatchSend(picked, to: output.tm, dB: dB)
        Task { await model.commitIfQuick() }
    }

    private func pickBar(current: XTStrip?) -> some View {
        let hiddenPicked = picked.filter(model.hiddenStrips.contains)
        let pickedSources = picked.filter { $0.bus != .output }
        return HStack(spacing: Tokens.Space.s) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(nsColor: .controlAccentColor))
            Text("已选 \(picked.count) 条").font(Tokens.Font.caption)
            if hiddenPicked.count < picked.count { Button("屏蔽 ⌘⇧H", action: hidePicked).controlSize(.small) }
            if !hiddenPicked.isEmpty { Button("取消屏蔽 ⌘⇧U", action: unhidePicked).controlSize(.small) }
            Button("静音") { batchMute(true) }.controlSize(.small)
            Button("取消静音") { batchMute(false) }.controlSize(.small)
            if let o = current, !pickedSources.isEmpty {
                Button("送到 \(o.name)…") { batchGain = true }.controlSize(.small)
                    .help("所选 \(pickedSources.count) 条来源送到「\(o.name)」的电平设成同一个值")
                    .popover(isPresented: $batchGain, arrowEdge: .bottom) {
                        GainEditor(batchTitle: "所选 \(pickedSources.count) 条 → \(o.name)", initial: -30,
                                   onCancel: { batchGain = false }) { dB in
                            batchSend(dB, to: o)
                            batchGain = false
                        }
                    }
            }
            Button("取消选择") { picked = [] }.controlSize(.small)
            if let batchError {
                Text(batchError).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.problem).lineLimit(1)
            } else {
                Text("⌘ 单击加选 · ⇧ 单击连选 · ⌘A 全选 · 屏蔽只影响显示").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                    .lineLimit(1)
            }
        }
    }

    /// 已屏蔽的管理：显示已屏蔽、逐条或全部取消。
    @ViewBuilder private var hiddenMenu: some View {
        let hidden = model.hiddenStrips
        if !hidden.isEmpty {
            let names = Dictionary((model.xtStrips(.input) + model.xtStrips(.playback) + model.xtStrips(.output)).map { ($0.tm, $0.name) },
                                   uniquingKeysWith: { a, _ in a })
            Menu("已屏蔽 \(hidden.count) 条") {
                Toggle("显示已屏蔽（淡显）", isOn: $showHidden)
                Button("全部取消屏蔽") { model.unhideAllStrips() }
                Divider()
                ForEach(hidden.sorted(), id: \.self) { tm in
                    Button("取消屏蔽 \(names[tm] ?? tm.description)（\(Self.busName(tm))）") { model.unhideStrips([tm]) }
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .font(Tokens.Font.caption)
        }
    }

    static func busName(_ tm: TotalMixChannel) -> String {
        (tm.bus == .input ? "输入 " : tm.bus == .playback ? "回放 " : "输出 ") + "\(tm.number)"
    }

    /// 跳到一条：被屏蔽的临时显示，选中它，闪一下边框；各行自己滚过去（见 row）。
    private func go(to tm: TotalMixChannel) {
        revealed = model.hiddenStrips.contains(tm) ? [tm] : []
        picked = []
        if tm.bus == .output { output = tm; source = nil } else { source = tm }
        flash = tm
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if flash == tm { flash = nil }
        }
    }

    @ViewBuilder private func header(_ s: XTStrip?, sends: [(output: TotalMixChannel, dB: Double)],
                                     outputs: [XTStrip], current: XTStrip?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Text("MADIface XT · 通道条").font(Tokens.Font.cardTitle)
            // 多选时这一行换成多选操作（不加新行，免得通道条往下跳、点偏）
            if !picked.isEmpty {
                pickBar(current: current)
            } else if let s {
                let names = sends.map { t in "\(outputs.first { $0.tm == t.output }?.name ?? "\(t.output)") \(String(format: "%.1f", t.dB))" }
                let rec = s.tm.bus == .input ? ["电脑录音 \(recordingText(s))"] : []
                Text(verbatim: "「\(s.name)」→ " + ((names + rec).isEmpty ? "没有送到任何输出" : (names + rec).joined(separator: " · ")))
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.accent).lineLimit(1)
                Button("取消选择") { source = nil }.buttonStyle(.plain).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            } else if let c = current {
                Text(verbatim: "上两行显示送到「\(c.name)」的电平；点一条输入看它送到哪里").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            Spacer()
            hiddenMenu
            Text("拖上面一条到下面一条 = 新建发送（-30 dB）").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
        }
    }

    private func strip(_ s: XTStrip, origin: OriginLabel?, current: XTStrip?, row: [XTStrip]) -> some View {
        SourceStrip(model: model, strip: s, output: current, origin: origin,
                    selected: focus == nil ? source == s.tm : false, lit: focus.map { $0.contains(s.tm) },
                    picked: picked.contains(s.tm), flash: flash == s.tm, hiddenMark: model.hiddenStrips.contains(s.tm)) {
            if pickClick(s, row: row) { return }
            if focus != nil, onFocusPick?(s) == true { return }
            source = source == s.tm ? nil : s.tm
        }
        .transformAnchorPreference(key: StripAnchorKey.self, value: .bounds) {
            $0["src:\(s.tm.bus.rawValue):\(s.tm.number)"] = $1
            if source == s.tm { $0["src"] = $1 }
        }
    }

    private func filtered(_ s: [XTStrip]) -> [XTStrip] {
        let s = unhidden(s)
        guard onlySignal else { return s }
        return s.filter { $0.ref.map { model.hasSignal($0) == true } ?? false }
    }

    /// 去掉屏蔽的条；勾了“显示已屏蔽”、在选中接口的链上、或刚搜索跳到的照样显示。
    private func unhidden(_ s: [XTStrip]) -> [XTStrip] {
        let hidden = model.hiddenStrips
        guard !hidden.isEmpty, !showHidden else { return s }
        return s.filter { !hidden.contains($0.tm) || revealed.contains($0.tm) || focus?.contains($0.tm) == true }
    }

    private func row<C: View>(_ title: String, sub: String?, ids: [TotalMixChannel], @ViewBuilder content: @escaping () -> C) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Tokens.Font.caption.weight(.semibold))
                if let sub { Text(sub).font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted) }
            }
            .frame(width: 66, alignment: .leading)
            ScrollViewReader { proxy in
                // 懒加载：只建屏幕上看得见的通道条（MADI 三个口共 200 多条，全建切页要卡 1 秒）
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 4) { content() }.padding(.bottom, 6)
                }
                // 搜索跳转：这一行有目标就滚过去（放到下一轮，等临时显示的条先建出来）
                .onChange(of: flash) {
                    guard let t = flash, ids.contains(t) else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(t, anchor: .center) }
                    }
                }
                // 选中接口后自动滚到这一行第一条高亮的通道条
                .onChange(of: focus) {
                    if let first = ids.first(where: { focus?.contains($0) == true }) {
                        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(first, anchor: .leading) }
                    }
                }
            }
        }
        .padding(.bottom, 14)   // 给线留出空间
    }
}

func recordingText(_ s: XTStrip) -> String { s.stereo ? "\(s.tm.number)/\(s.tm.number + 1)" : "\(s.tm.number)" }

struct StripAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// 从选中的来源条画到各目标条：底边中点出发，弧线进入目标顶边；线上标电平。
struct RouteLines: View {
    var from: CGRect
    var targets: [(CGRect, Double?)]
    var opacity: Double = 1

    var body: some View {
        ZStack {
            ForEach(Array(targets.enumerated()), id: \.offset) { _, t in
                let a = CGPoint(x: from.midX, y: from.maxY), b = CGPoint(x: t.0.midX, y: t.0.minY)
                Path { p in
                    p.move(to: a)
                    p.addCurve(to: b, control1: CGPoint(x: a.x, y: a.y + (b.y - a.y) * 0.55),
                               control2: CGPoint(x: b.x, y: b.y - (b.y - a.y) * 0.55))
                }
                .stroke(Tokens.Palette.accent.opacity(0.85),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: t.1 == nil ? [5, 4] : []))
                Circle().fill(Tokens.Palette.accent).frame(width: 6, height: 6).position(b)
                if let dB = t.1 {
                    Text(String(format: "%.1f", dB)).font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 3).background(RoundedRectangle(cornerRadius: 3).fill(Tokens.Palette.surface))
                        .foregroundStyle(Tokens.Palette.accent)
                        .position(x: b.x, y: b.y - 9)
                }
            }
            Circle().fill(Tokens.Palette.accent).frame(width: 7, height: 7).position(x: from.midX, y: from.maxY)
        }
        .opacity(opacity)
    }
}

/// 选中硬件输入时，在回放一行左侧出现的“电脑录音 n”：硬件输入 n 固定就是录音第 n 路，不用拉线。
struct RecordingGhost: View {
    var strip: XTStrip

    var body: some View {
        VStack(spacing: 3) {
            Text("电脑录音").font(.system(size: 11, weight: .semibold))
            Text(recordingText(strip)).font(.system(size: 13, design: .monospaced)).foregroundStyle(Tokens.Palette.accent)
            Text("DAW 输入\n固定对应").font(.system(size: 9)).multilineTextAlignment(.center).foregroundStyle(Tokens.Palette.textMuted)
        }
        .padding(5)
        .frame(width: 72, height: 96)
        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Tokens.Palette.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .transformAnchorPreference(key: StripAnchorKey.self, value: .bounds) { $0["rec"] = $1 }
        .help("硬件输入 \(recordingText(strip)) 就是电脑录音第 \(recordingText(strip)) 路，在 DAW 里选这个输入即可，不需要在 TotalMix 里拉线")
    }
}

/// 输入 / 回放的一条：名字、源头、电平、送到所选输出的电平（点了改）、M / Ø / 配对。点名字选中，可拖到输出条上。
struct SourceStrip: View {
    var model: AppModel
    var strip: XTStrip
    var output: XTStrip?
    var origin: OriginLabel?
    var selected: Bool
    /// 面板上选了接口时：true 高亮、false 变淡、nil 照常。
    var lit: Bool? = nil
    var picked = false
    var flash = false
    var hiddenMark = false
    var select: () -> Void
    @State private var editing = false

    var body: some View {
        let send = output.flatMap { model.xtSend(from: strip.tm, to: $0.tm) }
        let pending = strip.ref.flatMap { r in output?.ref.flatMap { model.pendingGain(source: r, destination: $0) } }
        VStack(spacing: 3) {
            Button(action: select) {
                VStack(spacing: 1) {
                    Text(strip.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    let looped = strip.tm.bus == .input ? model.loopbackSource(recording: strip.tm.number) : nil
                    Text(looped.map { "录音 = \($0.name) 回环" } ?? origin.map { $0.verified ? $0.text : $0.text + "？" }
                         ?? (strip.tm.bus == .input ? "录音 \(recordingText(strip))"
                             : (strip.ref.flatMap { model.hasSignal($0) } == true ? "DAW 在送" : "回放 \(recordingText(strip))")))
                        .font(.system(size: 9)).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(looped != nil ? Tokens.Palette.problem : origin?.verified == true || (strip.tm.bus == .playback && strip.ref.flatMap { model.hasSignal($0) } == true)
                                         ? Tokens.Palette.ok : Tokens.Palette.textMuted)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help((origin.map { $0.verified ? "\($0.text)\n" : "\($0.text)（未核对：这一段来自演示数据，设备还没读到）\n" } ?? "") + "点了看它送到哪里")
            if let ref = strip.ref { MeterBar(store: model.meters, ref: ref, width: 46) } else { Spacer().frame(height: 6) }
            // 源头话放的增益（第 6.4.3 节）：XT Mic，或追到的 12Mic / XTC 话放
            if strip.tm.bus == .input, let ref = strip.ref, let sp = model.stripPreamp(ref) {
                StripGainChip(model: model, sp: sp)
            }
            Button { editing = true } label: {
                Group {
                    if let p = pending { Text(PendingChange.format(p)).foregroundStyle(Tokens.Palette.accent) }
                    else if let s = send { Text(String(format: "%.1f", s)).foregroundStyle(Tokens.Palette.accent) }
                    else { Text("—").foregroundStyle(Tokens.Palette.textMuted) }
                }
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(Tokens.Palette.border.opacity(editing ? 1 : 0.4)))
            }
            .buttonStyle(.plain)
            .disabled(strip.ref == nil || output?.ref == nil)
            .help("送到「\(output?.name ?? "")」的电平；点了修改（先进待应用栏）")
            .popover(isPresented: $editing, arrowEdge: .bottom) {
                if let src = strip.ref, let o = output, let dst = o.ref {
                    GainEditor(current: send, initial: pending ?? send, title: "\(strip.name) → \(o.name)") { dB in
                        if !StripControls.sameVolume(dB, send) || pending != nil {
                            if model.stageGain(source: src, destination: dst, dB: dB) == nil { Task { await model.commitIfQuick() } }
                        }
                        editing = false
                    }
                }
            }
            if let ref = strip.ref { MiniStripButtons(model: model, ref: ref, strip: strip) }
        }
        .padding(5)
        .frame(width: 72)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.strip).fill(Tokens.Palette.bg))
        .themedSelection(selected || lit == true, cornerRadius: Tokens.Radius.strip)
        .modifier(StripMarks(picked: picked, flash: flash, hidden: hiddenMark))
        .opacity(lit == false ? 0.3 : (strip.ref.flatMap { model.hasSignal($0) } == false && !selected && lit != true ? 0.55 : 1))
        .draggable(strip.ref?.description ?? "") {
            Text(strip.name).font(Tokens.Font.caption).padding(6).background(Tokens.Palette.surface)
        }
    }
}

/// 硬件输出的一条：名字、电平、总音量、M / Ø / 配对。点选 = 上两行显示送到它的电平；接收拖来的来源。
struct OutputStrip: View {
    var model: AppModel
    var strip: XTStrip
    var selected: Bool
    /// 选中某个来源时：它送到这里的电平（nil = 没送到）。
    var routedDB: Double?
    var lit: Bool? = nil
    var picked = false
    var flash = false
    var hiddenMark = false
    var select: () -> Void
    @State private var dropTarget = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 3) {
            Text(strip.name).font(.system(size: 11, weight: .semibold)).lineLimit(1).frame(maxWidth: .infinity)
            Text("输出 \(recordingText(strip))").font(.system(size: 9)).foregroundStyle(Tokens.Palette.textMuted)
            if let ref = strip.ref { MeterBar(store: model.meters, ref: ref, width: 46) } else { Spacer().frame(height: 6) }
            let vol = strip.ref.flatMap { model.stripValue($0, .volume) }
            Text(TotalMixStripParam.volume.text(vol)).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Tokens.Palette.textMuted)
            if let ref = strip.ref { MiniStripButtons(model: model, ref: ref, strip: strip) }
        }
        .padding(5)
        .frame(width: 72)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.strip).fill(Tokens.Palette.bg))
        .themedSelection(dropTarget || selected || routedDB != nil || lit == true, cornerRadius: Tokens.Radius.strip)
        .modifier(StripMarks(picked: picked, flash: flash, hidden: hiddenMark))
        .opacity(lit == false ? 0.3 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .help(message ?? "点选：上两行显示送到这里的电平；把来源拖到这里新建发送")
        .dropDestination(for: String.self) { items, _ in
            guard let text = items.first, let src = ChannelRef(text: text), let dst = strip.ref else { return false }
            if let e = model.stageNewSend(source: src, destination: dst) { message = e.text; return false }
            Task { await model.commitIfQuick() }
            select()
            return true
        } isTargeted: { dropTarget = $0 }
    }
}

/// 通道条上的小按钮：静音 M、相位 Ø、立体声配对（只在奇数号通道上；走待应用栏，配对一律确认）。
struct MiniStripButtons: View {
    var model: AppModel
    var ref: ChannelRef
    var strip: XTStrip? = nil

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                chip("M", .mute, on: Tokens.Palette.problem)
                chip("Ø", .phase, on: Tokens.Palette.warn)
                // 送电脑录音（只有输出有；TotalMix 没回报这一项时不显示）
                if model.stripValue(ref, .loopback) != nil { chip("录", .loopback, on: Tokens.Palette.problem) }
            }
            if let s = strip, s.tm.number % 2 == 1, canPair(s) { pairChip(s) }
        }
    }

    /// 奇数号通道：已是立体声（可拆），或右边紧挨着还有一个通道（可合）。
    private func canPair(_ s: XTStrip) -> Bool {
        s.stereo || model.tmState.names[TotalMixChannel(s.tm.bus, s.tm.number + 1)] != nil
    }

    private func pairChip(_ s: XTStrip) -> some View {
        let pend = model.pendingStrip(ref, .stereo)
        let target = pend.map { $0 >= 0.5 } ?? s.stereo
        return Button {
            if model.stageStrip(ref, .stereo, s.stereo ? 0 : 1) == nil { Task { await model.commitIfQuick() } }
        } label: {
            Text(target ? "◫ 立体声" : "◧ 单声道").font(.system(size: 9))
                .frame(width: 44, height: 14)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(Tokens.Palette.border.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.chip).stroke(pend != nil ? Tokens.Palette.accent : .clear))
                .foregroundStyle(Tokens.Palette.textMuted)
        }
        .buttonStyle(.plain)
        .help(s.stereo ? "拆成两个单声道（\(s.tm.number)、\(s.tm.number + 1)；需确认）" : "与 \(s.tm.number + 1) 合并成立体声（需确认）")
    }

    private func chip(_ label: String, _ p: TotalMixStripParam, on color: Color) -> some View {
        let now = model.stripValue(ref, p), pend = model.pendingStrip(ref, p)
        let isOn = ((pend ?? now) ?? 0) >= 0.5
        return Button {
            if model.stageStrip(ref, p, isOn ? 0 : 1) == nil { Task { await model.commitIfQuick() } }
        } label: {
            Text(label).font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 15)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(isOn ? color.opacity(0.35) : Tokens.Palette.border.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.chip).stroke(pend != nil ? Tokens.Palette.accent : .clear))
                .foregroundStyle(isOn ? Tokens.Palette.text : Tokens.Palette.textMuted)
        }
        .buttonStyle(.plain)
        .disabled(now == nil)
        .help(p == .mute ? (isOn ? "取消静音（会出声，需要确认）" : "静音")
              : p == .loopback ? (isOn ? "关掉送电脑录音（录音通道恢复为原来的硬件输入）"
                                       : "把这个输出的混音送进电脑同号录音通道（会顶替那一路硬件输入，需要确认）")
              : "切换相位")
    }
}

/// 通道条上的标记：多选（系统强调色框和勾）、搜索跳到（闪一下）、已屏蔽（眼睛图标、淡显）。
struct StripMarks: ViewModifier {
    var picked: Bool
    var flash: Bool
    var hidden: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if picked {
                    RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .controlAccentColor), lineWidth: 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlAccentColor).opacity(0.10)))
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if flash {
                    RoundedRectangle(cornerRadius: 6).stroke(Tokens.Palette.warn, lineWidth: 3)
                        .shadow(color: Tokens.Palette.warn, radius: 6)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if hidden {
                    Image(systemName: "eye.slash").font(.system(size: 8)).foregroundStyle(Tokens.Palette.textMuted).padding(3)
                        .help("已屏蔽（只是不显示）")
                }
            }
            .opacity(hidden ? 0.5 : 1)
    }
}

/// 一次搜索跳转：nonce 每次加一，同一条连跳两次也会触发。
struct StripJump: Equatable {
    var target: TotalMixChannel
    var nonce: Int
}

/// 多选的快捷键（第 6.4.5 节）。单独一个小视图读“当前页”，设备页藏在后面时不接管快捷键，也不让大视图跟着重绘。
struct StripShortcuts: View {
    var enabled: Bool
    var hasPicks: Bool
    var selectAll: () -> Void
    var hide: () -> Void
    var unhide: () -> Void
    var clear: () -> Void
    @Environment(\.pageActive) private var pageActive

    var body: some View {
        if pageActive {
            ZStack {
                if enabled { Button("全选通道条", action: selectAll).keyboardShortcut("a", modifiers: .command) }
                if hasPicks {
                    Button("屏蔽所选", action: hide).keyboardShortcut("h", modifiers: [.command, .shift])
                    Button("取消屏蔽所选", action: unhide).keyboardShortcut("u", modifiers: [.command, .shift])
                    Button("取消多选", action: clear).keyboardShortcut(.escape, modifiers: [])
                }
            }
            .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
    }
}

/// 通道条上的增益按钮：显示源头话放的增益，点了改（走前级写入流程）。
struct StripGainChip: View {
    var model: AppModel
    var sp: StripPreamp
    @State private var editing = false
    @State private var error: String?

    var body: some View {
        let pending = model.pendingPreamp(deviceID: sp.deviceID, input: sp.preamp.input, field: .gain)
            .flatMap { if case let .gain(g) = $0 { return g } else { return nil } }
        let gain = pending ?? sp.preamp.gainDB.knownValue
        Button { editing = true } label: {
            HStack(spacing: 2) {
                Image(systemName: "mic.fill").font(.system(size: 8))
                Text(gain.map { String(format: "%.0f", $0) } ?? "?").font(.system(size: 10, design: .monospaced))
                if sp.preamp.phantom.knownValue == true {
                    Text("48V").font(.system(size: 7, weight: .bold)).foregroundStyle(Tokens.Palette.warn)
                }
            }
            .foregroundStyle(pending != nil ? Tokens.Palette.accent : Tokens.Palette.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(Tokens.Palette.border.opacity(editing ? 1 : 0.3)))
        }
        .buttonStyle(.plain)
        .disabled(sp.preamp.gainDB.knownValue == nil)
        .help(error ?? "源头话放：\(model.snapshot.topology.device(sp.deviceID)?.name ?? sp.deviceID) \(sp.preamp.input)；点了改增益（先进待应用栏）")
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            PreampGainEditor(title: "\(model.snapshot.topology.device(sp.deviceID)?.name ?? sp.deviceID) \(sp.preamp.input) 增益",
                             current: sp.preamp.gainDB.knownValue ?? 0, initial: gain ?? 0) { value in
                if let v = value {
                    error = model.stagePreamp(deviceID: sp.deviceID, input: sp.preamp.input, field: .gain, value: .gain(v))?.text
                    if error == nil { Task { await model.commitIfQuick() } }
                }
                editing = false
            }
        }
    }
}
