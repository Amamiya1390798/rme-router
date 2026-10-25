import SwiftUI
import UniformTypeIdentifiers
import RMECore
import RMEAdapters

/// MADIface XT 的 TotalMix 式通道条（文档第 6.4.2、6.4.3 节）：
/// 硬件输入（= 电脑录音）、软件回放（DAW 送来）、硬件输出三行；选一个输出，上两行显示送到它的电平。
/// 把上面一条拖到下面一条 = 新建发送（-30 dB 起步，进待应用栏）。
struct XTStripsView: View {
    @Bindable var model: AppModel
    var onlySignal: Bool
    @State private var output: TotalMixChannel?

    private var outputs: [XTStrip] { model.xtStrips(.output) }
    private var current: XTStrip? { outputs.first { $0.tm == output } ?? outputs.first }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("MADIface XT · 通道条").font(Tokens.Font.cardTitle)
                if let c = current {
                    Text(verbatim: "上两行显示送到「\(c.name)」的电平").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                }
                Spacer()
                Text("拖上面一条到下面一条 = 新建发送（-30 dB）").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            if outputs.isEmpty {
                Text("还没有从 TotalMix 读到通道。在“连接”页确认端口后点“读取设备”。")
                    .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
            } else {
                row("硬件输入", sub: "= 电脑录音", strips: filtered(model.xtStrips(.input)))
                row("软件回放", sub: "DAW 送来", strips: filtered(model.xtStrips(.playback)))
                row("硬件输出", sub: nil, strips: outputs)
            }
        }
        .padding(Tokens.Space.m)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(Tokens.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(Tokens.Palette.border))
    }

    private func filtered(_ s: [XTStrip]) -> [XTStrip] {
        guard onlySignal else { return s }
        return s.filter { $0.ref.map { model.hasSignal($0) == true } ?? false }
    }

    private func row(_ title: String, sub: String?, strips: [XTStrip]) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Tokens.Font.caption.weight(.semibold))
                if let sub { Text(sub).font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted) }
            }
            .frame(width: 66, alignment: .leading)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 4) {
                    ForEach(strips) { s in
                        if s.tm.bus == .output {
                            OutputStrip(model: model, strip: s, selected: s.tm == current?.tm) { output = s.tm }
                        } else if let out = current {
                            SourceStrip(model: model, strip: s, output: out)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }
}

/// 输入 / 回放的一条：名字、电平、送到所选输出的电平（点了改）、静音与相位。可拖到输出条上。
struct SourceStrip: View {
    var model: AppModel
    var strip: XTStrip
    var output: XTStrip
    @State private var editing = false

    var body: some View {
        let send = model.xtSend(from: strip.tm, to: output.tm)
        let pending = strip.ref.flatMap { r in output.ref.flatMap { model.pendingGain(source: r, destination: $0) } }
        VStack(spacing: 4) {
            Text(strip.name).font(.system(size: 11, weight: .semibold)).lineLimit(1).frame(maxWidth: .infinity)
            if let ref = strip.ref { MeterBar(store: model.meters, ref: ref, width: 46) } else { Spacer().frame(height: 6) }
            Button { editing = true } label: {
                Group {
                    if let p = pending { Text(PendingChange.format(p)).foregroundStyle(Tokens.Palette.accent) }
                    else if let s = send { Text(String(format: "%.1f", s)).foregroundStyle(Tokens.Palette.accent) }
                    else { Text("—").foregroundStyle(Tokens.Palette.textMuted) }
                }
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 3).fill(Tokens.Palette.border.opacity(editing ? 1 : 0.4)))
            }
            .buttonStyle(.plain)
            .disabled(strip.ref == nil || output.ref == nil)
            .help("送到「\(output.name)」的电平；点了修改（先进待应用栏）")
            .popover(isPresented: $editing, arrowEdge: .bottom) {
                if let src = strip.ref, let dst = output.ref {
                    GainEditor(current: send, initial: pending ?? send, title: "\(strip.name) → \(output.name)") { dB in
                        if !StripControls.sameVolume(dB, send) || pending != nil {
                            if model.stageGain(source: src, destination: dst, dB: dB) == nil { Task { await model.commitIfQuick() } }
                        }
                        editing = false
                    }
                }
            }
            if let ref = strip.ref { MiniStripButtons(model: model, ref: ref) }
        }
        .padding(5)
        .frame(width: 72)
        .background(RoundedRectangle(cornerRadius: 6).fill(Tokens.Palette.bg))
        .opacity(strip.ref.flatMap { model.hasSignal($0) } == false ? 0.55 : 1)
        .draggable(strip.ref?.description ?? "") {
            Text(strip.name).font(Tokens.Font.caption).padding(6).background(Tokens.Palette.surface)
        }
    }
}

/// 硬件输出的一条：名字、电平、总音量、静音与相位。点选 = 上两行显示送到它的电平；接收拖来的来源。
struct OutputStrip: View {
    var model: AppModel
    var strip: XTStrip
    var selected: Bool
    var select: () -> Void
    @State private var dropTarget = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(strip.name).font(.system(size: 11, weight: .semibold)).lineLimit(1).frame(maxWidth: .infinity)
            if let ref = strip.ref { MeterBar(store: model.meters, ref: ref, width: 46) } else { Spacer().frame(height: 6) }
            let vol = strip.ref.flatMap { model.stripValue($0, .volume) }
            Text(TotalMixStripParam.volume.text(vol)).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Tokens.Palette.textMuted)
            if let ref = strip.ref { MiniStripButtons(model: model, ref: ref) }
        }
        .padding(5)
        .frame(width: 72)
        .background(RoundedRectangle(cornerRadius: 6).fill(Tokens.Palette.bg))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(dropTarget || selected ? Tokens.Palette.accent : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .help(message ?? "点选：上两行显示送到这里的电平；把来源拖到这里新建发送")
        .dropDestination(for: String.self) { items, _ in
            guard let text = items.first, let src = ChannelRef(text: text), let dst = strip.ref else { return false }
            if let e = model.stageNewSend(source: src, destination: dst) { message = e.text; return false }
            Task { await model.commitIfQuick() }
            select()
            return true
        } isTargeted: { dropTarget = $0 }
    }
}

/// 通道条上的小按钮：静音 M、相位 Ø（第 7.8 节，走待应用栏）。
struct MiniStripButtons: View {
    var model: AppModel
    var ref: ChannelRef

    var body: some View {
        HStack(spacing: 3) {
            chip("M", .mute, on: Tokens.Palette.problem)
            chip("Ø", .phase, on: Tokens.Palette.warn)
        }
    }

    private func chip(_ label: String, _ p: TotalMixStripParam, on color: Color) -> some View {
        let now = model.stripValue(ref, p), pend = model.pendingStrip(ref, p)
        let isOn = ((pend ?? now) ?? 0) >= 0.5
        return Button {
            if model.stageStrip(ref, p, isOn ? 0 : 1) == nil { Task { await model.commitIfQuick() } }
        } label: {
            Text(label).font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 15)
                .background(RoundedRectangle(cornerRadius: 3).fill(isOn ? color.opacity(0.35) : Tokens.Palette.border.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(pend != nil ? Tokens.Palette.accent : .clear))
                .foregroundStyle(isOn ? Tokens.Palette.text : Tokens.Palette.textMuted)
        }
        .buttonStyle(.plain)
        .disabled(now == nil)
        .help(p == .mute ? (isOn ? "取消静音（会出声，需要确认）" : "静音") : "切换相位")
    }
}
