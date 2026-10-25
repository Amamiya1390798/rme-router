import SwiftUI
import RMECore
import RMEAdapters

/// 选中接口后的链路卡（文档第 6.4.4 节）：链上的线缆、每条发送，看完直接改。
/// 改动都走现有写入流程（待应用栏或快速方式、确认规则、回读核对、撤销）。
struct ChainCard: View {
    var model: AppModel
    var focus: StripFocus
    @Binding var showAll: Bool
    /// 鼠标停在哪条发送上：通道条之间对应的线加亮。
    @Binding var hoverEdge: StripFocus.Edge?
    var close: () -> Void
    @State private var error: String?

    var body: some View {
        let strips = Dictionary((model.xtStrips(.input) + model.xtStrips(.playback) + model.xtStrips(.output)).map { ($0.tm, $0) },
                                uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            header
            cables
            if focus.edges.isEmpty {
                Text(focus.isEmpty ? "链上没有 XT 通道（没接线或没有路由）。" : "链上还没有发送：用下面的“加一个去处”，或把通道条拖到输出条上。")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(focus.edges.prefix(StripFocus.maxEdges)), id: \.self) { e in
                        if let s = strips[e.from], let o = strips[e.to], let src = s.ref, let dst = o.ref {
                            EdgeRow(model: model, source: s, output: o, src: src, dst: dst, dB: e.dB, error: $error)
                                .background(RoundedRectangle(cornerRadius: 4).fill(hoverEdge == e ? Tokens.Palette.accent.opacity(0.12) : .clear))
                                .onHover { hoverEdge = $0 ? e : (hoverEdge == e ? nil : hoverEdge) }
                        }
                    }
                    if focus.edges.count > StripFocus.maxEdges {
                        Text("还有 \(focus.edges.count - StripFocus.maxEdges) 条发送没列出").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                    }
                }
            }
            addMenu(strips)
            if let error { Text(error).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.problem) }
        }
        .padding(Tokens.Space.m)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(Tokens.Palette.accent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(Tokens.Palette.accent.opacity(0.4)))
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(Tokens.Palette.accent)
            Text(focus.title).font(Tokens.Font.cardTitle)
            Text(verbatim: "\(focus.inputs.count) 条输入 · \(focus.playbacks.count) 条回放 · \(focus.outputs.count) 个输出 · \(focus.edges.count) 条发送")
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            Spacer()
            if focus.activeOnly {
                Button("只看在用的 \(focus.stripCount) 条（共 \(focus.total) 条）· 显示全部") { showAll = true }
                    .buttonStyle(.link).font(Tokens.Font.caption)
            } else if showAll {
                Button("只看在用的") { showAll = false }.buttonStyle(.link).font(Tokens.Font.caption)
            }
            Button("取消选择", action: close).keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder private var cables: some View {
        let topo = model.snapshot.topology
        let links = topo.links.filter { focus.links.contains($0.id) }
        if !links.isEmpty {
            HStack(spacing: Tokens.Space.m) {
                ForEach(links, id: \.id) { l in
                    let declared = model.cableStatus(l) == .declared
                    HStack(spacing: Tokens.Space.xs) {
                        EvidenceDot(declared ? .inferred : .confirmed)
                        Text(verbatim: "\(name(l.from)) ⇒ \(name(l.to))").font(Tokens.Font.caption)
                        Text(declared ? "未核对" : "已核对").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                    }
                    .help(model.cableStatus(l).text)
                }
            }
        }
    }

    private func name(_ portID: String) -> String {
        let topo = model.snapshot.topology
        return topo.port(portID).map { "\(topo.device($0.deviceID)?.name ?? $0.deviceID) \($0.name)" } ?? portID
    }

    /// 加一个去处：链上的来源 → 还没送到的硬件输出，新建发送（-30 dB）。
    @ViewBuilder private func addMenu(_ strips: [TotalMixChannel: XTStrip]) -> some View {
        let sources = (focus.inputs.sorted() + focus.playbacks.sorted()).compactMap { strips[$0] }.filter { $0.ref != nil }
        if !sources.isEmpty {
            let outputs = model.xtStrips(.output).filter { $0.ref != nil }
            Menu {
                ForEach(sources) { s in
                    let sent = Set(focus.edges.filter { $0.from == s.tm }.map(\.to))
                    Menu(s.name) {
                        ForEach(outputs.filter { !sent.contains($0.tm) }) { o in
                            Button(o.name) {
                                guard let src = s.ref, let dst = o.ref else { return }
                                error = model.stageNewSend(source: src, destination: dst)?.text
                                if error == nil { Task { await model.commitIfQuick() } }
                            }
                        }
                    }
                }
            } label: {
                Label("加一个去处（-30 dB）", systemImage: "plus")
            }
            .menuStyle(.borderlessButton).fixedSize()
            .font(Tokens.Font.caption)
        }
    }
}

/// 一条发送：来源 → 输出、电平（点了改电平和声像）、来源静音、关掉这条。
private struct EdgeRow: View {
    var model: AppModel
    var source: XTStrip
    var output: XTStrip
    var src: ChannelRef
    var dst: ChannelRef
    var dB: Double
    @Binding var error: String?
    @State private var editing = false

    var body: some View {
        let pending = model.pendingGain(source: src, destination: dst)
        HStack(spacing: Tokens.Space.s) {
            Text(source.name).font(Tokens.Font.body).frame(width: 110, alignment: .leading).lineLimit(1)
            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted)
            Text(output.name).font(Tokens.Font.body).frame(width: 110, alignment: .leading).lineLimit(1)
            Button { editing = true } label: {
                Text(pending.map(PendingChange.format) ?? String(format: "%.1f dB", dB))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Tokens.Palette.accent)
                    .frame(width: 72)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Tokens.Palette.border.opacity(editing ? 1 : 0.4)))
            }
            .buttonStyle(.plain)
            .help("改这条发送的电平和声像")
            .popover(isPresented: $editing, arrowEdge: .bottom) {
                let pan = model.sendPan(source: src, destination: dst)
                let pendingPan = model.pendingSendPan(source: src, destination: dst)
                GainEditor(current: dB, initial: pending ?? dB, title: "\(source.name) → \(output.name)",
                           pan: pan.map { (current: $0, initial: pendingPan ?? $0) }) { newDB, newPan in
                    if !StripControls.sameVolume(newDB, dB) || pending != nil {
                        error = model.stageGain(source: src, destination: dst, dB: newDB)?.text
                    }
                    if error == nil, let newPan, let pan, abs(newPan - pan) > 0.005 || pendingPan != nil {
                        error = model.stageSendPan(source: src, destination: dst, pan: newPan)?.text
                    }
                    if error == nil { Task { await model.commitIfQuick() } }
                    editing = false
                }
            }
            MiniStripButtons(model: model, ref: src)
            Button {
                error = model.stageGain(source: src, destination: dst, dB: nil)?.text
                if error == nil { Task { await model.commitIfQuick() } }
            } label: {
                Image(systemName: "xmark.circle").foregroundStyle(Tokens.Palette.textMuted)
            }
            .buttonStyle(.plain)
            .help("关掉这条发送（推子拉到关）")
            Spacer()
        }
        .padding(.horizontal, Tokens.Space.xs).padding(.vertical, 2)
    }
}
