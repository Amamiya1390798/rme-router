import SwiftUI
import RMECore

/// 信号核对（文档第 6.5 节）：选一支麦克风 → 说话或轻拍 → 看它实际进了 XT 的哪一路。只读，不改任何设备。
struct IdentifySheet: View {
    @Bindable var model: AppModel
    var close: () -> Void
    @State private var source: ChannelRef?
    @State private var error: String?

    /// 可选的麦克风：XT 自带、12Mic、XTC。
    private var sources: [(String, [ChannelRef])] {
        [("MADIface XT", (1 ... 2).map { ChannelRef("xt.mic.in", $0) }),
         ("12Mic", (1 ... 12).map { ChannelRef("12mic.analog.in", $0) }),
         ("OctaMic XTC", (1 ... 8).map { ChannelRef("xtc.mic.in", $0) })]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            Text("信号核对").font(Tokens.Font.viewTitle)
            Text("选一支麦克风，开始后对着它说话或轻拍。App 看 XT 全部输入的电平，找出它实际进了哪一路，再和接线表、路由算出来的比。只读，不改任何设备。")
                .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted).fixedSize(horizontal: false, vertical: true)

            if let t = model.identify { running(t) } else { picker }

            if let error {
                Text(error).font(Tokens.Font.body).foregroundStyle(Tokens.Palette.problem).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                if model.identify?.outcome == nil, model.identify != nil {
                    Button("现在判定") { model.finishIdentify() }
                }
                if model.identify?.outcome != nil {
                    Button("再测一支") { model.cancelIdentify(); source = nil }
                }
                Button("关闭") { model.cancelIdentify(); close() }.keyboardShortcut(.cancelAction)
                if model.identify == nil {
                    Button("开始") {
                        guard let s = source else { return }
                        error = model.startIdentify(source: s)?.text
                    }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Tokens.Palette.accent)
                    .disabled(source == nil)
                }
            }
        }
        .padding(Tokens.Space.xl)
        .frame(width: 560)
        .background(Tokens.Palette.bg)
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            ForEach(sources, id: \.0) { device, refs in
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text(device).font(Tokens.Font.caption.weight(.semibold)).foregroundStyle(Tokens.Palette.textMuted)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 4), count: 7), alignment: .leading, spacing: 4) {
                        ForEach(refs, id: \.self) { r in
                            Button { source = r; error = nil } label: {
                                Text("Mic \(r.channel)").font(Tokens.Font.caption).frame(width: 60, height: 22)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(source == r ? Tokens.Palette.accent.opacity(0.3) : Tokens.Palette.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(source == r ? Tokens.Palette.accent : Tokens.Palette.border))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let s = source {
                let e = model.expectedXTInputs(from: s)
                Text(verbatim: e.isEmpty ? "按当前接线和路由，\(model.shortName(s)) 到不了 XT。"
                     : "按当前接线和路由，\(model.shortName(s)) 应该出现在：" + e.keys.sorted().map(model.shortName).joined(separator: "、"))
                    .font(Tokens.Font.body).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func running(_ t: IdentifyTest) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text(verbatim: "\(model.shortName(t.source)) · 应出现在 " + t.expected.map(model.shortName).joined(separator: "、"))
                .font(Tokens.Font.body.weight(.semibold))
            switch t.outcome {
            case nil:
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let left = max(0, Int(IdentifyTest.duration - ctx.date.timeIntervalSince(t.startedAt)))
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        Text("请对着这支麦克风说话或轻拍……还剩 \(left) 秒").foregroundStyle(Tokens.Palette.accent)
                        if let top = model.identify?.candidates.first {
                            Text(verbatim: "目前最明显：\(model.shortName(top))").font(Tokens.Font.caption)
                        }
                    }
                }
            case let .match(hit)?:
                Label("一致：声音进了 \(model.shortName(hit))。路上的线已记为“已用信号核对”。", systemImage: "checkmark.circle")
                    .foregroundStyle(Tokens.Palette.ok).fixedSize(horizontal: false, vertical: true)
            case let .elsewhere(found, expected)?:
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Label("对不上：声音出现在 \(model.shortName(found))，预期是 \(expected.map(model.shortName).joined(separator: "、"))。",
                          systemImage: "exclamationmark.triangle").foregroundStyle(Tokens.Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(found.portID != expected.first?.portID
                         ? "进了另一个口：多半是线插反了，或接线表填错。到“设置 → 接线”里按实物改。"
                         : "口对了但通道不同：发出这一路的设备（如 12Mic）路由和预期不同。到“输出”页看它的路由。")
                        .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("去接线页") { model.showWiring(); model.cancelIdentify(); close() }
                        Button("去输出页") { model.section = .outputs; model.cancelIdentify(); close() }
                    }
                }
            case .none?:
                Label("没检测到：10 秒内 XT 没有任何输入明显变响。查一下线、增益、静音，或换支麦克风再试。", systemImage: "questionmark.circle")
                    .foregroundStyle(Tokens.Palette.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
