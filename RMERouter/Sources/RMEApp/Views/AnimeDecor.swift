import SwiftUI
import AppKit

/// 二次元模式（文档第 5.1.1 节）：素材来自 Small-tailqwq/dsh-deep-whale 的“深海女仆工坊”，
/// CC BY-NC-SA 4.0（上善 → ZipZipPipe → Small-tailqwq），只能非商用，署名见 Resources/Anime/NOTICE.txt。
enum AnimeArt {
    static let directory: URL? = {
        let fm = FileManager.default
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Anime"), fm.fileExists(atPath: r.path) { return r }
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { u.deleteLastPathComponent() }   // Sources/RMEApp/Views/AnimeDecor.swift → 包根目录
        let repo = u.appendingPathComponent("Resources/Anime")
        return fm.fileExists(atPath: repo.path) ? repo : nil
    }()

    @MainActor static var cache: [String: NSImage] = [:]

    @MainActor static func image(_ name: String) -> NSImage? {
        if let i = cache[name] { return i }
        guard let url = directory?.appendingPathComponent(name), let i = NSImage(contentsOf: url) else { return nil }
        cache[name] = i
        return i
    }

    static let names = ["maid-left.webp", "maid-right.webp", "palace-day.webp", "palace-night.webp", "lace-tile.png",
                        "trim-tile.webp", "corner.png", "face-delighted.png", "face-sleepy.png", "face-determined.png"]

    /// 署名链（CC BY-NC-SA 4.0 要求完整保留）。
    static let credits: [(role: String, name: String, url: String)] = [
        ("鲸鱼娘原作", "上善", "https://www.pixiv.net/users/62155430"),
        ("女仆鲸鱼娘二创", "ZipZipPipe", "https://www.pixiv.net/users/18604994"),
        ("深海女仆工坊皮肤", "Small-tailqwq", "https://github.com/Small-tailqwq/dsh-deep-whale"),
    ]
}

extension UITheme {
    var isAnime: Bool { self == .anime }
}

/// 设置 → 外观：DeepSeek 下的“二次元模式”开关与署名。
struct AnimeModeRow: View {
    @Bindable var model: AppModel
    @State private var showNotice = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Toggle("二次元模式 🐋（深海女仆工坊）", isOn: Binding(get: { model.theme == .anime },
                                                       set: { model.theme = $0 ? .anime : .deepseek }))
                .toggleStyle(.switch)
            if model.theme == .anime {
                HStack(spacing: Tokens.Space.l) {
                    Toggle("显示立绘", isOn: $model.animeArt)
                    Toggle("气泡动画", isOn: $model.animeMotion)
                }
                .toggleStyle(.checkbox)
                HStack(spacing: 4) {
                    Text("美术：").foregroundStyle(Tokens.Palette.textMuted)
                    ForEach(Array(AnimeArt.credits.enumerated()), id: \.offset) { i, c in
                        if i > 0 { Text("→").foregroundStyle(Tokens.Palette.textMuted) }
                        Link(c.name, destination: URL(string: c.url)!).help(c.role)
                    }
                    Text("· CC BY-NC-SA 4.0，仅限非商用").foregroundStyle(Tokens.Palette.textMuted)
                    Button("协议全文") { showNotice = true }.buttonStyle(.link)
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
            AnimeArt.directory.flatMap { try? String(contentsOf: $0.appendingPathComponent(n), encoding: .utf8) }
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
                if let bg = AnimeArt.image(scheme == .dark ? "palace-night.webp" : "palace-day.webp") {
                    Image(nsImage: bg).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: g.size.width, height: g.size.height).clipped()
                    Tokens.Palette.bg.opacity(scheme == .dark ? 0.72 : 0.8)
                }
                if model.animeMotion && !reduceMotion { Bubbles() }
                if model.animeArt, g.size.width > 1100, let maid = AnimeArt.image("maid-right.webp") {
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

/// 慢速上浮的小气泡（30 fps）。
struct Bubbles: View {
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
                    ctx.stroke(Path(ellipseIn: rect), with: .color(Color(hex: 0x9BB0E1).opacity(0.35 * y + 0.1)), lineWidth: 1)
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
            if let corner = AnimeArt.image("corner.png") {
                Image(nsImage: corner).resizable().frame(width: 70, height: 70)
                    .scaleEffect(x: -1, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 2).padding(.leading, 2).opacity(0.8)
            }
            if model.animeArt, let maid = AnimeArt.image("maid-left.webp") {
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
            if let lace = AnimeArt.image("lace-tile.png") {
                Rectangle().fill(ImagePaint(image: Image(nsImage: lace), scale: 0.16)).frame(height: 12).opacity(0.7)
            }
            Spacer(minLength: 0)
            if let trim = AnimeArt.image("trim-tile.webp") {
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
