import SwiftUI
import RMECore
import RMEAdapters

/// 窗口底部的“待应用”栏（文档第 7.1、7.2 节）：列出发送电平与前级改动，可单项放弃、全部放弃、应用；显示上一批结果并可撤销。
struct PendingBar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            if !model.manualTasks.isEmpty {
                HStack(spacing: Tokens.Space.s) {
                    Image(systemName: "hand.raised").foregroundStyle(Tokens.Palette.warn)
                    Text("需人工完成 \(model.manualTasks.count) 项").font(Tokens.Font.cardTitle)
                    Text("在设备面板上做完后勾掉").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                }
                ForEach(model.manualTasks) { t in
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                        Button { model.completeManualTask(t.id) } label: { Image(systemName: "square") }
                            .buttonStyle(.plain).help("标记为已完成")
                        Text(verbatim: t.text).font(Tokens.Font.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if model.hasPending || !model.history.isEmpty { Divider() }
            }
            if model.hasPending {
                HStack {
                    Text("待应用 \(model.pendingCount) 项").font(Tokens.Font.cardTitle)
                    Text("还没有发送任何消息").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                    if model.confirmMode == .quick {
                        Text("快速方式：这些改动需要你确认后才发送").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.warn)
                    }
                    Spacer()
                    Button("全部放弃") { model.discardAll() }
                    Button("应用…") { model.showConfirm = true }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent).tint(Tokens.Palette.accent)
                }
                ForEach(model.pending) { c in
                    row(title: "\(c.source.description) → \(c.destination.description)",
                        change: "\(PendingChange.format(c.oldDB)) → \(PendingChange.format(c.newDB))",
                        badges: c.isLargeJump ? [("大幅抬高", Tokens.Palette.warn)] : []) { model.discard(c.id) }
                }
                ForEach(model.pendingRoutes) { r in
                    row(title: "12Mic 路由 \(r.destination.description)",
                        change: "\(PendingRouteChange.text(r.old)) → \(PendingRouteChange.text(r.new))",
                        badges: r.isPhones ? [("耳机：注意音量", Tokens.Palette.warn)] : []) { model.discardRoute(r.id) }
                }
                ForEach(model.pendingStrips) { c in
                    row(title: c.title, change: c.changeText,
                        badges: (c.isLayoutChange ? [("改通道布局", Tokens.Palette.warn)] : [])
                            + (c.isUnmute ? [("取消静音：会出声", Tokens.Palette.problem)] : [])
                            + (c.isLargeJump ? [("大幅抬高", Tokens.Palette.warn)] : [])) { model.discardStrip(c.id) }
                }
                ForEach(model.pendingXTCRoutes) { r in
                    row(title: r.title, change: r.changeText,
                        badges: [("整块 8 路一起换", Tokens.Palette.warn)]) { model.discardXTCRoute(r.id) }
                }
                ForEach(model.pendingPreamps) { p in
                    row(title: "\(p.label)（\(p.input.description)）\(p.field.label)",
                        change: "\(p.old?.text ?? "?") → \(p.new.text)",
                        badges: (p.needsPhantomAck ? [("打开 48V", Tokens.Palette.problem)] : [])
                            + (p.isLargeJump ? [("大幅抬高", Tokens.Palette.warn)] : [])) { model.discardPreamp(p.id) }
                }
            } else if let last = model.history.first {
                HStack(spacing: Tokens.Space.s) {
                    EvidenceDot(last.verifiedCount == last.count ? .confirmed : .conflict)
                    Text("上一批：\(last.count) 项，已核对 \(last.verifiedCount) 项").font(Tokens.Font.body)
                    Text(last.date.formatted(date: .omitted, time: .standard))
                        .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                    Spacer()
                    Button("撤销这批…") {
                        model.stageUndo(last)
                        Task { await model.commitIfQuick() }
                    }
                    .help(model.confirmMode == .quick ? "把这批改回旧值（快速方式：立即发送）" : "把旧值加入待应用，仍需确认")
                }
            }
        }
        .padding(Tokens.Space.m)
        .background(Tokens.Palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(Tokens.Palette.border).frame(height: 1) }
    }

    private func row(title: String, change: String, badges: [(String, Color)], discard: @escaping () -> Void) -> some View {
        HStack(spacing: Tokens.Space.s) {
            Text(title).font(Tokens.Font.mono)
            Text(change).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.accent)
            ForEach(Array(badges.enumerated()), id: \.offset) { _, b in Badge(text: b.0, color: b.1) }
            Spacer()
            Button(action: discard) { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Tokens.Palette.textMuted).help("放弃这一项")
        }
    }
}

