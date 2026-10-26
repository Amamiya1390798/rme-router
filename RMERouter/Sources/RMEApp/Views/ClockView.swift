import SwiftUI
import RMECore
import RMEEngine

/// “时钟”页（文档第 3 节痛点 6）：各设备采样率、时钟源、各数字输入的 Lock/Sync 一页看全。
public struct ClockView: View {
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        ScrollView {
            ClockContent(rows: ClockReport.build(model.snapshot), summary: model.checkupResults.filter { ClockReport.summaryRules.contains($0.id) }
                .sorted { ClockReport.summaryRules.firstIndex(of: $0.id)! < ClockReport.summaryRules.firstIndex(of: $1.id)! })
                .padding(Tokens.Space.xl)
        }
        .pageBackground()
    }
}

/// 可渲染的内容部分。
public struct ClockContent: View {
    var rows: [ClockDeviceRow]
    var summary: [RuleResult]

    public init(rows: [ClockDeviceRow], summary: [RuleResult]) {
        self.rows = rows
        self.summary = summary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            ViewHeader(title: "时钟", subtitle: "整个系统只能有一个时钟主机，其余设备跟随它；所有设备的采样率要一致。读不到的项标“需人工确认”。", mood: .determined)
            summaryCard
            ForEach(rows) { DeviceClockCard(row: $0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 摘要：与体检 R1、R2、R4、R5 同一套结论。
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("结论").font(Tokens.Font.cardTitle)
            ForEach(summary) { r in
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    EvidenceDot(r.status == .pass ? .confirmed : r.status == .problem ? .conflict : .unknown)
                    Text(r.info.title).font(Tokens.Font.body).frame(width: 130, alignment: .leading)
                    Text(detail(r)).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func detail(_ r: RuleResult) -> String {
        switch r.status {
        case .pass: return "通过"
        case .notApplicable: return "没有可检查的项"
        case .problem, .undetermined:
            var msgs: [String] = []
            for f in r.failures + r.undetermined {
                let m: String
                switch f.verdict { case let .fail(t), let .cannotDetermine(t): m = t; case .pass: continue }
                let text = r.findings.count > 1 && f.subject != "系统" ? "\(f.subject)：\(m)" : m
                if !msgs.contains(text) { msgs.append(text) }
            }
            return msgs.prefix(3).joined(separator: "；") + (msgs.count > 3 ? " 等" : "")
        }
    }
}

struct DeviceClockCard: View {
    var row: ClockDeviceRow

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Text(row.deviceName).font(Tokens.Font.cardTitle)
                if row.isMaster == true { Badge(text: "主机", color: Tokens.Palette.accent) }
                if row.isMaster == false { Badge(text: "从机", color: Tokens.Palette.textMuted) }
                Spacer()
                if let s = row.soundness { Text("设备自报：\(s)").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted) }
            }
            Grid(alignment: .leading, horizontalSpacing: Tokens.Space.m, verticalSpacing: Tokens.Space.xs) {
                GridRow {
                    Text("采样率").foregroundStyle(Tokens.Palette.textMuted)
                    if let r = row.rate?.knownValue {
                        HStack(spacing: Tokens.Space.s) {
                            EvidenceDot(row.rate?.evidence ?? .unknown)
                            Text(verbatim: "\(r) Hz").font(Tokens.Font.mono)
                        }
                    } else {
                        needsManual
                    }
                }
                GridRow {
                    Text("时钟源").foregroundStyle(Tokens.Palette.textMuted)
                    if let s = row.sourceText { Text(s).font(Tokens.Font.body) } else { needsManual }
                }
            }
            .font(Tokens.Font.body)
            if !row.inputs.isEmpty {
                Rectangle().fill(Tokens.Palette.border).frame(height: 1)
                ForEach(row.inputs) { input in inputRow(input) }
            }
            if !row.rateKnown || row.sourceText == nil {
                Text(row.manualHint).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var needsManual: some View {
        HStack(spacing: Tokens.Space.s) {
            EvidenceDot(.unknown)
            Text("需人工确认").foregroundStyle(Tokens.Palette.unknown)
        }
    }

    private func inputRow(_ input: ClockDeviceRow.Input) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Text(input.portName).font(Tokens.Font.body).frame(width: 120, alignment: .leading)
            flag("Lock", input.lock)
            flag("Sync", input.sync)
            Text(input.upstream.map { "来自 \($0)" } ?? "没有登记接线")
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
        }
    }

    /// Lock / Sync 状态：读到为真 = 实心；为假 = 红；读不到 = 灰色虚线。
    private func flag(_ label: String, _ fact: Fact<Bool>?) -> some View {
        HStack(spacing: 4) {
            switch fact?.knownValue {
            case true?: EvidenceDot(fact?.evidence == .confirmed ? .confirmed : .inferred)
            case false?: EvidenceDot(.conflict)
            case nil: EvidenceDot(.unknown)
            }
            Text(label).font(Tokens.Font.caption)
                .foregroundStyle(fact?.knownValue == false ? Tokens.Palette.problem : Tokens.Palette.textMuted)
        }
        .frame(width: 60, alignment: .leading)
    }
}
