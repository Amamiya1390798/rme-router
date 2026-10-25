// 生成 App 图标：TotalMix 式调音台通道条（推子、电平表、旋钮），象牙色底、暖炭黑面板、陶土色强调。
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
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }
    func round(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius * s, yRadius: radius * s) }

    // macOS 图标网格：824×824 圆角方块，留边 100；象牙色底
    let body = round(rect(100, 100, 824, 824), 185)
    color(0xF0EEE6).setFill(); body.fill()
    color(0xDDD9CE).setStroke(); body.lineWidth = 6 * s; body.stroke()

    // 调音台面板（TotalMix 式通道条）：暖炭黑
    let panel = round(rect(178, 196, 668, 632), 96)
    color(0x262624).setFill(); panel.fill()

    // 四条通道：推子槽、推子帽、电平表、顶部旋钮
    let centers: [CGFloat] = [292, 438, 584, 730]
    let faders: [CGFloat] = [0.42, 0.72, 0.30, 0.58]   // 推子位置（0 底 … 1 顶）
    let meters: [CGFloat] = [0.55, 0.86, 0.38, 0.70]   // 电平高度
    let bottom: CGFloat = 268, travel: CGFloat = 430
    for (i, cx) in centers.enumerated() {
        let gx = cx - 18
        color(0x141413).setFill()
        round(rect(gx - 9, bottom, 18, travel), 9).fill()

        // 电平表：陶土色，顶端一小段浅色
        let mh = travel * meters[i]
        color(0x3A3936).setFill(); round(rect(cx + 30, bottom, 22, travel), 8).fill()
        color(0xD97757).setFill(); round(rect(cx + 30, bottom, 22, mh), 8).fill()
        color(0xF0B49B).setFill(); round(rect(cx + 30, bottom + mh - 34, 22, 34), 8).fill()

        // 推子帽：象牙色，中间一道陶土色刻线；第二条通道整帽高亮
        let fy = bottom + travel * faders[i] - 26
        let cap = round(rect(gx - 42, fy, 84, 52), 14)
        color(i == 1 ? 0xD97757 : 0xF0EEE6).setFill(); cap.fill()
        color(i == 1 ? 0xF0EEE6 : 0xD97757).setFill()
        round(rect(gx - 30, fy + 22, 60, 8), 4).fill()

        // 旋钮
        let k = NSBezierPath(ovalIn: rect(cx - 30, 726, 60, 60))
        color(0x3A3936).setFill(); k.fill()
        let tick = NSBezierPath()
        let ang = CGFloat.pi * (0.75 - 0.5 * faders[i])
        tick.move(to: NSPoint(x: cx * s, y: 756 * s))
        tick.line(to: NSPoint(x: (cx + 22 * cos(ang)) * s, y: (756 + 22 * sin(ang)) * s))
        tick.lineWidth = 9 * s; tick.lineCapStyle = .round
        color(0xF0EEE6).setStroke(); tick.stroke()
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