/// 确认框（第 7.1 节第 2–4 步、第 7.2 节）：逐条列出将发送的原文；只有“确认发送”签发 UserConfirmation。
/// 打开 48V 的改动要先勾选“没有接带式话筒等设备”。
struct ConfirmSheet: View {
    @Bindable var model: AppModel
    @State private var result: AppliedBatch?
    @State private var phantomAck = false

    private var sends: [PendingChange] { result?.changes ?? model.pending }
    private var preamps: [PendingPreampChange] { result?.preamps ?? model.pendingPreamps }
    private var routes: [PendingRouteChange] { result?.routes ?? model.pendingRoutes }
    private var xtcRoutes: [PendingXTCRouteChange] { result?.xtcRoutes ?? model.pendingXTCRoutes }
    private var strips: [PendingStripChange] { result?.strips ?? model.pendingStrips }
    private var needsPhantomAck: Bool { result == nil && model.pendingPreamps.contains(where: \.needsPhantomAck) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            Text(result == nil ? "确认发送" : "发送结果").font(Tokens.Font.viewTitle)
            connectionNote
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    ForEach(sends) { c in sendRow(c) }
                    ForEach(strips) { c in stripRow(c) }
                    ForEach(routes) { r in routeRow(r) }
                    ForEach(xtcRoutes) { r in xtcRouteRow(r) }
                    ForEach(preamps) { p in preampRow(p) }
                }
            }
            .frame(minHeight: 120, maxHeight: 360)
            if needsPhantomAck {
                Toggle(isOn: $phantomAck) {
                    Text("我确认打开 48V 的这几路没有接带式话筒等不能接幻象电源的设备")
                        .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.problem)
                }
                .toggleStyle(.checkbox)
            }
            HStack {
                Spacer()
                if let result {
                    Button("撤销这批…") {
                        model.stageUndo(result)
                        model.showConfirm = false
                        Task { await model.commitIfQuick() }
                    }
                    Button("完成") { model.showConfirm = false }.keyboardShortcut(.defaultAction)
                } else {
                    Button("取消") { model.showConfirm = false }.keyboardShortcut(.cancelAction)
                    Button(model.isApplying ? "发送中…" : "确认发送") { confirm() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent).tint(Tokens.Palette.accent)
                        .disabled(model.isApplying || !model.hasPending || (needsPhantomAck && !phantomAck))
                }
            }
        }
        .padding(Tokens.Space.xl)
        .frame(width: 640)
        .background(Tokens.Palette.bg)
    }

    @ViewBuilder private var connectionNote: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            if !sends.isEmpty || !strips.isEmpty || preamps.contains(where: { $0.deviceID == "xt" }) {
                switch model.xtStatus {
                case .live:
                    Label("MADIface XT 已连接：改动会立即影响声音。", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Tokens.Palette.warn)
                case .offlineSaved:
                    Label("MADIface XT 未连接：只改 TotalMix 保存的配置，不会出声。", systemImage: "info.circle")
                        .foregroundStyle(Tokens.Palette.textMuted)
                default:
                    Label("TotalMix 状态未知。", systemImage: "questionmark.circle").foregroundStyle(Tokens.Palette.textMuted)
                }
            }
            if preamps.contains(where: { $0.deviceID == "12mic" }) || !routes.isEmpty {
                Label("12Mic 已连接：改动会立即生效。", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Tokens.Palette.warn)
            }
            if preamps.contains(where: { $0.deviceID == "xtc" }) || !xtcRoutes.isEmpty {
                Label("XTC 已连接：改动会立即生效；TotalMix Aux Device 与 MIDI Remote 不要同时控制它。", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Tokens.Palette.warn)
            }
        }
        .font(Tokens.Font.body)
    }

    private func sendRow(_ c: PendingChange) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.s) {
                Text("\(c.source.description) → \(c.destination.description)").font(Tokens.Font.mono)
                Spacer()
                Text("\(PendingChange.format(c.oldDB)) → \(PendingChange.format(c.newDB))")
                    .font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.accent)
            }
            Text("TotalMix：\(c.totalMixLabel)").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            Text("OSC：\(c.write.message.description)").font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
            HStack(spacing: Tokens.Space.s) {
                if c.mapEvidence != .confirmed { Badge(text: "对照表为推断：请对照 TotalMix 屏幕", color: Tokens.Palette.warn) }
                if c.isLargeJump { Badge(text: "大幅抬高", color: Tokens.Palette.problem) }
                outcome(c.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func routeRow(_ r: PendingRouteChange) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.s) {
                Text(verbatim: "12Mic 路由 \(r.destination.description)").font(Tokens.Font.mono)
                Spacer()
                Text(verbatim: "\(PendingRouteChange.text(r.old)) → \(PendingRouteChange.text(r.new))")
                    .font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.accent)
            }
            Text(verbatim: r.wireText).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
            HStack(spacing: Tokens.Space.s) {
                if r.old != nil { Badge(text: "替换原来的来源", color: Tokens.Palette.warn) }
                if r.isPhones { Badge(text: "目标是耳机：注意音量", color: Tokens.Palette.problem) }
                outcome(r.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func stripRow(_ c: PendingStripChange) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.s) {
                Text(verbatim: c.title).font(Tokens.Font.mono)
                Spacer()
                Text(verbatim: c.changeText).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.accent)
            }
            Text(verbatim: "TotalMix：\(c.totalMixLabel)").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            Text(verbatim: c.wireText).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
            HStack(spacing: Tokens.Space.s) {
                if c.stereo { Badge(text: "立体声：作用于左右两声道", color: Tokens.Palette.textMuted) }
                if c.isLayoutChange { Badge(text: "改通道布局：这一对的发送、名字会跟着变", color: Tokens.Palette.warn) }
                if c.isUnmute { Badge(text: "取消静音：会突然出声", color: Tokens.Palette.problem) }
                if c.isLargeJump { Badge(text: "大幅抬高", color: Tokens.Palette.problem) }
                outcome(c.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func xtcRouteRow(_ r: PendingXTCRouteChange) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.s) {
                Text(verbatim: r.title).font(Tokens.Font.mono)
                Spacer()
                Text(verbatim: r.changeText).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.accent)
            }
            Text(verbatim: r.wireText).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
            HStack(spacing: Tokens.Space.s) {
                Badge(text: "整块 8 路一起换", color: Tokens.Palette.warn)
                outcome(r.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func preampRow(_ p: PendingPreampChange) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.s) {
                Text("\(p.label)（\(p.input.description)）\(p.field.label)").font(Tokens.Font.mono)
                Spacer()
                Text("\(p.old?.text ?? "?") → \(p.new.text)").font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.accent)
            }
            if let tm = p.tmInput {
                Text("TotalMix：\(tm.description)").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            Text(verbatim: p.wireText).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
            HStack(spacing: Tokens.Space.s) {
                if p.needsPhantomAck { Badge(text: "打开 48V：先确认没有接带式话筒", color: Tokens.Palette.problem) }
                if p.isLargeJump { Badge(text: "大幅抬高", color: Tokens.Palette.problem) }
                outcome(p.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder private func outcome(_ id: UUID) -> some View {
        if let o = result?.outcomes[id] {
            EvidenceDot(o == .verified ? .confirmed : .conflict)
            Text(o.text).font(Tokens.Font.caption)
        }
    }

    /// 唯一签发 UserConfirmation 的地方。
    private func confirm() {
        let confirmation = ConfirmationGate.userConfirmed(model.allPendingOperations)
        Task { result = await model.applyPending(confirmation: confirmation) }
    }
}
