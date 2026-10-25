import Foundation
import RMECore
import RMEEngine

/// 体检视图的一张卡：一条规则的全部结论。
public struct RuleResult: Identifiable, Equatable, Sendable {
    public enum Status: Int, Comparable, Sendable {
        /// notApplicable：规则没有产出任何结论（例如没有声明期望设置、没有配置 Aux Device、没有读到输出）。
        case problem = 0, undetermined = 1, pass = 2, notApplicable = 3
        public static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
    }

    public var info: RuleInfo
    public var severity: Severity
    public var findings: [Finding]

    public var id: String { info.id }
    public var failures: [Finding] { findings.filter(\.verdict.isFail) }
    public var undetermined: [Finding] { findings.filter(\.verdict.isUndetermined) }
    public var passes: [Finding] { findings.filter(\.verdict.isPass) }

    /// 有任何一条有问题就算有问题；否则有无法判断就算无法判断；没有任何结论算“没有可检查的项”，不算通过。
    public var status: Status {
        if !failures.isEmpty { return .problem }
        if !undetermined.isEmpty { return .undetermined }
        if findings.isEmpty { return .notApplicable }
        return .pass
    }
}

public extension Severity {
    var label: String {
        switch self {
        case .error: return "严重"
        case .warning: return "注意"
        case .info: return "提示"
        }
    }
    var rank: Int {
        switch self {
        case .error: return 0
        case .warning: return 1
        case .info: return 2
        }
    }
}

public enum CheckupReport {
    /// 跑全部规则，按规则分组；排序：有问题 → 无法判断 → 通过，同类里严重在前，再按规则号。
    public static func build(_ snapshot: SystemSnapshot,
                             rules: [any DiagnosticRule] = Diagnostics.allRules) -> [RuleResult] {
        let findings = Diagnostics.run(snapshot, rules: rules)
        let byRule = Dictionary(grouping: findings, by: \.ruleID)
        return rules.map { rule in
            RuleResult(info: RuleCatalog.info(rule.id)
                           ?? RuleInfo(id: rule.id, title: rule.id, explanation: "", fix: "", howToCheck: ""),
                       severity: rule.severity,
                       findings: (byRule[rule.id] ?? []).sorted { $0.subject < $1.subject })
        }
        .sorted { a, b in
            if a.status != b.status { return a.status < b.status }
            if a.severity != b.severity { return a.severity.rank < b.severity.rank }
            return number(a.id) < number(b.id)
        }
    }

    static func number(_ id: String) -> Int { Int(id.dropFirst()) ?? 999 }

    /// 顶部摘要：各状态的规则数。
    public static func counts(_ results: [RuleResult]) -> (problem: Int, undetermined: Int, pass: Int) {
        (results.filter { $0.status == .problem }.count,
         results.filter { $0.status == .undetermined }.count,
         results.filter { $0.status == .pass }.count)
    }
}
