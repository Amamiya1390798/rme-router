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

    /// 字体随主题样式卡（第 5.1 节）。
    public enum Font {
        public static var viewTitle: SwiftUI.Font {
            let st = UITheme.current.style
            return .system(size: st.title == .heavy ? 24 : 22, weight: st.title.weight, design: st.title.design)
        }
        public static var cardTitle: SwiftUI.Font {
            let st = UITheme.current.style
            return .system(size: 15, weight: st.title == .heavy ? .bold : .semibold, design: st.title == .serif ? .default : st.title.design)
        }
        public static var body: SwiftUI.Font { .system(size: 13, design: UITheme.current.style.bodyRounded ? .rounded : .default) }
        public static var caption: SwiftUI.Font { .system(size: 11, design: UITheme.current.style.bodyRounded ? .rounded : .default) }
        public static let mono = SwiftUI.Font.system(size: 12, design: .monospaced).monospacedDigit()
    }

    public enum Space {
        public static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24
    }

    public enum Radius {
        public static let control: CGFloat = 8
        /// 小按钮（M、Ø、开关等）圆角：胶囊样式的主题给大值。
        public static var chip: CGFloat { UITheme.current.style.capsuleChips ? 99 : 4 }
        /// 通道条圆角随卡片圆角（大圆角主题的通道条也更圆）。
        public static var strip: CGFloat { max(6, UITheme.current.cardRadius / 2) }
        /// 卡片圆角随主题：Gemini 风格更圆（第 5.1 节）。
        public static var card: CGFloat { UITheme.current.cardRadius }
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
    case warm, studio, contrast, gemini, gpt, deepseek, kimi
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .warm: return "默认暖色"; case .studio: return "工作室蓝灰"; case .contrast: return "高对比"
        case .gemini: return "Gemini 风格"; case .gpt: return "GPT 风格"; case .deepseek: return "DeepSeek 风格"; case .kimi: return "Kimi 风格"
        }
    }

    /// 卡片圆角（第 5.1 节）。
    public var cardRadius: CGFloat {
        switch self { case .gemini: return 20; case .gpt, .kimi: return 16; case .deepseek: return 14; default: return 12 }
    }
    /// 侧栏页面项圆角（Gemini 是胶囊）。
    public var itemRadius: CGFloat {
        switch self { case .gemini: return 20; case .gpt, .deepseek, .kimi: return 10; default: return 8 }
    }
    /// 样式卡（第 5.1 节）：颜色以外的定制。
    public var style: ThemeStyle {
        switch self {
        case .warm: return ThemeStyle(title: .serif, card: .outlined, panel: .flat, meter: .traffic, brand: .plain, selection: .thin)
        case .studio: return ThemeStyle(title: .standard, card: .filled, panel: .topGradient, meter: .traffic, brand: .plain, selection: .thin)
        case .contrast: return ThemeStyle(title: .heavy, card: .heavyOutline, panel: .flat, meter: .traffic, brand: .plain, selection: .thick)
        case .gemini: return ThemeStyle(title: .rounded, bodyRounded: true, card: .elevated, capsuleChips: true, panel: .glow,
                                        meter: .gradient, brand: .gradient, selection: .glow)
        case .gpt: return ThemeStyle(title: .standard, card: .filled, capsuleChips: true, panel: .flat, meter: .mono, brand: .bold, selection: .thin)
        case .deepseek: return ThemeStyle(title: .standard, card: .elevated, panel: .topGradient, meter: .gradient, brand: .badge, selection: .glow)
        case .kimi: return ThemeStyle(title: .heavy, card: .heavyOutline, capsuleChips: true, panel: .flat, meter: .mono, brand: .badge, selection: .thick)
        }
    }

    /// 主题渐变色（电平条、渐变字、柔光）。
    public var gradientColors: [UInt32] {
        switch self {
        case .gemini: return [0x4285F4, 0x9B72CB, 0xD96570]
        case .deepseek: return [0x4D6BFE, 0x7FA2FF]
        case .kimi: return [0x4F46E5, 0x8B5CF6]
        default: return [value(.accent).0, value(.accent).1]
        }
    }

    /// 侧栏选中块用强调色淡底（否则用灰底）。
    public var tintedSelection: Bool { self == .gemini || self == .deepseek || self == .kimi }
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
        case .gpt:
            switch t {
            case .chrome: return (0xF9F9F9, 0x171717)
            case .bg: return (0xFFFFFF, 0x212121)
            case .surface: return (0xF7F7F8, 0x2F2F2F)
            case .border: return (0xE5E5E5, 0x3A3A3A)
            case .text: return (0x0D0D0D, 0xECECEC)
            case .textMuted: return (0x5D5D5D, 0xB4B4B4)
            case .accent: return (0x0D0D0D, 0xECECEC)
            case .ok: return (0x10A37F, 0x19C37D)
            case .warn: return (0xC27C0E, 0xF0B429)
            case .problem: return (0xD93F3F, 0xFF6B6B)
            case .unknown: return (0xA3A3A3, 0x6B6B6B)
            }
        case .deepseek:
            switch t {
            case .chrome: return (0xF5F7FB, 0x212327)
            case .bg: return (0xFFFFFF, 0x292A2D)
            case .surface: return (0xF5F7FB, 0x33353A)
            case .border: return (0xE1E5EE, 0x43464D)
            case .text: return (0x1A1C21, 0xE8EAED)
            case .textMuted: return (0x5E6573, 0xA0A6B0)
            case .accent: return (0x4D6BFE, 0x6D88FF)
            case .ok: return (0x2E9E5B, 0x5BC98A)
            case .warn: return (0xD08A1A, 0xF2C14E)
            case .problem: return (0xE0453A, 0xFF7A70)
            case .unknown: return (0xA0A6B0, 0x6A707A)
            }
        case .kimi:
            switch t {
            case .chrome: return (0xF4F4F5, 0x101012)
            case .bg: return (0xFFFFFF, 0x18181B)
            case .surface: return (0xF4F4F5, 0x27272A)
            case .border: return (0xE4E4E7, 0x3F3F46)
            case .text: return (0x09090B, 0xFAFAFA)
            case .textMuted: return (0x52525B, 0xA1A1AA)
            case .accent: return (0x4F46E5, 0x8B8CF6)
            case .ok: return (0x16A34A, 0x4ADE80)
            case .warn: return (0xCA8A04, 0xFACC15)
            case .problem: return (0xDC2626, 0xF87171)
            case .unknown: return (0xA1A1AA, 0x71717A)
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

/// 主题样式卡（第 5.1 节）。
public struct ThemeStyle: Equatable, Sendable {
    public enum Title: Sendable { case serif, rounded, standard, heavy
        var design: SwiftUI.Font.Design { self == .serif ? .serif : self == .rounded ? .rounded : .default }
        var weight: SwiftUI.Font.Weight { self == .heavy ? .heavy : self == .rounded ? .semibold : .regular }
    }
    public enum Card: Sendable { case outlined, elevated, filled, heavyOutline }
    public enum Panel: Sendable { case flat, glow, topGradient }
    public enum Meter: Sendable { case traffic, gradient, mono }
    public enum Brand: Sendable { case plain, bold, gradient, badge }
    public enum Selection: Sendable { case thin, glow, thick }

    public var title: Title
    public var bodyRounded = false
    public var card: Card
    public var capsuleChips = false
    public var panel: Panel
    public var meter: Meter
    public var brand: Brand
    public var selection: Selection
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

/// 卡片：按主题样式卡（第 5.1 节）——细线框 / 浮起阴影 / 实色底 / 粗线框。
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.card)
        let style = UITheme.current.style.card
        content
            .padding(Tokens.Space.m)
            .background(Tokens.Palette.surface, in: shape)
            .overlay {
                switch style {
                case .outlined: shape.strokeBorder(Tokens.Palette.border, lineWidth: 1)
                case .heavyOutline: shape.strokeBorder(Tokens.Palette.text.opacity(0.8), lineWidth: 1.5)
                case .elevated, .filled: EmptyView()
                }
            }
            .shadow(color: style == .elevated ? .black.opacity(0.10) : .clear, radius: 8, y: 2)
    }
}

extension View {
    /// 通道条等被选中 / 高亮时的边框：细线 / 发光 / 粗线（第 5.1 节）。
    func themedSelection(_ on: Bool, cornerRadius: CGFloat = 6) -> some View {
        let sel = UITheme.current.style.selection
        return overlay(RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(on ? Tokens.Palette.accent : .clear, lineWidth: sel == .thick ? 2.5 : 1.5))
            .shadow(color: on && sel == .glow ? Tokens.Palette.accent.opacity(0.55) : .clear, radius: 6)
    }
}

/// 内容面板上的背景氛围：柔光（左上角主题色光晕）或顶部渐变（第 5.1 节）。只是覆盖一层很淡的颜色，不挡点击。
struct PanelAtmosphere: View {
    var body: some View {
        let t = UITheme.current
        let colors = t.gradientColors.map { Color(nsColor: NSColor(hex: $0)) }
        switch t.style.panel {
        case .flat: Color.clear
        case .glow:
            ZStack {
                RadialGradient(colors: [colors.first!.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
                RadialGradient(colors: [colors.last!.opacity(0.10), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 420)
            }
        case .topGradient:
            LinearGradient(colors: [colors.first!.opacity(0.10), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))
        }
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
