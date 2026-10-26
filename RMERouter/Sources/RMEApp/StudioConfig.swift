import Foundation
import RMEAdapters

/// 主卡型号（文档第 6.4.6 节）。
public enum MainCard: String, CaseIterable, Identifiable, Codable, Sendable {
    case madifaceXT, ufx3, generic
    public var id: String { rawValue }
    public var title: String {
        switch self { case .madifaceXT: return "MADIface XT"; case .ufx3: return "Fireface UFX III"; case .generic: return "通用（任何 TotalMix FX 设备）" }
    }
    /// 设备页、侧栏显示的名字。
    public var deviceName: String {
        switch self { case .madifaceXT: return "MADIface XT"; case .ufx3: return "Fireface UFX III"; case .generic: return "主卡（TotalMix FX）" }
    }
    /// 界面里的简称：“XT”“UFX III”“主卡”。
    public var shortName: String {
        switch self { case .madifaceXT: return "XT"; case .ufx3: return "UFX III"; case .generic: return "主卡" }
    }
    /// 在 Core Audio / Logic 里认这张卡的名字片段。“UFX III”不会认成 UFX II / UFX+；通用卡用 TotalMix 报的型号，报不出就不认（不猜）。
    public func audioKeyword(totalMix: String?) -> String? {
        switch self {
        case .madifaceXT: return "MADIface XT"
        case .ufx3: return "UFX III"
        case .generic: return totalMix.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
    }
    /// TotalMix 报的型号和所选主卡对不上（通用卡不比；报不出也不算）。XT 按整词“XT”比，XTC 不算。
    public func mismatches(totalMix: String?) -> Bool {
        guard let n = totalMix, !n.isEmpty else { return false }
        switch self {
        case .madifaceXT: return n.range(of: #"\bXT\b"#, options: [.regularExpression, .caseInsensitive]) == nil
        case .ufx3: return n.range(of: #"UFX\s*(III|3)\b"#, options: [.regularExpression, .caseInsensitive]) == nil
        case .generic: return false
        }
    }
    /// 话放增益上限（手册：XT 60 dB，UFX III 75 dB）。
    public var gainMax: Double { self == .ufx3 ? 75 : 60 }

    /// TotalMix 对照方式。
    public var mapLayout: TotalMixChannelMap.Layout {
        switch self { case .madifaceXT: return .madifaceXT; case .ufx3: return .ufx3; case .generic: return .generic }
    }
}

/// 设备组成：主卡型号 + 打开的扩展设备。存本机偏好。
public struct StudioConfig: Codable, Equatable, Sendable {
    public var mainCard: MainCard = .madifaceXT
    /// 打开的扩展设备："12mic"、"xtc"、"p16i"。
    public var expansions: Set<String> = StudioConfig.allExpansions

    public static let allExpansions: Set<String> = ["12mic", "xtc", "p16i"]
    public static let expansionNames: [(id: String, name: String)] = [("12mic", "12Mic"), ("xtc", "OctaMic XTC"), ("p16i", "Behringer P16-I")]
    public static let defaultsKey = "studio.config"

    public init(mainCard: MainCard = .madifaceXT, expansions: Set<String> = StudioConfig.allExpansions) {
        self.mainCard = mainCard
        self.expansions = expansions
    }

    public func has(_ device: String) -> Bool { device == "xt" || expansions.contains(device) }

    /// 当前组成：拓扑、能力在构建时读它（主线程上改，见 AppModel.studioConfig）。
    nonisolated(unsafe) public static var current = StudioConfig()
}

/// 当前主卡的简称、全名（界面文字用，跟着“设备组成”改）。
var mainName: String { StudioConfig.current.mainCard.shortName }
var mainFullName: String { StudioConfig.current.mainCard.deviceName }
