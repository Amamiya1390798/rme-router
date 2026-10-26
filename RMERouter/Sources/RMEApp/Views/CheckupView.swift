import SwiftUI
import RMECore
import RMEEngine

/// “体检”视图：哪里配置不对、为什么、怎么改（文档第 3 节痛点 5）。
public struct CheckupView: View {
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        ScrollView {
            CheckupContent(results: model.checkupResults, status: model.xtStatus,
                           lastLoaded: model.lastLoaded, demoDevices: demoNames, twelveMic: model.twelveMicStatus)
                .padding(Tokens.Space.xl)
        }
        .background(Tokens.Palette.bg)
    }

    private var demoNames: [String] {
        ["12mic", "xtc"].filter(model.isDemo).compactMap { model.snapshot.topology.device($0)?.name }
    }
}

/// 可渲染的内容部分（不含 ScrollView）。
public struct CheckupContent: View {
    var results: [RuleResult]
    var status: XTStatus
    var lastLoaded: Date?
    var demoDevices: [String]
    var twelveMic: TwelveMicStatus

    public init(results: [RuleResult], status: XTStatus, lastLoaded: Date?, demoDevices: [String],
                twelveMic: TwelveMicStatus = .notLoaded) {
        self.results = results
        self.status = status
        self.lastLoaded = lastLoaded
        self.demoDevices = demoDevices
        self.twelveMic = twelveMic
    }

    public var body: some View {
        let counts = CheckupReport.counts(results)
        LazyVStack(alignment: .leading, spacing: Tokens.Space.xl) {   // 懒加载：规则卡片多，切页时只建看得见的
            ViewHeader(title: "体检", subtitle: summary(counts))
            StatusStrip(status: status, lastLoaded: lastLoaded, demoDevices: demoDevices, twelveMic: twelveMic)
            ForEach(results.filter { $0.status == .problem || $0.status == .undetermined }) { RuleCard(result: $0) }
            let passed = results.filter { $0.status == .pass }
            if !passed.isEmpty { PassedCard(results: passed) }
            let empty = results.filter { $0.status == .notApplicable }
            if !empty.isEmpty {
                Text("没有可检查的项：" + empty.map { "\($0.info.id) \($0.info.title)" }.joined(separator: "、")
                     + "（没有配置或没有读到相关数据，不算通过）")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summary(_ c: (problem: Int, undetermined: Int, pass: Int)) -> String {
        var parts: [String] = []
        if c.problem > 0 { parts.append("\(c.problem) 项有问题") }
        if c.undetermined > 0 { parts.append("\(c.undetermined) 项无法判断") }
        parts.append("\(c.pass) 项通过")
        return parts.joined(separator: "，") + "。读不到的状态一律算“无法判断”，不算通过。"
    }
}

/// 一条规则的卡片：有问题与无法判断的条目、说明、改法或确认方法。
struct RuleCard: View {
    var result: RuleResult
    static let maxRows = 8

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                EvidenceDot(result.status == .problem ? .conflict : .unknown)
                Text("\(result.info.id) \(result.info.title)").font(Tokens.Font.cardTitle).foregroundStyle(Tokens.Palette.text)
                Badge(text: result.severity.label, color: severityColor)
                Spacer(minLength: Tokens.Space.s)
                Text(countsText).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            Text(result.info.explanation).font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Tokens.Palette.border).frame(height: 1)

            if !result.failures.isEmpty {
                rows(result.failures, dot: .conflict)
                labeled("改法", result.info.fix, color: Tokens.Palette.accent)
            }
            if !result.undetermined.isEmpty {
                rows(result.undetermined, dot: .unknown)
                labeled("怎么确认", result.info.howToCheck, color: Tokens.Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var severityColor: Color {
        switch result.severity {
        case .error: return Tokens.Palette.problem
        case .warning: return Tokens.Palette.warn
        case .info: return Tokens.Palette.textMuted
        }
    }

    private var countsText: String {
        var parts: [String] = []
        if !result.failures.isEmpty { parts.append("\(result.failures.count) 有问题") }
        if !result.undetermined.isEmpty { parts.append("\(result.undetermined.count) 无法判断") }
        if !result.passes.isEmpty { parts.append("\(result.passes.count) 通过") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func rows(_ findings: [Finding], dot: Evidence) -> some View {
        ForEach(Array(findings.prefix(Self.maxRows).enumerated()), id: \.offset) { _, f in
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                EvidenceDot(dot)
                Text(f.subject).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.text)
                Text(message(f.verdict)).font(Tokens.Font.body).foregroundStyle(Tokens.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if findings.count > Self.maxRows {
            Text("还有 \(findings.count - Self.maxRows) 条").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
        }
    }

    private func labeled(_ label: String, _ text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Text(label).font(Tokens.Font.caption.weight(.semibold)).foregroundStyle(color)
            Text(text).font(Tokens.Font.body).foregroundStyle(Tokens.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Tokens.Space.xs)
    }

    private func message(_ v: Verdict) -> String {
        switch v {
        case .pass: return "通过"
        case let .fail(m), let .cannotDetermine(m): return m
        }
    }
}

/// 全部通过的规则，收在一张卡里。
struct PassedCard: View {
    var results: [RuleResult]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(spacing: Tokens.Space.s) {
                EvidenceDot(.confirmed)
                Text("通过的检查").font(Tokens.Font.cardTitle).foregroundStyle(Tokens.Palette.text)
                Text("\(results.count) 项").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            ForEach(results) { r in
                HStack(spacing: Tokens.Space.s) {
                    Text(r.info.id).font(Tokens.Font.mono).foregroundStyle(Tokens.Palette.textMuted)
                    Text(r.info.title).font(Tokens.Font.body).foregroundStyle(Tokens.Palette.text)
                    if r.passes.count > 1 {
                        Text("\(r.passes.count) 项").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
