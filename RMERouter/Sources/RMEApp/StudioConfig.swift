import Foundation

/// 主卡型号（文档第 6.4.6 节）。
public enum MainCard: String, CaseIterable, Identifiable, Codable, Sendable {
    case madifaceXT, generic
    public var id: String { rawValue }
    public var title: String { self == .madifaceXT ? "MADIface XT" : "通用（任何 TotalMix FX 设备）" }
    /// 设备页、侧栏显示的名字。
    public var deviceName: String { self == .madifaceXT ? "MADIface XT" : "主卡（TotalMix FX）" }
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
