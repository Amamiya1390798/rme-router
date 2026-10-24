import SwiftUI
import RMECore

/// “输出”视图：按设备分栏，每个在用的输出一张卡，列出送进来的声音。
public struct OutputsView: View {
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        GeometryReader { geo in
            ScrollView {
                OutputsContent(outputs: model.outputs, status: model.xtStatus, lastLoaded: model.lastLoaded,
                               demoDevices: demoNames, showPlayback: $model.showPlayback,
                               columns: max(1, Int((geo.size.width - 48) / 300))) { ref in
                    model.traceTarget = ref
                    model.section = .signalFlow
                }
                .padding(Tokens.Space.xl)
            }
        }
        .background(Tokens.Palette.bg)
    }

    private var demoNames: [String] {
        ["12mic", "xtc"].filter(model.isDemo).compactMap { model.snapshot.topology.device($0)?.name }
    }
}

/// 可渲染的内容部分（不含 ScrollView，便于 ImageRenderer 出图检查）。
public struct OutputsContent: View {
    var outputs: [DeviceOutputs]
    var status: XTStatus
    var lastLoaded: Date?
    var demoDevices: [String]
    @Binding var showPlayback: Bool
    var columns: Int
    var onSelectSource: (ChannelRef) -> Void = { _ in }

    public init(outputs: [DeviceOutputs], status: XTStatus, lastLoaded: Date?, demoDevices: [String],
                showPlayback: Binding<Bool>, columns: Int, onSelectSource: @escaping (ChannelRef) -> Void = { _ in }) {
        self.outputs = outputs
        self.status = status
        self.lastLoaded = lastLoaded
        self.demoDevices = demoDevices
        self._showPlayback = showPlayback
        self.columns = columns
        self.onSelectSource = onSelectSource
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            HStack(alignment: .top) {
                ViewHeader(title: "输出", subtitle: "每个在用的输出现在送出什么。点一路来源可以看它的完整路径。")
                Toggle("显示电脑回放", isOn: $showPlayback).toggleStyle(.switch).controlSize(.small)
                    .font(Tokens.Font.body).fixedSize()
            }
            StatusStrip(status: status, lastLoaded: lastLoaded, demoDevices: demoDevices)
            ForEach(outputs) { group in
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    HStack(spacing: Tokens.Space.s) {
                        Text(group.device.name).font(Tokens.Font.cardTitle).foregroundStyle(Tokens.Palette.text)
                        Text("\(group.cards.count) 个输出在用").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                        if demoDevices.contains(group.device.name) { Badge(text: "演示数据", color: Tokens.Palette.unknown) }
                    }
                    Grid(alignment: .topLeading, horizontalSpacing: Tokens.Space.m, verticalSpacing: Tokens.Space.m) {
                        ForEach(Array(rows(group.cards).enumerated()), id: \.offset) { _, row in
                            GridRow {
                                ForEach(row) { OutputCardView(card: $0, onSelectSource: onSelectSource) }
                                ForEach(0 ..< (columns - row.count), id: \.self) { _ in Color.clear.gridCellUnsizedAxes([.vertical]) }
                            }
                        }
                    }
                }
            }
            if outputs.isEmpty {
                Text("还没有在用的输出。").font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rows(_ cards: [OutputCard]) -> [[OutputCard]] {
        stride(from: 0, to: cards.count, by: columns).map { Array(cards[$0 ..< min($0 + columns, cards.count)]) }
    }
}

struct OutputCardView: View {
    var card: OutputCard
    var onSelectSource: (ChannelRef) -> Void
    static let visibleSources = 6

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Tokens.Font.cardTitle).foregroundStyle(Tokens.Palette.text)
                Spacer(minLength: Tokens.Space.s)
                EvidenceDot(card.evidence)
            }
            Text(card.address).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
            Rectangle().fill(Tokens.Palette.border).frame(height: 1)
            ForEach(Array(card.sources.prefix(Self.visibleSources).enumerated()), id: \.offset) { _, source in
                Button { onSelectSource(source.refs[0]) } label: {
                    HStack(spacing: Tokens.Space.s) {
                        EvidenceDot(source.evidence)
                        Text(source.label).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.text)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: Tokens.Space.s)
                        Text(source.kind.shortLabel).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if card.sources.count > Self.visibleSources {
                Text("还有 \(card.sources.count - Self.visibleSources) 路")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            if card.hiddenPlayback > 0 {
                Text("另有 \(card.hiddenPlayback) 路电脑回放")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var title: String {
        let chans = card.channels.count == 2 ? "\(card.channels[0])/\(card.channels[1])" : "\(card.channels[0])"
        return "\(card.port.name) · \(chans)"
    }
}
