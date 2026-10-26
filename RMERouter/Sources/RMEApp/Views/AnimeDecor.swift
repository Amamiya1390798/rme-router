import SwiftUI
import AppKit

/// 二次元模式的皮肤（文档第 5.1.1、5.1.2 节）：同一套装饰代码，按皮肤换素材与署名。
enum AnimeSkin: String, Sendable {
    /// 深海女仆工坊：素材来自 Small-tailqwq/dsh-deep-whale，CC BY-NC-SA 4.0（上善 → ZipZipPipe → Small-tailqwq），只能非商用。
    case whale
    /// Claude 看板娘：形象由 amamiya 提供；其余素材按 docs/二次元素材-Claude.md 出图，缺的用代码画的替代。
    case claude

    var folder: String { self == .whale ? "Anime" : "AnimeClaude" }
    var base: UITheme { self == .whale ? .deepseek : .warm }
    var theme: UITheme { self == .whale ? .anime : .claudeAnime }
    var toggleTitle: String { self == .whale ? "二次元模式 🐋（深海女仆工坊）" : "二次元模式 🌻（Claude 看板娘）" }

    /// 署名链。
    var credits: [(role: String, name: String, url: String)] {
        switch self {
        case .whale: return [
            ("鲸鱼娘原作", "上善", "https://www.pixiv.net/users/62155430"),
            ("女仆鲸鱼娘二创", "ZipZipPipe", "https://www.pixiv.net/users/18604994"),
            ("深海女仆工坊皮肤", "Small-tailqwq", "https://github.com/Small-tailqwq/dsh-deep-whale"),
        ]
        case .claude: return [("形象", "amamiya", "mailto:cly20041110@gmail.com")]
        }
    }
    var licenseNote: String { self == .whale ? "· CC BY-NC-SA 4.0，仅限非商用" : "· 立绘由作者提供，随 App 分发" }
}

enum AnimeArt {
    static let names = ["maid-left", "maid-right", "palace-day", "palace-night", "lace-tile",
                        "trim-tile", "corner", "face-delighted", "face-sleepy", "face-determined"]

    static func directory(_ skin: AnimeSkin) -> URL? {
        let fm = FileManager.default
        if let r = Bundle.main.resourceURL?.appendingPathComponent(skin.folder), fm.fileExists(atPath: r.path) { return r }
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { u.deleteLastPathComponent() }   // Sources/RMEApp/Views/AnimeDecor.swift → 包根目录
        let repo = u.appendingPathComponent("Resources/\(skin.folder)")
        return fm.fileExists(atPath: repo.path) ? repo : nil
    }
    /// 旧调用（深海女仆工坊）。
    static var directory: URL? { directory(.whale) }

    @MainActor static var cache: [String: NSImage?] = [:]

    /// 按基本名找图（webp / png / jpg 都行）；没有就 nil，调用方用代码画的替代或不显示。
    @MainActor static func image(_ name: String, skin: AnimeSkin? = nil) -> NSImage? {
        guard let skin = skin ?? UITheme.current.animeSkin else { return nil }
        let base = (name as NSString).deletingPathExtension
        let key = "\(skin.rawValue)/\(base)"
        if let hit = cache[key] { return hit }
        let found = directory(skin).flatMap { dir in
            ["webp", "png", "jpg"].lazy.compactMap { NSImage(contentsOf: dir.appendingPathComponent("\(base).\($0)")) }.first
        }
        cache[key] = found
        return found
    }

    /// 旧调用：深海女仆工坊的署名。
    static var credits: [(role: String, name: String, url: String)] { AnimeSkin.whale.credits }
}

extension UITheme {
    var animeSkin: AnimeSkin? { self == .anime ? .whale : self == .claudeAnime ? .claude : nil }
    var isAnime: Bool { animeSkin != nil }
}

