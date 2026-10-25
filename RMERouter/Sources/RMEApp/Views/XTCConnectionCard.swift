import SwiftUI
import RMECore
import RMEAdapters

/// “连接”页的 XTC 一节（文档第 6.3 节）：端点、设备 ID、读取开关、改动开关。全部默认关。
struct XTCConnectionCard: View {
    @Bindable var model: AppModel
    @State private var sources: [String] = []
    @State private var destinations: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("OctaMic XTC（MIDI）").font(Tokens.Font.cardTitle)
            Grid(alignment: .leading, horizontalSpacing: Tokens.Space.m, verticalSpacing: Tokens.Space.s) {
                GridRow {
                    Text("从 XTC 收（MIDI 输入）").foregroundStyle(Tokens.Palette.textMuted)
                    endpointPicker(selection: $model.xtcSettings.sourceName, names: sources)
                }
                GridRow {
                    Text("发往 XTC（MIDI 输出）").foregroundStyle(Tokens.Palette.textMuted)
                    endpointPicker(selection: $model.xtcSettings.destinationName, names: destinations)
                }
                GridRow {
                    Text("设备 ID").foregroundStyle(Tokens.Palette.textMuted)
                    Picker("设备 ID", selection: $model.xtcSettings.midiDeviceID) {
                        ForEach(0 ..< 8) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden().frame(width: 80)
                }
            }
            .font(Tokens.Font.body)
            Button("刷新端点列表") { reloadEndpoints() }

            Toggle("读取 XTC（只发“请求全部参数”，不改设置）", isOn: $model.xtcSettings.readEnabled)
                .disabled(!model.xtcSettings.endpointsChosen)
            Toggle(isOn: $model.xtcSettings.auxDeviceOff) {
                Text("我已确认 TotalMix 的 Aux Device 和 MIDI Remote 没有在控制 XTC")
            }
            .toggleStyle(.checkbox)
            .disabled(!model.xtcSettings.readEnabled)
            Toggle("允许本 App 改动 XTC（路由、增益、反相、48V）", isOn: $model.xtcSettings.writeEnabled)
                .disabled(!model.xtcSettings.readEnabled || !model.xtcSettings.auxDeviceOff)

            HStack {
                Button("读取 XTC") { Task { await model.refreshXTC() } }
                    .disabled(!model.xtcSettings.readEnabled || model.xtcStatus == .loading)
                status
            }
            Text("XTC 只接受一个控制来源：本 App、TotalMix Aux Device、MIDI Remote 三者同时只能用一个。不打开“读取 XTC”时，本 App 不向 XTC 发任何消息，XTC 显示演示数据。XTC 面板 Options → MIDI Sources 要允许你选的端口（USB 或 MADI）。")
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Tokens.Font.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .onAppear { reloadEndpoints() }
    }

    @ViewBuilder private var status: some View {
        switch model.xtcStatus {
        case .off: EmptyView()
        case .loading: Text("正在读取…").foregroundStyle(Tokens.Palette.textMuted)
        case .live:
            Label(model.xtcWritable ? "已读到；允许改动" : "已读到（只读）", systemImage: "checkmark.circle")
                .foregroundStyle(Tokens.Palette.ok)
        case let .unreachable(r): Text(r).foregroundStyle(Tokens.Palette.problem).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func endpointPicker(selection: Binding<String>, names: [String]) -> some View {
        // 当前选的端点不在列表里（XTC 没接上）时也保留它，不悄悄清掉。
        let all = (names.contains(selection.wrappedValue) || selection.wrappedValue.isEmpty) ? names : [selection.wrappedValue] + names
        return Picker("端点", selection: selection) {
            Text("未选择").tag("")
            ForEach(all, id: \.self) { n in
                Text(names.contains(n) ? n : "\(n)（未找到）").tag(n)
            }
        }
        .labelsHidden().frame(width: 260)
    }

    private func reloadEndpoints() {
        sources = MIDIEndpoints.sources()
        destinations = MIDIEndpoints.destinations()
    }
}
