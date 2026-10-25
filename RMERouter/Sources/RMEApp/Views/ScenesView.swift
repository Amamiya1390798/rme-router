import SwiftUI
import RMECore

/// “场景”页（文档第 7.6 节，痛点 9）：保存整套状态，对比，恢复。
public struct ScenesView: View {
    @Bindable var model: AppModel
    @State private var name = ""
    @State private var comparing: UUID?
    @State private var deleting: StudioScene?
    @State private var errors: [String] = []

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                ViewHeader(title: "场景", subtitle: "把整套设置（TotalMix 发送与通道条、前级、12Mic 和 XTC 路由）存下来，之后对比或恢复。恢复前一定会让你确认。")
                saveCard
                ForEach(errors, id: \.self) { Text($0).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.problem) }
                if model.scenes.isEmpty {
                    Text("还没有保存过场景。").font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
                }
                ForEach(model.scenes) { sceneCard($0) }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(Tokens.Space.xl)
        }
        .background(Tokens.Palette.bg)
        .confirmationDialog("删除场景“\(deleting?.name ?? "")”？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) { if let d = deleting { model.deleteScene(d.id) }; deleting = nil }
        } message: {
            Text("只删除 App 里保存的场景文件，不会改动设备。")
        }
    }

    private var saveCard: some View {
        let devices = model.sceneDevices
        return VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("保存当前设置").font(Tokens.Font.cardTitle)
            HStack {
                TextField("场景名称，例如“周日乐队排练”", text: $name).frame(width: 320)
                Button("保存") {
                    if model.saveScene(named: name) != nil { name = "" }
                }
                .disabled(devices.isEmpty)
            }
            Text(devices.isEmpty
                 ? "还没有读到任何设备，不能保存（演示数据不会存进场景）。"
                 : "会保存：" + devices.map { $0 == "xt" ? "MADIface XT（TotalMix）" : "12Mic" }.joined(separator: "、") + "。XTC 没有可读协议，不在场景里。")
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func sceneCard(_ scene: StudioScene) -> some View {
        let diffs = comparing == scene.id ? model.diff(scene) : []
        return VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(scene.name).font(Tokens.Font.cardTitle)
                Text(scene.date.formatted(date: .abbreviated, time: .shortened))
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                Spacer()
                Button(comparing == scene.id ? "收起" : "对比") { comparing = comparing == scene.id ? nil : scene.id }
                Button("恢复…") { errors = model.restore(scene) }
                    .help("把差异加入待应用，并打开确认框")
                Button { deleting = scene } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(Tokens.Palette.textMuted).help("删除这个场景")
            }
            Text(scene.summary).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            if comparing == scene.id {
                Rectangle().fill(Tokens.Palette.border).frame(height: 1)
                if diffs.isEmpty {
                    Label("和当前设置一致", systemImage: "checkmark.circle")
                        .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.ok)
                } else {
                    Text("\(diffs.count) 处不同").font(Tokens.Font.body)
                    ForEach(diffs.prefix(30)) { d in
                        Text(verbatim: d.text).font(Tokens.Font.caption).fixedSize(horizontal: false, vertical: true)
                    }
                    if diffs.count > 30 {
                        Text("还有 \(diffs.count - 30) 处").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                    }
                }
                let missing = scene.devices.filter { !model.sceneDevices.contains($0) }
                if !missing.isEmpty {
                    Text("现在读不到：" + missing.joined(separator: "、") + "，这部分没有比较，恢复时也会跳过。")
                        .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.warn)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
