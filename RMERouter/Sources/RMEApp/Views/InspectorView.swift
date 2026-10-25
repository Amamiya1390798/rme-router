import SwiftUI
import RMECore

/// 窗口右侧的检查器（阶段 B2）：选中通道的全部信息。点其中的通道可以继续追。
struct InspectorPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            if let ref = model.inspectorTarget {
                InspectorContent(info: model.inspectorInfo(ref)) { model.inspect($0) }
                    .padding(Tokens.Space.l)
            } else {
                Text("在信号流、输出卡标题或前级卡上选一个通道，这里显示它的全部信息。")
                    .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
                    .padding(Tokens.Space.l)
            }
        }
        .background(Tokens.Palette.surface)
    }
}

struct InspectorContent: View {
    var info: InspectorInfo
    var select: (ChannelRef) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(verbatim: info.ref.description).font(Tokens.Font.mono).textSelection(.enabled)
                Text(verbatim: "\(info.deviceName) · \(info.portName) · \(info.isInput ? "输入" : "输出")")
                    .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
                if let tm = info.totalMix {
                    HStack(spacing: Tokens.Space.s) {
                        EvidenceDot(info.totalMixEvidence ?? .unknown)
                        Text(verbatim: "TotalMix：\(tm)").font(Tokens.Font.caption)
                        if info.totalMixEvidence == .inferred {
                            Text("对照表为推断").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.warn)
                        }
                    }
                }
            }

            if let p = info.preamp {
                section("前级") {
                    row("增益", p.gainDB.knownValue.map { String(format: "%.1f dB", $0) } ?? "读不到")
                    row("48V", p.phantom.knownValue.map { $0 ? "开" : "关" } ?? "读不到")
                    row("相位", p.phase.knownValue.map { $0 ? "反相" : "正相" } ?? "读不到")
                    if let l = p.label.knownValue, !l.isEmpty { row("标签", l) }
                }
            }

            section("来自（\(info.from.count)）") { links(info.from, empty: "没有任何东西送进来") }
            section("送到（\(info.to.count)）") {
                links(info.to, empty: info.isInput ? "没有送到任何地方" : "物理输出口（没有登记接线）")
            }

            if !info.origins.isEmpty {
                section("源头") { refs(info.origins) }
            }
            if !info.endpoints.isEmpty {
                section("最终送到") { refs(info.endpoints) }
            }
            if !info.pending.isEmpty {
                section("待应用") {
                    ForEach(info.pending, id: \.self) {
                        Text(verbatim: $0).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.accent)
                    }
                }
            }
            if !info.findings.isEmpty {
                section("体检") {
                    ForEach(info.findings, id: \.self) {
                        Text(verbatim: $0).font(Tokens.Font.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(title).font(Tokens.Font.caption.weight(.semibold)).foregroundStyle(Tokens.Palette.textMuted)
            content()
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted).frame(width: 50, alignment: .leading)
            Text(v).font(Tokens.Font.body)
        }
    }

    @ViewBuilder private func links(_ items: [InspectorInfo.Link], empty: String) -> some View {
        if items.isEmpty {
            Text(empty).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
        }
        ForEach(Array(items.prefix(20).enumerated()), id: \.offset) { _, l in
            Button { select(l.ref) } label: {
                HStack(spacing: Tokens.Space.s) {
                    EvidenceDot(l.evidence)
                    Text(verbatim: l.ref.description).font(Tokens.Font.mono)
                    Text(verbatim: l.via).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                }
            }
            .buttonStyle(.plain)
        }
        if items.count > 20 {
            Text("还有 \(items.count - 20) 条").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
        }
    }

    private func refs(_ items: [ChannelRef]) -> some View {
        ForEach(items, id: \.self) { r in
            Button { select(r) } label: { Text(verbatim: r.description).font(Tokens.Font.mono) }.buttonStyle(.plain)
        }
    }
}
