import SwiftUI
import RMECore
import RMEAdapters

/// 控制室一栏（文档第 7.9 节）：Dim、Main 单声道、全局静音、快照 1–8。改动都进待应用栏。
struct ControlRoomBar: View {
    @Bindable var model: AppModel
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            // 三组（开关、监听、快照）放不下就换行：每组只建一次（以前三种排法都建一遍，下拉菜单被建 9 次，切页变慢）
            FlowLayout(spacing: Tokens.Space.l, lineSpacing: Tokens.Space.s) {
                HStack(spacing: Tokens.Space.m) { toggles }.fixedSize()
                HStack(spacing: Tokens.Space.m) { monitors }.fixedSize()
                HStack(spacing: Tokens.Space.m) { snapshots }.fixedSize()
            }
            if let error {
                Text(error).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.problem)
            }
        }
        .padding(Tokens.Space.m)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(Tokens.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(Tokens.Palette.border))
    }

    @ViewBuilder private var toggles: some View {
        Text("控制室").font(Tokens.Font.cardTitle).fixedSize()
        toggle(.dim, onColor: Tokens.Palette.warn)
        toggle(.mainMono, onColor: Tokens.Palette.warn)
        toggle(.globalMute, onColor: Tokens.Palette.problem)
        if model.talkbackReady {
            toggle(.talkback, onColor: Tokens.Palette.accent)
        }
    }

    @ViewBuilder private var monitors: some View {
        let outputs = model.xtStrips(.output)
        monitorMenu(.mainOut, outputs)
        monitorMenu(.phones(1), outputs)
        monitorMenu(.phones(2), outputs)
    }

    /// 主输出 / 耳机选哪一对硬件输出（第 7.9 节）。读不到这一项时不显示。
    @ViewBuilder private func monitorMenu(_ g: TotalMixGlobal, _ outputs: [XTStrip]) -> some View {
        if model.globalValue(g) != nil {
            let pend = model.pendingGlobal(g)
            let current = pend?.output ?? model.monitorOutput(g)
            let name = current.map { c in outputs.first { $0.tm == c }?.name ?? "输出 \(c.number)" } ?? "未指定"
            Menu {
                ForEach(outputs) { o in
                    Button {
                        error = model.stageMonitor(g, output: o.tm)?.text
                        if error == nil { Task { await model.commitIfQuick() } }
                    } label: {
                        Text(o.tm == current ? "✓ \(o.name)" : o.name)
                    }
                }
            } label: {
                Text("\(g.label)：\(name)").font(Tokens.Font.caption)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Tokens.Palette.border.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(pend != nil ? Tokens.Palette.accent : .clear))
            .help(g == .mainOut ? "主输出接哪一对音箱（改了一定会确认）" : "\(g.label)用哪一对输出")
        }
    }

    @ViewBuilder private var snapshots: some View {
        Text("快照").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted).fixedSize()
        if model.snapshots.isEmpty {
            Text("没读到").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.unknown).fixedSize()
        }
        ForEach(model.snapshots, id: \.number) { s in snapshot(s.number, state: s.state) }
    }

    private func toggle(_ g: TotalMixGlobal, onColor: Color) -> some View {
        let now = model.globalValue(g), pend = model.pendingGlobal(g)
        let isOn = pend.map(\.on) ?? ((now ?? 0) >= 0.5)
        return Button {
            error = model.stageGlobal(g, on: !isOn)?.text
            if error == nil { Task { await model.commitIfQuick() } }
        } label: {
            Text(g.label).font(Tokens.Font.caption).fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(isOn ? onColor.opacity(0.35) : Tokens.Palette.border.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(pend != nil ? Tokens.Palette.accent : .clear))
                .foregroundStyle(isOn ? Tokens.Palette.text : Tokens.Palette.textMuted)
        }
        .buttonStyle(.plain)
        .disabled(now == nil)
        .help(now == nil ? "还没从 TotalMix 读到" : (g == .globalMute && isOn ? "取消全局静音（会出声，需要确认）" : "切换（先进待应用栏）"))
    }

    /// 快照按钮：当前的实心，已改动的加点；点了调用（一律确认）。
    private func snapshot(_ n: Int, state: Double) -> some View {
        let current = state >= 1.5, changed = state >= 2.5
        let pend = model.pendingGlobal(.snapshot(n)) != nil
        return Button {
            error = model.stageSnapshot(n)?.text
            if error == nil { Task { await model.commitIfQuick() } }
        } label: {
            Text(changed ? "\(n)•" : "\(n)").font(.system(size: 11, weight: current ? .bold : .regular, design: .monospaced))
                .frame(width: 24, height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(current ? Tokens.Palette.accent.opacity(0.35) : Tokens.Palette.border.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(pend ? Tokens.Palette.accent : .clear))
        }
        .buttonStyle(.plain)
        .help(current ? (changed ? "当前快照（已改动，未保存）" : "当前快照") : "调用快照 \(n)：整套混音会被替换，需要确认，不能撤销")
    }
}

/// 从左到右排，一行放不下就换到下一行。
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        let w = rows.map { $0.width }.max() ?? 0
        let h = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, v) in subviews.enumerated() {
            let size = v.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var r = rows[rows.count - 1]
            r.width += (r.items.isEmpty ? 0 : spacing) + size.width
            r.height = max(r.height, size.height)
            r.items.append(i)
            rows[rows.count - 1] = r
        }
        return rows
    }
}
