import SwiftUI
import RMECore
import RMEAdapters

/// 设备页的“这台 Mac”卡片（文档第 6.6 节）：点开看 XT 的连接、采样率、在用的程序，可改采样率。
struct MacNodeCard: View {
    @Bindable var model: AppModel
    @State private var open = false

    private var lines: [String] {
        guard let a = model.xtAudio else {
            return [model.audioChecked ? "没找到 XT（没接或驱动没装）" : "还没读取"]
        }
        var l = ["\(a.transport) · \(a.sampleRate.map(AppModel.rateText) ?? "?") · \(a.inputs) 入 / \(a.outputs) 出"]
        let clients = model.xtAudioClients
        l.append(clients.isEmpty ? "没有程序在用 XT" : "在用：" + clients.map(\.name).joined(separator: "、"))
        return l
    }

    var body: some View {
        Button { open = true } label: {
            NodeCard(title: "这台 Mac", lines: lines, color: Color(hex: 0x9B8BD6))
        }
        .buttonStyle(.plain)
        .help("点开看 XT 与电脑的连接、采样率、哪些程序在用")
        .popover(isPresented: $open, arrowEdge: .bottom) { MacDetail(model: model) }
    }
}

struct MacDetail: View {
    @Bindable var model: AppModel
    @State private var pendingRate: Double?
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("这台 Mac").font(Tokens.Font.cardTitle)
            if let a = model.xtAudio {
                Grid(alignment: .leading, horizontalSpacing: Tokens.Space.m, verticalSpacing: Tokens.Space.s) {
                    row("设备", a.name)
                    row("连接方式", a.transport)
                    row("录音 / 回放", "\(a.inputs) 路 / \(a.outputs) 路")
                    row("采样率", a.sampleRate.map(AppModel.rateText) ?? "读不到")
                }
                .font(Tokens.Font.body)
                if !a.availableRates.isEmpty {
                    HStack {
                        Text("改采样率").foregroundStyle(Tokens.Palette.textMuted)
                        ForEach(a.availableRates, id: \.self) { r in
                            Button(AppModel.rateText(r)) { pendingRate = r }
                                .disabled(busy || abs((a.sampleRate ?? 0) - r) < 1)
                        }
                    }
                    .font(Tokens.Font.caption)
                }
                Divider()
                Text("在用 XT 的程序").font(Tokens.Font.caption.weight(.semibold)).foregroundStyle(Tokens.Palette.textMuted)
                let clients = model.xtAudioClients
                if clients.isEmpty {
                    Text("没有").font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
                }
                ForEach(clients, id: \.name) { c in
                    HStack {
                        Text(c.name).font(Tokens.Font.body)
                        Spacer()
                        Text([c.input ? "录音" : nil, c.output ? "放音" : nil].compactMap { $0 }.joined(separator: " + "))
                            .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                    }
                }
                Text("录音通道 n = XT 硬件输入 n（固定）；回放通道 n = TotalMix 软件回放 n。")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("系统里没找到 MADIface XT：检查 USB / PCIe 线和 RME 驱动。")
                    .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            if let message {
                Text(message).font(Tokens.Font.caption).foregroundStyle(message.hasPrefix("已") ? Tokens.Palette.ok : Tokens.Palette.problem)
            }
            HStack {
                Spacer()
                Button("重新读取") { model.refreshAudio() }
            }
        }
        .padding(Tokens.Space.l)
        .frame(width: 360)
        .onAppear { model.refreshAudio() }
        .confirmationDialog("把 XT 的采样率改成 \(pendingRate.map(AppModel.rateText) ?? "")？",
                            isPresented: Binding(get: { pendingRate != nil }, set: { if !$0 { pendingRate = nil } })) {
            Button("改") {
                guard let r = pendingRate else { return }
                busy = true
                Task {
                    let e = await model.setXTSampleRate(r)
                    message = e ?? "已改为 \(AppModel.rateText(r))，读回一致"
                    busy = false
                    pendingRate = nil
                }
            }
            Button("取消", role: .cancel) { pendingRate = nil }
        } message: {
            Text("整条时钟链会换速度：12Mic、XTC 要跟着改，否则会失锁。正在录音或播放的程序会中断一下。")
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(Tokens.Palette.textMuted)
            Text(v)
        }
    }
}
