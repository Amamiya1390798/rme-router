import SwiftUI
import RMECore
import RMEAdapters

public struct EQTarget: Identifiable, Equatable, Sendable {
    public var ref: ChannelRef
    public var name: String
    public var id: ChannelRef { ref }
}

/// EQ 窗口（文档第 7.8 节“EQ 与低切”）：频响曲线 + 三段参数 EQ + 低切。改动进待应用 / 快速方式。
struct EQEditor: View {
    var model: AppModel
    var target: EQTarget
    var close: () -> Void

    @State private var enabled = false
    @State private var gain: [Double] = [0, 0, 0]
    @State private var freq: [Double] = [80, 1000, 5000]
    @State private var q: [Double] = [1, 1, 1]
    @State private var lcOn = false
    @State private var lcFreq: Double = 20
    @State private var error: String?

    private func shown(_ p: TotalMixStripParam) -> Double? { model.pendingStrip(target.ref, p) ?? model.stripValue(target.ref, p) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack {
                Text("EQ · \(target.name)").font(Tokens.Font.cardTitle)
                Text(target.ref.description).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
                Spacer()
                Toggle("EQ 开", isOn: $enabled).toggleStyle(.switch).controlSize(.small)
                Toggle("低切", isOn: $lcOn).toggleStyle(.switch).controlSize(.small)
            }
            EQCurve(enabled: enabled, gain: gain, freq: freq, q: q, lowCut: lcOn ? lcFreq : nil)
                .frame(height: 180)
            HStack(alignment: .top, spacing: Tokens.Space.l) {
                ForEach(0 ..< 3, id: \.self) { i in band(i) }
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    Text("低切").font(Tokens.Font.caption.weight(.semibold))
                    row("频率", TotalMixStripParam.lcFreq.text(lcFreq))
                    Slider(value: logBinding($lcFreq, 20, 500), in: 0 ... 1)
                    readOnly("斜率", .lcSlope)
                }
                .frame(width: 150)
                .opacity(lcOn ? 1 : 0.5)
            }
            Text("XT 每个通道就是 3 段 EQ + 低切（硬件上限）。第 1、3 段类型和低切斜率在协议里是序号，含义还没核对，先只显示；曲线按峰值型、12 dB/oct 低切示意。")
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.problem) }
            HStack {
                Button("增益归零") { gain = [0, 0, 0] }
                Spacer()
                Button("取消", action: close).keyboardShortcut(.cancelAction)
                Button(ConfirmMode.current.applyLabel, action: apply).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Space.l)
        .frame(width: 720)
        .onAppear(perform: load)
    }

    private func band(_ i: Int) -> some View {
        let p = TotalMixStripParam.eqBand(i + 1)
        return VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("第 \(i + 1) 段").font(Tokens.Font.caption.weight(.semibold))
            row("增益", p.gain.text(gain[i]))
            Slider(value: $gain[i], in: -20 ... 20, step: 0.5)
            row("频率", p.freq.text(freq[i]))
            Slider(value: logBinding($freq[i], 20, 20000), in: 0 ... 1)
            row("Q", String(format: "%.1f", q[i]))
            Slider(value: $q[i], in: 0.7 ... 5.0, step: 0.1)
            if i == 0 { readOnly("类型", .eqB1Type) }
            if i == 2 { readOnly("类型", .eqB3Type) }
            if i == 1 { row("类型", "峰值（固定）") }
        }
        .frame(width: 150)
        .opacity(enabled ? 1 : 0.5)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted); Spacer(); Text(v).font(Tokens.Font.mono) }
    }

    private func readOnly(_ k: String, _ p: TotalMixStripParam) -> some View {
        row(k, model.stripValue(target.ref, p).map { p.text($0) } ?? "?")
            .help("取值含义还没核对，暂时只读")
    }

    /// 频率滑块用对数刻度。
    private func logBinding(_ v: Binding<Double>, _ lo: Double, _ hi: Double) -> Binding<Double> {
        Binding(get: { log(v.wrappedValue / lo) / log(hi / lo) },
                set: { v.wrappedValue = (lo * pow(hi / lo, $0)).rounded() })
    }

    private func load() {
        enabled = (shown(.eqEnable) ?? 0) >= 0.5
        lcOn = (shown(.lcEnable) ?? 0) >= 0.5
        lcFreq = shown(.lcFreq) ?? 20
        for i in 0 ..< 3 {
            let p = TotalMixStripParam.eqBand(i + 1)
            gain[i] = shown(p.gain) ?? 0; freq[i] = shown(p.freq) ?? freq[i]; q[i] = shown(p.q) ?? 1
        }
    }

    /// 只暂存和当前不同的项。
    private func apply() {
        var changes: [(TotalMixStripParam, Double)] = [(.eqEnable, enabled ? 1 : 0), (.lcEnable, lcOn ? 1 : 0), (.lcFreq, lcFreq)]
        for i in 0 ..< 3 {
            let p = TotalMixStripParam.eqBand(i + 1)
            changes += [(p.gain, gain[i]), (p.freq, freq[i]), (p.q, q[i])]
        }
        error = nil
        for (p, v) in changes where !PendingStripChange.same(p, shown(p), p.clamp(v)) {
            if let e = model.stageStrip(target.ref, p, v) { error = e.text; return }
        }
        Task { await model.commitIfQuick() }
        close()
    }
}