/// 设置 → 外观：DeepSeek 下的“二次元模式”开关与署名。
struct AnimeModeRow: View {
    @Bindable var model: AppModel
    var skin: AnimeSkin = .whale
    @State private var showNotice = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Toggle(skin.toggleTitle, isOn: Binding(get: { model.theme == skin.theme },
                                                   set: { model.theme = $0 ? skin.theme : skin.base }))
                .toggleStyle(.switch)
            if model.theme == skin.theme {
                HStack(spacing: Tokens.Space.l) {
                    Toggle("显示立绘", isOn: $model.animeArt)
                    Toggle("气泡动画", isOn: $model.animeMotion)
                }
                .toggleStyle(.checkbox)
                HStack(spacing: 4) {
                    Text("美术：").foregroundStyle(Tokens.Palette.textMuted)
                    ForEach(Array(skin.credits.enumerated()), id: \.offset) { i, c in
                        if i > 0 { Text("→").foregroundStyle(Tokens.Palette.textMuted) }
                        if let u = URL(string: c.url) { Link(c.name, destination: u).help(c.role) } else { Text(c.name) }
                    }
                    Text(skin.licenseNote).foregroundStyle(Tokens.Palette.textMuted)
                    if skin == .whale { Button("协议全文") { showNotice = true }.buttonStyle(.link) }
                }
                .font(Tokens.Font.caption)
            }
        }
        .sheet(isPresented: $showNotice) {
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                ScrollView {
                    Text(Self.noticeText).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack { Spacer(); Button("关闭") { showNotice = false }.keyboardShortcut(.defaultAction) }
            }
            .padding(Tokens.Space.l).frame(width: 620, height: 480)
        }
    }

    static var noticeText: String {
        ["NOTICE.txt", "LICENSE-ARTWORK.txt"].compactMap { n in
            AnimeArt.directory(.whale).flatMap { try? String(contentsOf: $0.appendingPathComponent(n), encoding: .utf8) }
        }.joined(separator: "\n\n────────\n\n")
    }
}

/// 主区背景：宫殿图（浅色昼、深色夜）压一层底色；右下角立绘；上浮气泡。全部不接收点击。
struct AnimeBackdrop: View {
    var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottomTrailing) {
                if let bg = AnimeArt.image(scheme == .dark ? "palace-night" : "palace-day") {
                    Image(nsImage: bg).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: g.size.width, height: g.size.height).clipped()
                    Tokens.Palette.bg.opacity(scheme == .dark ? 0.72 : 0.8)
                } else if UITheme.current.animeSkin == .claude {
                    ClaudePaper()   // 背景图还没出：暖色渐变 + 终端点阵
                }
                if model.animeMotion && !reduceMotion { Bubbles(skin: UITheme.current.animeSkin ?? .whale) }
                if model.animeArt, g.size.width > 1100, let maid = AnimeArt.image("maid-right") {
                    Image(nsImage: maid).resizable().aspectRatio(contentMode: .fit)
                        .frame(height: min(320, g.size.height * 0.45))
                        .opacity(0.92)
                        .padding(.trailing, 6)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 慢速上浮的小气泡（30 fps）；Claude 看板娘换成橙 / 金色的像素小方块。
struct Bubbles: View {
    var skin: AnimeSkin = .whale
    private struct B { var x: Double; var r: Double; var speed: Double; var phase: Double }
    private static let bubbles: [B] = (0 ..< 14).map { i in
        let f = Double(i)
        return B(x: (f * 0.137).truncatingRemainder(dividingBy: 1), r: 3 + (f * 1.7).truncatingRemainder(dividingBy: 6),
                 speed: 0.025 + (f * 0.013).truncatingRemainder(dividingBy: 0.03), phase: (f * 0.271).truncatingRemainder(dividingBy: 1))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                for b in Self.bubbles {
                    let y = 1 - (b.phase + t * b.speed).truncatingRemainder(dividingBy: 1)
                    let x = b.x + 0.012 * sin(t * 0.8 + b.phase * 6)
                    let rect = CGRect(x: x * size.width, y: y * size.height, width: b.r * 2, height: b.r * 2)
                    if skin == .claude {
                        let px = CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: (b.r).rounded(), height: (b.r).rounded())
                        ctx.fill(Path(px), with: .color(Color(hex: b.r > 5 ? 0xC9A15A : 0xD97757).opacity(0.28 * y + 0.08)))
                    } else {
                        ctx.stroke(Path(ellipseIn: rect), with: .color(Color(hex: 0x9BB0E1).opacity(0.35 * y + 0.1)), lineWidth: 1)
                    }
                }
            }
        }
    }
}

