// 生成 App 图标（暖白纸色底、陶土色强调，三个设备节点用信号线连起来）。
// 用法：swift scripts/make-icon.swift <输出目录>   → <输出目录>/AppIcon.icns
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID()).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func draw(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    // macOS 图标网格：824×824 圆角方块，留边 100
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    color(0xF5F3EE).setFill(); path.fill()
    color(0xE4E0D6).setStroke(); path.lineWidth = 6 * s; path.stroke()

    // 三个节点：左上、右上、下中；信号线从左上经下中到右上
    let a = NSPoint(x: 300 * s, y: 650 * s), b = NSPoint(x: 724 * s, y: 650 * s), c = NSPoint(x: 512 * s, y: 330 * s)
    let line = NSBezierPath()
    line.move(to: a); line.curve(to: c, controlPoint1: NSPoint(x: 300 * s, y: 450 * s), controlPoint2: NSPoint(x: 420 * s, y: 330 * s))
    line.curve(to: b, controlPoint1: NSPoint(x: 604 * s, y: 330 * s), controlPoint2: NSPoint(x: 724 * s, y: 450 * s))
    line.lineWidth = 44 * s; line.lineCapStyle = .round
    color(0xB5552F).setStroke(); line.stroke()

    for (p, filled) in [(a, false), (b, false), (c, true)] {
        let r = 78 * s
        let dot = NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        color(filled ? 0xB5552F : 0xFBFAF7).setFill(); dot.fill()
        color(0xB5552F).setStroke(); dot.lineWidth = 30 * s; dot.stroke()
    }
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
