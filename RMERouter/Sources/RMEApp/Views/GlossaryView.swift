import SwiftUI

/// “设置 → TotalMix 对照”（文档第 6.8 节）：TotalMix 菜单、设置窗口、通道条上每一项的中文意思，以及本 App 能不能做。
struct GlossaryView: View {
    @State private var query = ""

    var body: some View {
        let sections = TotalMixGlossary.search(query)
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                ViewHeader(title: "TotalMix 对照", subtitle: "TotalMix 里每个菜单、设置、按钮是什么意思，在本 App 里能不能做。出处：TotalMix 自带帮助与程序里的文字。")
                HStack(spacing: Tokens.Space.m) {
                    TextField("搜索，例如 Send Level、对讲、Talkback", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                    legend(.done); legend(.required); legend(.planned); legend(.no)
                }
                if sections.isEmpty {
                    Text("没找到").font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
                }
                ForEach(sections) { sec in
                    VStack(alignment: .leading, spacing: Tokens.Space.s) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(sec.title).font(Tokens.Font.cardTitle)
                            Text(sec.path).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                        }
                        Grid(alignment: .leading, horizontalSpacing: Tokens.Space.m, verticalSpacing: Tokens.Space.s) {
                            ForEach(sec.rows) { r in
                                GridRow(alignment: .firstTextBaseline) {
                                    Text(r.en).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
                                        .frame(width: 260, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.zh).font(Tokens.Font.body).fixedSize(horizontal: false, vertical: true)
                                        if !r.note.isEmpty {
                                            Text(r.note).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    status(r).frame(width: 200, alignment: .leading)
                                }
                            }
                        }
                    }
                    .card()
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(Tokens.Space.xl)
        }
        .background(Tokens.Palette.bg)
    }

    private static func label(_ a: GlossaryRow.App) -> (String, Color) {
        switch a {
        case .done: return ("本 App 能做", Tokens.Palette.ok)
        case .required: return ("本 App 需要这样设", Tokens.Palette.accent)
        case .planned: return ("计划做", Tokens.Palette.warn)
        case .no: return ("只能在 TotalMix 里", Tokens.Palette.unknown)
        case .info: return ("说明", Tokens.Palette.textMuted)
        }
    }

    private func legend(_ a: GlossaryRow.App) -> some View {
        let (t, c) = Self.label(a)
        return HStack(spacing: 4) { Circle().fill(c).frame(width: 7, height: 7); Text(t).font(Tokens.Font.caption) }
            .foregroundStyle(Tokens.Palette.textMuted)
    }

    private func status(_ r: GlossaryRow) -> some View {
        let (t, c) = Self.label(r.app)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) { Circle().fill(c).frame(width: 7, height: 7); Text(t).font(Tokens.Font.caption).foregroundStyle(c) }
            if !r.appWhere.isEmpty {
                Text(r.appWhere).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
