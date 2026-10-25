import AppKit
import SwiftUI
import RMECore

/// 设计 token（文档第 5 节）：暖白纸色底、单一陶土色强调、细线代替阴影。
public enum Tokens {
    /// 颜色随主题（第 5.1 节）和系统浅色 / 深色变化：绘制时按当前主题取值。
    public enum Palette {
        public static let bg = Color(token: .bg)
        /// 窗口框（侧边栏与面板四周），比页面底色稍深（第 5.1 节）。
        public static let chrome = Color(token: .chrome)
        public static let surface = Color(token: .surface)
        public static let border = Color(token: .border)
        public static let text = Color(token: .text)
        public static let textMuted = Color(token: .textMuted)
        public static let accent = Color(token: .accent)
        public static let ok = Color(token: .ok)
        public static let warn = Color(token: .warn)
        public static let problem = Color(token: .problem)
        public static let unknown = Color(token: .unknown)
    }

    public enum Font {
        public static let viewTitle = SwiftUI.Font.system(size: 22, weight: .regular, design: .serif)
        public static let cardTitle = SwiftUI.Font.system(size: 15, weight: .semibold)
        public static let body = SwiftUI.Font.system(size: 13)
        public static let caption = SwiftUI.Font.system(size: 11)
        public static let mono = SwiftUI.Font.system(size: 12, design: .monospaced).monospacedDigit()
    }

    public enum Space {
        public static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24
    }

    public enum Radius {
        public static let control: CGFloat = 8
        /// 卡片圆角随主题：Gemini 风格更圆（第 5.1 节）。
        public static var card: CGFloat { UITheme.current == .gemini ? 20 : 12 }
    }

    /// 主题点缀渐变（只有 Gemini 风格有：蓝→紫→粉）；其他主题为 nil。
    public static var sparkle: LinearGradient? {
        guard UITheme.current == .gemini else { return nil }
        return LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x4285F4)), Color(nsColor: NSColor(hex: 0x9B72CB)),
                                       Color(nsColor: NSColor(hex: 0xD96570))], startPoint: .leading, endPoint: .trailing)
    }
}

