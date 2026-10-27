import SwiftUI
import RMECore

/// “接线”页（阶段 A4）：设备之间的线缆。改动立即存盘，各页面同时更新。
public struct WiringView: View {
    @Bindable var model: AppModel
    @State private var from = ""
    @State private var to = ""
    @State private var error: String?
    @State private var confirmReset = false

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                ViewHeader(title: "接线", subtitle: "设备之间实际接了哪些线。信号流、体检、时钟、跨设备送声都按这张表计算；改动立即保存。", mood: .determined)
                if model.linkStore.load() == nil {
                    // 没改过接线时用的是默认接法（2026-10-27：用户指出没告诉过这是默认）
                    Label("现在用的是默认接法（XTC 在 XT 的 MADI 1、12Mic 在 MADI 2）。和实际不一样就在下面改，改过之后按你的保存。", systemImage: "info.circle")
                        .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.warn)
                }
                linkList
                addCard
                HStack {
                    Text(model.linksCustomized ? "已改过默认接线。" : "当前是默认接线。")
                        .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                    Spacer()
                    Button("恢复默认接线…") { confirmReset = true }.disabled(!model.linksCustomized)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(Tokens.Space.xl)
        }
        .pageBackground()
        .confirmationDialog("恢复默认接线？", isPresented: $confirmReset) {
            Button("恢复默认", role: .destructive) { model.resetLinks() }
        } message: {
            Text("你加的线会被删掉，删掉的默认线会回来。")
        }
        .onAppear {
            if from.isEmpty { from = model.wiringOutputs.first?.id ?? "" }
            if to.isEmpty { to = model.wiringInputs.first?.id ?? "" }
        }
    }

    private var linkList: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("\(model.links.count) 根线").font(Tokens.Font.cardTitle)
            ForEach(model.links) { link in
                let issues = model.linkIssues[link.id] ?? []
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Tokens.Space.s) {
                        EvidenceDot(issues.contains(where: \.isError) ? .conflict : .documented)
                        Text(verbatim: label(link.from)).font(Tokens.Font.body)
                        Text("⇒").foregroundStyle(Tokens.Palette.textMuted)
                        Text(verbatim: label(link.to)).font(Tokens.Font.body)
                        Spacer()
                        Button { model.removeLink(link.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(Tokens.Palette.textMuted).help("删掉这根线")
                    }
                    Text(verbatim: "\(link.from) ⇒ \(link.to)").font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Text(issue.description).font(Tokens.Font.caption)
                            .foregroundStyle(issue.isError ? Tokens.Palette.problem : Tokens.Palette.warn)
                    }
                }
                .padding(.vertical, Tokens.Space.xs)
                Rectangle().fill(Tokens.Palette.border).frame(height: 1)
            }
            if model.links.isEmpty {
                Text("还没有任何线。").font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("加一根线").font(Tokens.Font.cardTitle)
            Grid(alignment: .leading, horizontalSpacing: Tokens.Space.m, verticalSpacing: Tokens.Space.s) {
                GridRow {
                    Text("从（输出）").foregroundStyle(Tokens.Palette.textMuted)
                    portPicker($from, ports: model.wiringOutputs)
                }
                GridRow {
                    Text("到（输入）").foregroundStyle(Tokens.Palette.textMuted)
                    portPicker($to, ports: model.wiringInputs)
                }
            }
            .font(Tokens.Font.body)
            if let error { Text(error).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.problem) }
            Button("添加") { error = model.addLink(from: from, to: to) }
                .disabled(from.isEmpty || to.isEmpty)
            Text("MADI 是单向的：两台设备之间通常要接来回两根（体检 R6 会检查）。")
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .onChange(of: from) { error = nil }
        .onChange(of: to) { error = nil }
    }

    private func label(_ portID: String) -> String {
        guard let p = model.snapshot.topology.port(portID) else { return portID }
        return "\(model.snapshot.topology.device(p.deviceID)?.name ?? p.deviceID) · \(p.name)"
    }

    private func portPicker(_ selection: Binding<String>, ports: [RMECore.Port]) -> some View {
        Picker("", selection: selection) {
            ForEach(ports, id: \.id) { p in Text(verbatim: label(p.id)).tag(p.id) }
        }
        .labelsHidden()
        .frame(width: 320)
    }
}
