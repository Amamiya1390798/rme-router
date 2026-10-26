import SwiftUI
import RMEAdapters

/// 通道条搜索框（文档第 6.4.5 节）：⌘F 进入，按名字、源头、通道号找，↑↓ 选、回车跳过去，Esc 清空。
struct StripSearchField: View {
    var model: AppModel
    /// 输入时为 true（⌘A 留给搜索框全选文字）。
    @Binding var editing: Bool
    var go: (TotalMixChannel) -> Void
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool
    @Environment(\.pageActive) private var pageActive

    var body: some View {
        // 有字就列结果（不依赖焦点状态）；跳过去后清空
        let hits = model.searchStrips(query)
        TextField("搜索通道条（⌘F）", text: $query)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 110, idealWidth: 220, maxWidth: 220)   // 窗口窄时先缩搜索框，别挤别的按钮
            .focused($focused)
            .onChange(of: focused) { editing = focused || !query.isEmpty }
            .onChange(of: query) { index = 0; editing = focused || !query.isEmpty }
            .onSubmit { pick(hits) }
            .onKeyPress(.downArrow) { index = min(index + 1, max(hits.count - 1, 0)); return .handled }
            .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
            .onExitCommand { query = ""; focused = false }
            .background {
                if pageActive { Button("搜索通道条") { focused = true }.keyboardShortcut("f", modifiers: .command).hidden() }
            }
            .overlay(alignment: .topLeading) {
                if !hits.isEmpty { results(hits).offset(y: 28) }
                else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("没找到").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                        .padding(Tokens.Space.s).frame(width: 220, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Tokens.Palette.surface).shadow(radius: 6))
                        .offset(y: 28)
                }
            }
    }

    private func pick(_ hits: [StripHit]) {
        guard hits.indices.contains(index) else { return }
        go(hits[index].strip.tm)
        query = ""
        focused = false
    }

    private func results(_ hits: [StripHit]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(hits.enumerated()), id: \.element.id) { i, h in
                VStack(alignment: .leading, spacing: 1) {
                    Text(h.strip.name).font(Tokens.Font.body)
                    Text(h.detail).font(Tokens.Font.caption).foregroundStyle(i == index ? Color.white.opacity(0.85) : Tokens.Palette.textMuted)
                        .lineLimit(1)
                }
                .foregroundStyle(i == index ? Color.white : Tokens.Palette.text)
                .padding(.horizontal, Tokens.Space.s).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4).fill(i == index ? Color(nsColor: .controlAccentColor) : .clear))
                .contentShape(Rectangle())
                .onTapGesture { index = i; pick(hits) }
                .onHover { if $0 { index = i } }
            }
        }
        .padding(4)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 8).fill(Tokens.Palette.surface).shadow(color: .black.opacity(0.3), radius: 8, y: 3))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.Palette.border))
    }
}
