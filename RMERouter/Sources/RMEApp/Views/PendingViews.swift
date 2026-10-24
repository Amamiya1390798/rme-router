import SwiftUI
import RMECore
import RMEAdapters

/// 窗口底部的“待应用”栏（文档第 7.1 节第 1、5 步）：列出改动，可单项放弃、全部放弃、应用；显示上一批结果并可撤销。
struct PendingBar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            if !model.pending.isEmpty {
                HStack {
                    Text("待应用 \(model.pending.count) 项").font(Tokens.Font.cardTitle)
                    Text("还没有发送任何消息").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                    Spacer()
                    Button("全部放弃") { model.discardAll() }
                    Button("应用…") { model.showConfirm = true }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent).tint(Tokens.Palette.accent)
                }
                ForEach(model.pending) { c in
                    HStack(spacing: Tokens.Space.s) {
                        Text("\(c.source.description) → \(c.destination.description)").font(Tokens.Font.mono)
                        Text("\(PendingChange.format(c.oldDB)) → \(PendingChange.format(c.newDB))")
                            .font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.accent)
                        if c.isLargeJump { Badge(text: "大幅抬高", color: Tokens.Palette.warn) }
                        Spacer()
                        Button { model.discard(c.id) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).foregroundStyle(Tokens.Palette.textMuted).help("放弃这一项")
                    }
                }
            } else if let last = model.history.first {
                HStack(spacing: Tokens.Space.s) {
                    let ok = last.changes.filter { last.outcomes[$0.id] == .verified }.count
                    EvidenceDot(ok == last.changes.count ? .confirmed : .conflict)
                    Text("上一批：\(last.changes.count) 项，已核对 \(ok) 项").font(Tokens.Font.body)
                    Text(last.date.formatted(date: .omitted, time: .standard))
                        .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                    Spacer()
                    Button("撤销这批…") { model.stageUndo(last) }.help("把旧值加入待应用，仍需确认")
                }
            }
        }
        .padding(Tokens.Space.m)
        .background(Tokens.Palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(Tokens.Palette.border).frame(height: 1) }
    }
}

/// 确认框（第 7.1 节第 2–4 步）：逐条列出将发送的 OSC 原文；只有“确认发送”签发 UserConfirmation。
struct ConfirmSheet: View {
    @Bindable var model: AppModel
    @State private var result: AppliedBatch?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            Text(result == nil ? "确认发送到 TotalMix" : "发送结果").font(Tokens.Font.viewTitle)
            connectionNote
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    ForEach(result?.changes ?? model.pending) { c in row(c) }
                }
            }
            .frame(minHeight: 120, maxHeight: 360)
            HStack {
                Spacer()
                if let result {
                    Button("撤销这批…") { model.stageUndo(result); model.showConfirm = false }
                    Button("完成") { model.showConfirm = false }.keyboardShortcut(.defaultAction)
                } else {
                    Button("取消") { model.showConfirm = false }.keyboardShortcut(.cancelAction)
                    Button(model.isApplying ? "发送中…" : "确认发送") { confirm() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent).tint(Tokens.Palette.accent)
                        .disabled(model.isApplying || model.pending.isEmpty)
                }
            }
        }
        .padding(Tokens.Space.xl)
        .frame(width: 620)
        .background(Tokens.Palette.bg)
    }

    @ViewBuilder private var connectionNote: some View {
        switch model.xtStatus {
        case .live:
            Label("MADIface XT 已连接：改动会立即影响声音。", systemImage: "exclamationmark.triangle")
                .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.warn)
        case .offlineSaved:
            Label("MADIface XT 未连接：只改 TotalMix 保存的配置，不会出声。", systemImage: "info.circle")
                .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
        default:
            Label("TotalMix 状态未知。", systemImage: "questionmark.circle")
                .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
        }
    }

    private func row(_ c: PendingChange) -> some View {
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
                if let outcome = result?.outcomes[c.id] {
                    EvidenceDot(outcome == .verified ? .confirmed : .conflict)
                    Text(outcome.text).font(Tokens.Font.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// 唯一签发 UserConfirmation 的地方。
    private func confirm() {
        let confirmation = ConfirmationGate.userConfirmed(model.pending.map(\.operation))
        Task { result = await model.applyPending(confirmation: confirmation) }
    }
}
