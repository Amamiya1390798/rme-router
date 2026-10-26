import XCTest
import CryptoKit
@testable import RMEApp

/// 二次元模式（文档第 5.1.1 节）。
@MainActor
final class AnimeThemeTests: XCTestCase {
    func testHiddenUnderDeepSeek() {
        XCTAssertFalse(UITheme.pickable.contains(.anime), "主题网格里不单列")
        XCTAssertFalse(UITheme.pickable.contains(.claudeAnime))
        XCTAssertEqual(AnimeSkin.claude.base, .warm)
        XCTAssertEqual(UITheme.claudeAnime.animeSkin, .claude)
        XCTAssertTrue(UITheme.pickable.contains(.deepseek))
        XCTAssertEqual(UITheme.anime.title, "二次元模式")
    }

    /// 正文与底色对比度 ≥ 4.5（浅色、深色）。
    func testReadable() {
        func lum(_ c: UInt32) -> Double {
            func ch(_ v: UInt32) -> Double { let x = Double(v) / 255; return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
            return 0.2126 * ch(c >> 16 & 0xFF) + 0.7152 * ch(c >> 8 & 0xFF) + 0.0722 * ch(c & 0xFF)
        }
        func ratio(_ a: UInt32, _ b: UInt32) -> Double { let (x, y) = (lum(a), lum(b)); return (max(x, y) + 0.05) / (min(x, y) + 0.05) }
        for t in [UITheme.anime, .claudeAnime] { for bg in [UITheme.Token.bg, .surface] {
            XCTAssertGreaterThan(ratio(t.value(.text).0, t.value(bg).0), 4.5)
            XCTAssertGreaterThan(ratio(t.value(.text).1, t.value(bg).1), 4.5)
            XCTAssertGreaterThan(ratio(t.value(.textMuted).0, t.value(bg).0), 4.5)
            XCTAssertGreaterThan(ratio(t.value(.textMuted).1, t.value(bg).1), 4.5)
        } }
    }

    /// 素材都在、能载入，和 sources.json 记的 sha256 一致；署名与协议文本在。
    func testArtwork() throws {
        let dir = try XCTUnwrap(AnimeArt.directory)
        for n in AnimeArt.names { XCTAssertNotNil(AnimeArt.image(n, skin: .whale), n) }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("sources.json"))) as? [String: Any]
        let files = try XCTUnwrap(json?["files"] as? [String: [String: String]])
        for (name, info) in files {
            let data = try Data(contentsOf: dir.appendingPathComponent(name))
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), info["sha256"], name)
        }
        let notice = AnimeModeRow.noticeText
        for c in AnimeArt.credits { XCTAssertTrue(notice.contains(c.name), c.name) }
        XCTAssertTrue(notice.contains("CC BY-NC-SA 4.0"))
        // Claude 看板娘：先有立绘，其余缺的用代码画的替代
        XCTAssertNotNil(AnimeArt.image("maid-left", skin: .claude))
    }
}

/// 主题光标（2026-10-27）：每套主题都有；Claude 贴小螃蟹，DeepSeek 两套贴鲸鱼尾巴（偶尔社区版），其余不贴。
@MainActor
final class ThemeCursorTests: XCTestCase {
    func testBadges() {
        XCTAssertEqual(ThemeCursor.badge(for: .claudeAnime), .crab)
        XCTAssertEqual(ThemeCursor.badge(for: .deepseek, roll: 0.5), .whaleOfficial)
        XCTAssertEqual(ThemeCursor.badge(for: .anime, roll: 0.05), .whaleCommunity)
        XCTAssertEqual(ThemeCursor.badge(for: .warm), ThemeCursor.Badge.none)
        XCTAssertNotNil(ThemeCursor.badgeImage(.whaleOfficial))
        XCTAssertNotNil(ThemeCursor.badgeImage(.whaleCommunity))
        for t in UITheme.allCases { XCTAssertEqual(ThemeCursor.cursor(for: t, dark: false).image.size, NSSize(width: 32, height: 32)) }
    }
}

extension ThemeCursorTests {
    /// 光标图真的画得出来（箭头尖附近不透明）；DeepSeek 带 SVG 角标时也一样。
    func testCursorRenders() throws {
        for t in [UITheme.warm, .deepseek, .anime, .claudeAnime] {
            let img = ThemeCursor.cursor(for: t, dark: true).image
            let rep = try XCTUnwrap(img.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)), "\(t)")
            let w = rep.pixelsWide, scale = Double(w) / 32
            let c = rep.colorAt(x: Int(4 * scale), y: Int(8 * scale))
            XCTAssertGreaterThan(c?.alphaComponent ?? 0, 0.5, "\(t) 箭头没画出来")
        }
    }
}
