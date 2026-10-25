import SwiftUI
import RMECore
import RMEEngine

/// 跨设备“送一路声音”（文档第 7.5 节）：选来源与去处 → 算路径 → 看每一步 → 加入待应用。
struct SendAcrossSheet: View {
    @Bindable var model: AppModel
    /// 从设备页拖线打开时预先填好（第 6.4.4 节）。
    var initialSource: ChannelRef? = nil
    var initialDest: ChannelRef? = nil
    var close: () -> Void

    @State private var sourcePort = ""
    @State private var sourceChannel = 1
    @State private var destPort = ""
    @State private var destChannel = 1
    @State private var pair = false
    @State private var result: SendPlanResult?
    @State private var errors: [String] = []
    /// 计划会让别的去向断声时，须先勾选（第 7.5 节第 7 条）。
    @State private var impactAcknowledged = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            Text("跨设备送一路声音").font(Tokens.Font.viewTitle)
            Text("选一个来源和去处，App 算出要经过哪些设备、每台怎么设。新建的 TotalMix 发送从 -30 dB 起步；XTC 只能在面板上手动设置。")
                .font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: Tokens.Space.m, verticalSpacing: Tokens.Space.s) {
                GridRow {
                    Text("来源").foregroundStyle(Tokens.Palette.textMuted)
                    portPicker($sourcePort, ports: model.sendSourcePorts)
                    channelStepper($sourceChannel, port: sourcePort)
                }
                GridRow {
                    Text("去处").foregroundStyle(Tokens.Palette.textMuted)
                    portPicker($destPort, ports: model.sendDestinationPorts)
                    channelStepper($destChannel, port: destPort)
                }
            }
            .font(Tokens.Font.body)
            Toggle("左右成对（同时送下一个通道）", isOn: $pair).toggleStyle(.checkbox).font(Tokens.Font.body)

            HStack {
                Button("计算路径") { compute() }
                    .disabled(sourcePort.isEmpty || destPort.isEmpty)
                Spacer()
            }

            if let result {
                ScrollView { planView(result).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(minHeight: 120, maxHeight: 320)
            }
            ForEach(errors, id: \.self) { Text($0).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.problem) }
            if hasImpact {
                Toggle("我知道会影响上面这些去向（它们原来的声音会断）", isOn: $impactAcknowledged)
                    .toggleStyle(.checkbox).font(Tokens.Font.body).foregroundStyle(Tokens.Palette.problem)
            }

            HStack {
                Spacer()
                Button("取消", action: close).keyboardShortcut(.cancelAction)
                Button(ConfirmMode.current.applyLabel) { stage() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).tint(Tokens.Palette.accent)
                    .disabled(plans.allSatisfy { $0.autoCount == 0 && $0.manualSteps.isEmpty } || (hasImpact && !impactAcknowledged))
            }
        }
        .padding(Tokens.Space.xl)
        .frame(width: 640)
        .background(Tokens.Palette.bg)
        .onAppear {
            if let s = initialSource { sourcePort = s.portID; sourceChannel = s.channel }
            if let d = initialDest { destPort = d.portID; destChannel = d.channel }
            if sourcePort.isEmpty { sourcePort = model.sendSourcePorts.first?.id ?? "" }
            if destPort.isEmpty { destPort = model.sendDestinationPorts.first?.id ?? "" }
            if initialSource != nil, initialDest != nil { DispatchQueue.main.async { compute() } }
        }
        .onChange(of: [sourcePort, destPort]) { result = nil; errors = [] }
        .onChange(of: [sourceChannel, destChannel]) { result = nil; errors = [] }
        .onChange(of: pair) { result = nil; errors = [] }
    }

    private var hasImpact: Bool { plans.contains { !$0.impacts.isEmpty } }

    private var plans: [SendPlan] {
        if case let .found(p)? = result { return p }
        return []
    }

    private func compute() {
        errors = []
        impactAcknowledged = false
        result = SendAcross.plan(model.snapshot, from: ChannelRef(sourcePort, sourceChannel),
                                 to: ChannelRef(destPort, destChannel), pair: pair)
    }

    private func stage() {
        errors = model.stageSendPlan(plans)
        guard errors.isEmpty else { return }
        close()
        Task { await model.commitIfQuick() }
    }

    private func portPicker(_ selection: Binding<String>, ports: [RMECore.Port]) -> some View {
        Picker("", selection: selection) {
            ForEach(ports, id: \.id) { p in
                Text(verbatim: "\(model.snapshot.topology.device(p.deviceID)?.name ?? p.deviceID) · \(p.name)").tag(p.id)
            }
        }
        .labelsHidden()
        .frame(width: 300)
    }

    private func channelStepper(_ value: Binding<Int>, port: String) -> some View {
        let maxCh = max(1, model.snapshot.topology.port(port)?.singleSpeedChannels ?? 1)
        return Stepper(value: value, in: 1 ... maxCh) {
            Text(verbatim: "通道 \(value.wrappedValue)").font(Tokens.Font.mono).frame(width: 70, alignment: .leading)
        }
    }

    @ViewBuilder private func planView(_ r: SendPlanResult) -> some View {
        switch r {
        case let .infeasible(reasons):
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Label("找不到路径", systemImage: "xmark.octagon").foregroundStyle(Tokens.Palette.problem).font(Tokens.Font.cardTitle)
                ForEach(reasons, id: \.self) { Text($0).font(Tokens.Font.caption) }
            }
            .card()
        case let .found(plans):
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                ForEach(Array(plans.enumerated()), id: \.offset) { _, plan in planCard(plan) }
            }
        }
    }

    private func planCard(_ plan: SendPlan) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack {
                Text(verbatim: "\(plan.source.description) → \(plan.destination.description)").font(Tokens.Font.mono)
                Spacer()
                Text("自动 \(plan.autoCount) 步 · 人工 \(plan.manualSteps.count) 步").font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Palette.textMuted)
            }
            ForEach(plan.steps) { step in stepRow(step) }
            if plan.autoCount == 0 && plan.manualSteps.isEmpty {
                Label("这条路径已经通了，不需要改动", systemImage: "checkmark.circle")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.ok)
            }
            if !plan.impacts.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("没有不覆盖的路，只能替换已有路由：").font(Tokens.Font.caption.weight(.semibold))
                    ForEach(Array(plan.impacts.enumerated()), id: \.offset) { _, i in
                        Text(verbatim: "· 覆盖 \(i.route.domain.displayName) 路由 \(model.shortName(i.route.source)) → \(i.route.destination)："
                             + "原来经这里送到 " + i.lostEndpoints.prefix(4).map(model.shortName).joined(separator: "、")
                             + (i.lostEndpoints.count > 4 ? " 等 \(i.lostEndpoints.count) 处" : "") + " 的声音会断")
                            .font(Tokens.Font.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(Tokens.Palette.problem)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func stepRow(_ step: SendPlan.Step) -> some View {
        let (tag, color, text): (String, Color, String) = {
            switch step.action {
            case let .totalMixSend(s, d, dB):
                return ("自动", Tokens.Palette.accent, "TotalMix 新建发送 \(s) → \(d)，\(String(format: "%.0f", dB)) dB 起步")
            case let .twelveMicRoute(s, d):
                return ("自动", Tokens.Palette.accent, "12Mic 路由 \(s) → \(d)")
            case let .xtcRoute(s, d):
                let sf = s.block * 8 + 1, df = d.block * 8 + 1
                return ("自动", Tokens.Palette.accent,
                        "XTC 路由（整块 8 路）\(s.portID):\(sf)–\(sf + 7) → \(d.portID):\(df)–\(df + 7)")
            case let .existing(r):
                return ("沿用", Tokens.Palette.ok, "已有 \(r.domain.displayName) 路由 \(r.source) → \(r.destination)")
            case let .cable(f, t):
                return ("线缆", Tokens.Palette.textMuted, "\(f) ⇒ \(t)")
            case let .manual(t):
                return ("人工", Tokens.Palette.warn, t)
            }
        }()
        return HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Badge(text: tag, color: color)
            Text(verbatim: text).font(Tokens.Font.caption).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 输出页标题旁的入口按钮。
struct SendAcrossButton: View {
    @Bindable var model: AppModel
    @State private var open = false

    var body: some View {
        Button { open = true } label: { Label("跨设备送一路声音", systemImage: "arrow.triangle.branch") }
            .help("选来源和去处，自动算出每台设备怎么设")
            .disabled(model.lastLoaded == nil)
            .sheet(isPresented: $open) { SendAcrossSheet(model: model) { open = false } }
    }
}