/// 视觉主题（文档第 5.1 节）。只换颜色，状态色意义不变。
public enum UITheme: String, CaseIterable, Identifiable, Sendable {
    case warm, studio, contrast, gemini
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .warm: return "默认暖色"; case .studio: return "工作室蓝灰"; case .contrast: return "高对比"; case .gemini: return "Gemini 风格"
        }
    }
    public static let defaultsKey = "ui.theme"

    /// 当前主题。只在主线程改（设置页），颜色在绘制时读。
    nonisolated(unsafe) public static var current: UITheme =
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(UITheme.init(rawValue:)) ?? .warm

    public enum Token: CaseIterable { case chrome, bg, surface, border, text, textMuted, accent, ok, warn, problem, unknown }

    /// (浅色, 深色)
    public func value(_ t: Token) -> (UInt32, UInt32) {
        switch self {
        case .warm:
            switch t {
            case .chrome: return (0xECE9E1, 0x1E1D1B)
            case .bg: return (0xF5F3EE, 0x262624)
            case .surface: return (0xFBFAF7, 0x2F2F2C)
            case .border: return (0xE4E0D6, 0x3E3D39)
            case .text: return (0x1F1E1C, 0xF1EFE8)
            case .textMuted: return (0x6E6B63, 0xA3A097)
            case .accent: return (0xB5552F, 0xD9805E)
            case .ok: return (0x5B8A68, 0x7FAE8B)
            case .warn: return (0xB7862E, 0xD3A452)
            case .problem: return (0xB23A2E, 0xE0675A)
            case .unknown: return (0xA8A49A, 0x6F6C65)
            }
        case .studio:
            switch t {
            case .chrome: return (0xE3E7EC, 0x171A1E)
            case .bg: return (0xEEF1F4, 0x1E2227)
            case .surface: return (0xF8FAFC, 0x272C33)
            case .border: return (0xD8DEE5, 0x3A414B)
            case .text: return (0x1A1F26, 0xE9EDF2)
            case .textMuted: return (0x5F6873, 0x9AA4B0)
            case .accent: return (0x2F6FB5, 0x5B9BE0)
            case .ok: return (0x3F8A5E, 0x6CC08E)
            case .warn: return (0xB07A1E, 0xE0B04E)
            case .problem: return (0xC0392B, 0xEF6F61)
            case .unknown: return (0x9AA3AD, 0x66707B)
            }
        case .gemini:
            switch t {
            case .chrome: return (0xF0F4F9, 0x1E1F20)
            case .bg: return (0xFFFFFF, 0x131314)
            case .surface: return (0xF0F4F9, 0x1E1F20)
            case .border: return (0xDDE3EA, 0x333537)
            case .text: return (0x1F1F1F, 0xE3E3E3)
            case .textMuted: return (0x5F6368, 0x9AA0A6)
            case .accent: return (0x1A73E8, 0x8AB4F8)
            case .ok: return (0x188038, 0x81C995)
            case .warn: return (0xE37400, 0xFDD663)
            case .problem: return (0xD93025, 0xF28B82)
            case .unknown: return (0x9AA0A6, 0x5F6368)
            }
        case .contrast:
            switch t {
            case .chrome: return (0xEDEDED, 0x000000)
            case .bg: return (0xFFFFFF, 0x121212)
            case .surface: return (0xFFFFFF, 0x1C1C1C)
            case .border: return (0x8A8A8A, 0x6A6A6A)
            case .text: return (0x000000, 0xFFFFFF)
            case .textMuted: return (0x3D3D3D, 0xC8C8C8)
            case .accent: return (0xA8401A, 0xFF8A5C)
            case .ok: return (0x1E7A3C, 0x5FD38A)
            case .warn: return (0x8F6200, 0xFFC94D)
            case .problem: return (0xB0140A, 0xFF6B5E)
            case .unknown: return (0x707070, 0x9A9A9A)
            }
        }
    }
}

/// 外观：跟随系统 / 浅色 / 深色（第 5.1 节）。
public enum UIAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String { self == .system ? "跟随系统" : self == .light ? "浅色" : "深色" }
    public static let defaultsKey = "ui.appearance"
    public var colorScheme: ColorScheme? { self == .system ? nil : self == .light ? .light : .dark }
}

extension Color {
    /// 主题色：绘制时按当前主题与浅色 / 深色取值。
    init(token: UITheme.Token) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let v = UITheme.current.value(token)
            return NSColor(hex: isDark ? v.1 : v.0)
        })
    }

    /// 随系统浅色/深色切换的颜色。
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// 四种状态（文档第 4 节）：已确认（实心点）、推断（空心点）、未知（灰色虚线）、有问题（警示红）。
public struct EvidenceDot: View {
    public var evidence: Evidence
    public init(_ evidence: Evidence) { self.evidence = evidence }

    public var body: some View {
        Group {
            switch evidence {
            case .confirmed:
                Circle().fill(Tokens.Palette.ok)
            case .documented, .inferred:
                Circle().strokeBorder(Tokens.Palette.warn, lineWidth: 1.5)
            case .unknown:
                Circle().strokeBorder(Tokens.Palette.unknown, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
            case .conflict:
                Circle().fill(Tokens.Palette.problem)
            }
        }
        .frame(width: 8, height: 8)
        .help(evidence.label)
    }
}

public extension Evidence {
    var label: String {
        switch self {
        case .confirmed: return "已确认"
        case .documented: return "有文档依据"
        case .inferred: return "推断"
        case .unknown: return "未知"
        case .conflict: return "有冲突"
        }
    }
}

/// 卡片：surface 底、1px 细线、圆角 12，无阴影。
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Tokens.Space.m)
            .background(Tokens.Palette.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).strokeBorder(Tokens.Palette.border, lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
