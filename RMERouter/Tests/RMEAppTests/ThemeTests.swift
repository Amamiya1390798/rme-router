import XCTest
@testable import RMEApp

/// 视觉主题（文档第 5.1 节）。
@MainActor
final class ThemeTests: XCTestCase {
    override func tearDown() { UITheme.current = .warm }

    /// 每套主题的样式卡与文档第 5.1 节的表一致（抽查）。
    func testStyleCards() {
        XCTAssertEqual(UITheme.warm.style.title, .serif)
        XCTAssertEqual(UITheme.gemini.style.panel, .glow)
        XCTAssertTrue(UITheme.gemini.style.capsuleChips)
        XCTAssertEqual(UITheme.gpt.style.meter, .gradient)
        XCTAssertEqual(UITheme.gpt.value(.accent).0, 0x10A37F)
        XCTAssertNotEqual(UITheme.gpt.value(.ok).0, UITheme.gpt.value(.accent).0, "已确认的绿和主题青绿要分开")
        XCTAssertEqual(UITheme.deepseek.style.brand, .badge)
        XCTAssertEqual(UITheme.kimi.style.card, .heavyOutline)
        XCTAssertEqual(UITheme.contrast.style.selection, .thick)
        UITheme.current = .kimi
        XCTAssertEqual(Tokens.Radius.chip, 99)
        UITheme.current = .warm
        XCTAssertEqual(Tokens.Radius.chip, 4)
    }

    /// Gemini 风格才有渐变点缀和大圆角。
    func testGeminiExtras() {
        UITheme.current = .gemini
        XCTAssertNotNil(Tokens.sparkle)
        XCTAssertEqual(Tokens.Radius.card, 20)
        UITheme.current = .warm
        XCTAssertNil(Tokens.sparkle)
        XCTAssertEqual(Tokens.Radius.card, 12)
    }

    /// 主题、外观存进偏好，重开还在；切换时当前主题跟着变。
    func testPersists() {
        let d = UserDefaults(suiteName: "theme-\(UUID())")!
        let m = AppModel(defaults: d)
        XCTAssertEqual(m.theme, .warm)
        m.theme = .studio
        XCTAssertEqual(UITheme.current, .studio)
        let again = AppModel(defaults: d)
        XCTAssertEqual(again.theme, .studio)
        XCTAssertEqual(again.appearance, .system)
    }

    /// 每套主题每个颜色都有值，且默认主题和设计文档第 5 节的表一致。
    func testTables() {
        XCTAssertEqual(UITheme.warm.value(.bg).0, 0xF5F3EE)
        XCTAssertEqual(UITheme.warm.value(.accent).1, 0xD9805E)
        XCTAssertEqual(UITheme.studio.value(.accent).0, 0x2F6FB5)
        XCTAssertEqual(UITheme.contrast.value(.bg).1, 0x121212)
        XCTAssertEqual(UITheme.gemini.value(.accent).0, 0x1A73E8)
        XCTAssertEqual(UITheme.allCases.count, 7)
        XCTAssertEqual(UITheme.deepseek.value(.accent).0, 0x4D6BFE)
        XCTAssertEqual(UITheme.gpt.cardRadius, 16)
        for t in UITheme.allCases {
            // 文字与底色要拉开：亮度差不小于默认主题的一半（粗略的对比检查）
            func lum(_ c: UInt32) -> Double { Double((c >> 16) & 0xFF) * 0.3 + Double((c >> 8) & 0xFF) * 0.59 + Double(c & 0xFF) * 0.11 }
            let (bgL, bgD) = t.value(.bg), (txL, txD) = t.value(.text)
            XCTAssertGreaterThan(abs(lum(bgL) - lum(txL)), 100, t.title)
            XCTAssertGreaterThan(abs(lum(bgD) - lum(txD)), 100, t.title)
        }
    }
}
