import SwiftUI
import RMECore
import RMEEngine

/// “前级”视图：12Mic 的增益、48V、相位、标签（只读，文档第 6.2 节）。
/// 只显示读到的真实数据；读不到时不拿演示值充数。
public struct PreampsView: View {
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        GeometryReader { geo in
            ScrollView {
                PreampsContent(preamps: model.snapshot.devices["12mic"]?.preamps ?? [],
                               live: model.twelveMicStatus == .live,
                               status: model.twelveMicStatus,
                               trace: SignalTrace(snapshot: model.snapshot),
                               columns: max(1, Int((geo.size.width - 48) / 220))) { ref in
                    model.traceTarget = ref
                    model.section = .signalFlow
                }
                .padding(Tokens.Space.xl)
            }
        }
        .background(Tokens.Palette.bg)
    }
}

/// 可渲染的内容部分。
public struct PreampsContent: View {
    var preamps: [PreampChannel]
    var live: Bool
    var status: TwelveMicStatus
    var trace: SignalTrace
    var columns: Int
    var onSelect: (ChannelRef) -> Void

    public init(preamps: [PreampChannel], live: Bool, status: TwelveMicStatus, trace: SignalTrace, columns: Int,
                onSelect: @escaping (ChannelRef) -> Void = { _ in }) {
        self.preamps = preamps
        self.live = live
        self.status = status
        self.trace = trace
        self.columns = columns
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            ViewHeader(title: "前级", subtitle: "12Mic 每一路话放的增益、48V、相位和标签。目前只读；点一张卡可以看这一路送到哪里。")
            if live && !preamps.isEmpty {
                summary
                Grid(alignment: .topLeading, horizontalSpacing: Tokens.Space.m, verticalSpacing: Tokens.Space.m) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(row) { p in
                                PreampCard(preamp: p, destinations: trace.destinations(of: p.input))
                                    .onTapGesture { onSelect(p.input) }
                            }
                            ForEach(0 ..< (columns - row.count), id: \.self) { _ in Color.clear.gridCellUnsizedAxes([.vertical]) }
                        }
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: [[PreampChannel]] {
        stride(from: 0, to: preamps.count, by: columns).map { Array(preamps[$0 ..< min($0 + columns, preamps.count)]) }
    }

    /// 一行摘要：几路开着 48V、几路反相——开机前最容易出事的两项。
    private var summary: some View {
        let p48 = preamps.filter { $0.phantom.knownValue == true }.map(\.input.channel)
        let phase = preamps.filter { $0.phase.knownValue == true }.map(\.input.channel)
        return HStack(spacing: Tokens.Space.l) {
            Text("48V 开：" + (p48.isEmpty ? "无" : p48.map { "Mic \($0)" }.joined(separator: "、")))
            Text("反相：" + (phase.isEmpty ? "无" : phase.map { "Mic \($0)" }.joined(separator: "、")))
        }
        .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(spacing: Tokens.Space.s) {
                EvidenceDot(status == .loading ? .inferred : .unknown)
                Text(status == .loading ? "正在读取 12Mic…" : "还没有读到 12Mic 的前级").font(Tokens.Font.cardTitle)
            }
            Text("前级只显示从设备读到的真实数值，不显示演示值。接上 12Mic（网线或 USB），在“连接”页确认地址，打开设备上的 STATE → remote → HTTP Remote，然后点“读取设备”。")
                .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if case let .unreachable(reason) = status {
                Text(reason).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct PreampCard: View {
    var preamp: PreampChannel
    var destinations: [ChannelRef]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Tokens.Font.cardTitle).foregroundStyle(Tokens.Palette.text).lineLimit(1)
                Spacer(minLength: Tokens.Space.xs)
                if hasLabel {   // 没有标签时标题已经是 “Mic n”，不重复
                    Text("Mic \(preamp.input.channel)").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                }
            }
            Text(preamp.input.description).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
            Text(gainText).font(.system(size: 22, weight: .regular, design: .monospaced).monospacedDigit())
                .foregroundStyle(preamp.gainDB.knownValue == nil ? Tokens.Palette.unknown : Tokens.Palette.text)
            HStack(spacing: Tokens.Space.xs) {
                if preamp.phantom.knownValue == true { Badge(text: "48V", color: Tokens.Palette.warn) }
                if preamp.phase.knownValue == true { Badge(text: "Ø 反相", color: Tokens.Palette.accent) }
                if preamp.hiZ.knownValue == true { Badge(text: "Hi-Z", color: Tokens.Palette.textMuted) }
                if preamp.autoGain.knownValue == true { Badge(text: "AutoSet", color: Tokens.Palette.textMuted) }
                if let g = preamp.gainGroup.knownValue, !g.isEmpty, g != "0", g.lowercased() != "none" {
                    Badge(text: "组 \(g)", color: Tokens.Palette.textMuted)
                }
            }
            if !unknownFields.isEmpty {
                Text("读不到：" + unknownFields.joined(separator: "、"))
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.unknown)
            }
            Rectangle().fill(Tokens.Palette.border).frame(height: 1)
            Text(destinationText).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .card()
        .help("查看 \(preamp.input.description) 的信号流")
    }

    private var labelText: String? {
        guard let l = preamp.label.knownValue?.trimmingCharacters(in: .whitespaces), !l.isEmpty else { return nil }
        return l
    }
    private var hasLabel: Bool { labelText != nil }
    private var title: String { labelText ?? "Mic \(preamp.input.channel)" }

    private var gainText: String {
        guard let g = preamp.gainDB.knownValue else { return "? dB" }
        return String(format: "%+.1f dB", g)
    }

    private var unknownFields: [String] {
        [("增益", preamp.gainDB.knownValue == nil), ("48V", preamp.phantom.knownValue == nil),
         ("相位", preamp.phase.knownValue == nil)].filter(\.1).map(\.0)
    }

    private var destinationText: String {
        guard !destinations.isEmpty else { return "没有送到任何地方" }
        let shown = destinations.prefix(2).map(\.description).joined(separator: "、")
        return "送到 " + shown + (destinations.count > 2 ? " 等 \(destinations.count) 处" : "")
    }
}
