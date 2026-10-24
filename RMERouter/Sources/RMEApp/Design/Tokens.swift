import AppKit
import SwiftUI
import RMECore

/// 设计 token（文档第 5 节）：暖白纸色底、单一陶土色强调、细线代替阴影。
public enum Tokens {
    public enum Palette {
        public static let bg = Color(light: 0xF5F3EE, dark: 0x262624)
        public static let surface = Color(light: 0xFBFAF7, dark: 0x2F2F2C)
        public static let border = Color(light: 0xE4E0D6, dark: 0x3E3D39)
        public static let text = Color(light: 0x1F1E1C, dark: 0xF1EFE8)
        public static let textMuted = Color(light: 0x6E6B63, dark: 0xA3A097)
        public static let accent = Color(light: 0xB5552F, dark: 0xD9805E)
        public static let ok = Color(light: 0x5B8A68, dark: 0x7FAE8B)
        public static let warn = Color(light: 0xB7862E, dark: 0xD3A452)
        public static let problem = Color(light: 0xB23A2E, dark: 0xE0675A)
        public static let unknown = Color(light: 0xA8A49A, dark: 0x6F6C65)
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
        public static let control: CGFloat = 8, card: CGFloat = 12
    }
}

extension Color {
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