/// 频响曲线（示意）：三段峰值型 + 2 阶高通低切，48 kHz 双二阶滤波器的幅度响应。
struct EQCurve: View {
    var enabled: Bool
    var gain: [Double]
    var freq: [Double]
    var q: [Double]
    var lowCut: Double?

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func x(_ f: Double) -> CGFloat { CGFloat(log10(f / 20) / 3) * w }
            func y(_ dB: Double) -> CGFloat { h / 2 - CGFloat(dB / 24) * (h / 2) }
            // 网格
            var grid = Path()
            for f in [50.0, 100, 200, 500, 1000, 2000, 5000, 10000] { grid.move(to: CGPoint(x: x(f), y: 0)); grid.addLine(to: CGPoint(x: x(f), y: h)) }
            for d in [-12.0, 0, 12] { grid.move(to: CGPoint(x: 0, y: y(d))); grid.addLine(to: CGPoint(x: w, y: y(d))) }
            ctx.stroke(grid, with: .color(Tokens.Palette.border), lineWidth: 0.5)
            for (f, t) in [(100.0, "100"), (1000, "1k"), (10000, "10k")] {
                ctx.draw(Text(t).font(.system(size: 9)).foregroundColor(Tokens.Palette.textMuted), at: CGPoint(x: x(f) + 10, y: h - 8))
            }
            // 曲线
            var path = Path()
            for i in 0 ... 200 {
                let f = 20 * pow(1000, Double(i) / 200)
                var dB = 0.0
                if enabled { for b in 0 ..< 3 { dB += Self.peak(f, f0: freq[b], gain: gain[b], q: q[b]) } }
                if let lc = lowCut { dB += Self.highPass(f, f0: lc) }
                let p = CGPoint(x: x(f), y: y(max(min(dB, 24), -24)))
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            ctx.stroke(path, with: .color(Tokens.Palette.accent), lineWidth: 2)
            if enabled {
                for b in 0 ..< 3 {
                    let c = CGPoint(x: x(freq[b]), y: y(gain[b]))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(Tokens.Palette.accent))
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Tokens.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.Palette.border))
    }

    static let fs = 48000.0

    /// RBJ 峰值滤波器在频率 f 处的增益（dB）。
    static func peak(_ f: Double, f0: Double, gain: Double, q: Double) -> Double {
        let A = pow(10, gain / 40), w0 = 2 * .pi * f0 / fs, alpha = sin(w0) / (2 * q)
        let b = [1 + alpha * A, -2 * cos(w0), 1 - alpha * A], a = [1 + alpha / A, -2 * cos(w0), 1 - alpha / A]
        return magnitudeDB(b, a, f)
    }

    /// 2 阶巴特沃斯高通（示意低切）。
    static func highPass(_ f: Double, f0: Double) -> Double {
        let w0 = 2 * .pi * f0 / fs, alpha = sin(w0) / (2 * 0.7071)
        let c = cos(w0)
        let b = [(1 + c) / 2, -(1 + c), (1 + c) / 2], a = [1 + alpha, -2 * c, 1 - alpha]
        return magnitudeDB(b, a, f)
    }

    static func magnitudeDB(_ b: [Double], _ a: [Double], _ f: Double) -> Double {
        let w = 2 * .pi * f / fs
        func h(_ k: [Double]) -> (Double, Double) {
            (k[0] + k[1] * cos(w) + k[2] * cos(2 * w), -(k[1] * sin(w) + k[2] * sin(2 * w)))
        }
        let (nr, ni) = h(b), (dr, di) = h(a)
        let mag = sqrt(nr * nr + ni * ni) / sqrt(dr * dr + di * di)
        return 20 * log10(max(mag, 1e-9))
    }
}
