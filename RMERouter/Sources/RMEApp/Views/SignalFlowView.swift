import SwiftUI
import RMECore
import RMEEngine

/// “信号流”视图：选一个通道，画出它的全部去向与来源，每段一个状态点。
public struct SignalFlowView: View {
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        HSplitView {
            // 只在值真的变了才写：@Observable 对同值写入也会通知观察者，避免无谓的重建。
            CandidateList(groups: groupedCandidates,
                          selection: Binding(get: { model.traceTarget },
                                             set: { if model.traceTarget != $0 { model.traceTarget = $0 } }))
                .frame(minWidth: 200, idealWidth: 230, maxWidth: 320)

            ScrollView {
                if let target = model.traceTarget {
                    SignalFlowContent(target: target, deviceName: model.deviceName(of: target),
                                      trace: SignalTrace(snapshot: model.snapshot), deviceNameOf: model.deviceName(of:))
                        .padding(Tokens.Space.xl)
                } else {
                    ViewHeader(title: "信号流", subtitle: "在左边选一个来源通道。").padding(Tokens.Space.xl)
                }
            }
            .frame(minWidth: 420)
            .background(Tokens.Palette.bg)
        }
    }

    private var groupedCandidates: [CandidateList.Group] {
        var order: [String] = []
        var groups: [String: [ChannelRef]] = [:]
        for ref in model.traceCandidates {
            let name = model.deviceName(of: ref)
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(ref)
        }
        return order.map { CandidateList.Group(device: $0, refs: groups[$0]!) }
    }
}

/// 可追踪通道列表。
struct CandidateList: View {
    struct Group: Equatable {
        var device: String
        var refs: [ChannelRef]
    }

    var groups: [Group]
    @Binding var selection: ChannelRef?

    var body: some View {
        List(selection: $selection) {
            ForEach(groups, id: \.device) { g in
                Section(g.device) {
                    ForEach(g.refs, id: \.self) { ref in
                        Text(ref.description).font(Tokens.Font.mono).tag(ref)
                    }
                }
            }
        }
    }
}

/// 可渲染的内容部分。
public struct SignalFlowContent: View {
    var target: ChannelRef
    var deviceName: String
    var trace: SignalTrace
    var deviceNameOf: (ChannelRef) -> String

    public init(target: ChannelRef, deviceName: String, trace: SignalTrace, deviceNameOf: @escaping (ChannelRef) -> String) {
        self.target = target
        self.deviceName = deviceName
        self.trace = trace
        self.deviceNameOf = deviceNameOf
    }

    public var body: some View {
        let down = trace.downstream(from: target)
        let up = trace.upstream(to: target)
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            ViewHeader(title: "信号流", subtitle: "\(target) · \(deviceName)")
            section("去向", paths: down, empty: "这个通道没有送到任何地方。")
            if !up.isEmpty { section("来源", paths: up, empty: "") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func section(_ title: String, paths: [[TraceStep]], empty: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack(spacing: Tokens.Space.s) {
                Text(title).font(Tokens.Font.cardTitle).foregroundStyle(Tokens.Palette.text)
                Text("\(paths.count) 条路径").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            if paths.isEmpty {
                Text(empty).font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
            }
            ForEach(Array(paths.prefix(20).enumerated()), id: \.offset) { _, path in
                PathCard(steps: path, deviceNameOf: deviceNameOf)
            }
            if paths.count > 20 {
                Text("还有 \(paths.count - 20) 条").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
        }
    }
}

/// 一条路径：通道节点与跳交替，竖排。
struct PathCard: View {
    var steps: [TraceStep]
    var deviceNameOf: (ChannelRef) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let first = steps.first { node(first.hop.from) }
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                hop(step)
                node(step.hop.to)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func node(_ ref: ChannelRef) -> some View {
        HStack(spacing: Tokens.Space.s) {
            Circle().fill(Tokens.Palette.text).frame(width: 6, height: 6)
            Text(ref.description).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.text)
            Text(deviceNameOf(ref)).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
        }
    }

    private func hop(_ step: TraceStep) -> some View {
        HStack(spacing: Tokens.Space.s) {
            Rectangle().fill(Tokens.Palette.border).frame(width: 1, height: 22).padding(.leading, 2.5)
            EvidenceDot(step.evidence)
            Text(label(step.hop)).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
        }
        .padding(.leading, Tokens.Space.xs)
    }

    private func label(_ hop: Hop) -> String {
        switch hop {
        case let .route(_, _, domain, kind): return "→ \(domain.displayName) \(kind.shortLabel)"
        case .cable: return "⇒ 线缆"
        }
    }
}
