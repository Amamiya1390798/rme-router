// 生成 App 图标：陶土色渐变底上一个白色旋钮（细刻度弧、圆点指针），右下角小字 total。
// 用法：swift scripts/make-icon.swift <输出目录>   → <输出目录>/AppIcon.icns
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID()).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// 手绘 “total”：x 高为 1 的字形单位，线宽 0.2，圆头。
func drawTotal(rightX: CGFloat, baseline: CGFloat, xHeight h: CGFloat) {
    let w: CGFloat = 0.2, gap: CGFloat = 0.3
    let widths: [CGFloat] = [0.6, 0.9, 0.6, 0.9, 0]
    let total = widths.reduce(0, +) + gap * CGFloat(widths.count - 1)
    var x = rightX / h - total
    let y0 = baseline / h
    let path = NSBezierPath()
    func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
        path.move(to: NSPoint(x: x1 * h, y: y1 * h)); path.line(to: NSPoint(x: x2 * h, y: y2 * h))
    }
    func bowl(_ x: CGFloat) {
        path.append(NSBezierPath(roundedRect: NSRect(x: x * h, y: y0 * h, width: 0.9 * h, height: h),
                                 xRadius: 0.36 * h, yRadius: 0.36 * h))
    }
    for (i, ch) in "total".enumerated() {
        switch ch {
        case "t": line(x + 0.2, y0 + 1.4, x + 0.2, y0); line(x, y0 + 1, x + 0.6, y0 + 1)
        case "o": bowl(x)
        case "a": bowl(x); line(x + 0.9, y0 + 1, x + 0.9, y0)
        default: line(x, y0 + 1.4, x, y0)
        }
        x += widths[i] + gap
    }
    path.lineWidth = w * h; path.lineCapStyle = .round; path.lineJoinStyle = .round
    NSColor.white.withAlphaComponent(0.9).setStroke(); path.stroke()
}

func draw(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let center = NSPoint(x: 512 * s, y: 512 * s)

    // macOS 图标网格：824×824 圆角方块，留边 100；陶土色渐变，上亮下深
    let body = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                            xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: color(0xE69274), ending: color(0xC4593A))!.draw(in: body, angle: -90)

    // 刻度弧：270° 细环，未到的部分半透明，已到的部分纯白
    let value: CGFloat = 0.64
    let start: CGFloat = 225, sweep: CGFloat = 270
    let end = start - sweep * value
    func arc(_ from: CGFloat, _ to: CGFloat, _ c: NSColor) {
        let p = NSBezierPath()
        p.appendArc(withCenter: center, radius: 272 * s, startAngle: from, endAngle: to, clockwise: true)
        p.lineWidth = 30 * s; p.lineCapStyle = .round
        c.setStroke(); p.stroke()
    }
    arc(start, start - sweep, NSColor.white.withAlphaComponent(0.28))
    arc(start, end, .white)

    // 旋钮：白色圆盘，柔和投影
    let knobRect = NSRect(x: center.x - 180 * s, y: center.y - 180 * s, width: 360 * s, height: 360 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(srgbRed: 0.35, green: 0.12, blue: 0.05, alpha: 0.35)
    shadow.shadowBlurRadius = 48 * s
    shadow.shadowOffset = NSSize(width: 0, height: -18 * s)
    shadow.set()
    color(0xFBFAF7).setFill(); NSBezierPath(ovalIn: knobRect).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: .white, ending: color(0xEFECE4))!.draw(in: NSBezierPath(ovalIn: knobRect), angle: -90)

    // 指针：一个陶土色圆点
    let rad = end * .pi / 180, r = 26 * s
    let dot = NSPoint(x: center.x + 118 * s * cos(rad), y: center.y + 118 * s * sin(rad))
    color(0xD06A4A).setFill()
    NSBezierPath(ovalIn: NSRect(x: dot.x - r, y: dot.y - r, width: 2 * r, height: 2 * r)).fill()

    // 右下角小字 “total”：等粗圆头线条、方中带圆的字形（参考 TotalMix 图标上的字样风格），右对齐
    drawTotal(rightX: 806 * s, baseline: 168 * s, xHeight: 46 * s)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try draw(size: CGFloat(base)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try draw(size: CGFloat(base * 2)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.appendingPathComponent("AppIcon.icns").path]
try p.run(); p.waitUntilExit()
try? draw(size: 1024).write(to: out.appendingPathComponent("AppIcon-1024.png"))
print(p.terminationStatus == 0 ? "已生成 \(out.path)/AppIcon.icns" : "iconutil 失败")