/// 侧栏：顶角金色角花、底部女仆立绘（渐隐）。
struct AnimeSidebarDecor: View {
    var model: AppModel

    var body: some View {
        ZStack {
            if let corner = AnimeArt.image("corner") {
                Image(nsImage: corner).resizable().frame(width: 70, height: 70)
                    .scaleEffect(x: -1, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 2).padding(.leading, 2).opacity(0.8)
            } else if UITheme.current.animeSkin == .claude {
                PixelFlower().frame(width: 28, height: 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 10).padding(.trailing, 12).opacity(0.85)
            }
            if model.animeArt, let maid = AnimeArt.image("maid-left") {
                Image(nsImage: maid).resizable().aspectRatio(contentMode: .fit)
                    .frame(height: 230)
                    .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .center))
                    .opacity(0.95)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 92)   // 让出底部设备状态列表
            }
        }
        .allowsHitTesting(false)
    }
}

/// 卡片顶边蕾丝、底边花边（只在二次元模式）。
struct AnimeCardTrim: View {
    var body: some View {
        VStack(spacing: 0) {
            if let lace = AnimeArt.image("lace-tile") {
                Rectangle().fill(ImagePaint(image: Image(nsImage: lace), scale: 0.16)).frame(height: 12).opacity(0.7)
            } else if UITheme.current.animeSkin == .claude {
                // 蕾丝还没出：裙摆那样的橙 → 金细边
                LinearGradient(colors: [Color(hex: 0xD97757), Color(hex: 0xC9A15A), Color(hex: 0xD97757).opacity(0)],
                               startPoint: .leading, endPoint: .trailing).frame(height: 2).opacity(0.8)
            }
            Spacer(minLength: 0)
            if let trim = AnimeArt.image("trim-tile") {
                Rectangle().fill(ImagePaint(image: Image(nsImage: trim), scale: 0.2)).frame(height: 6).opacity(0.3)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 表情小图：没回应 = 困、确认 = 认真、读取成功 = 开心。只在二次元模式出现。
struct AnimeFace: View {
    enum Mood: String { case delighted, sleepy, determined }
    var mood: Mood
    var size: CGFloat = 56

    var body: some View {
        if UITheme.current.isAnime, let img = AnimeArt.image("face-\(mood.rawValue).png") {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// Claude 看板娘的替代背景：奶油色暖渐变，叠一层很淡的终端点阵（第 5.1.2 节）。
struct ClaudePaper: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0xD97757).opacity(scheme == .dark ? 0.16 : 0.10), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Color(hex: 0xC9A15A).opacity(scheme == .dark ? 0.10 : 0.08), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 600)
            Canvas { ctx, size in
                let step: CGFloat = 18
                var y: CGFloat = 9
                while y < size.height {
                    var x: CGFloat = 9
                    while x < size.width { ctx.fill(Path(CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(Tokens.Palette.text.opacity(0.07))); x += step }
                    y += step
                }
            }
        }
    }
}

/// 像素小花（立绘裙子上的放射状花饰的像素版；不是任何公司的标志）。
struct PixelFlower: View {
    private static let map = [
        "..o.o.o..",
        ".o.ooo.o.",
        "..ooooo..",
        "oooogoooo",
        "..ooooo..",
        ".o.ooo.o.",
        "..o.o.o..",
    ]
    var body: some View {
        Canvas { ctx, size in
            let rows = Self.map.count, cols = Self.map[0].count
            let c = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            for (r, line) in Self.map.enumerated() {
                for (k, ch) in line.enumerated() where ch != "." {
                    ctx.fill(Path(CGRect(x: CGFloat(k) * c, y: CGFloat(r) * c, width: c, height: c)),
                             with: .color(Color(hex: ch == "g" ? 0xC9A15A : 0xD97757)))
                }
            }
        }
    }
}
