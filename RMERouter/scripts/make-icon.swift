// 生成 App 图标：一个大旋钮（暖炭黑底、象牙色旋钮与指针、陶土色刻度弧），下方 TotalMix 字样，参考 TotalMix 图标的构图。
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
    let center = NSPoint(x: 512 * s, y: 572 * s)

    // macOS 图标网格：824×824 圆角方块，留边 100；暖炭黑底，上亮下暗
    let body = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                            xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: color(0x34332F), ending: color(0x1F1E1C))!.draw(in: body, angle: -90)
    color(0x45443F).setStroke(); body.lineWidth = 4 * s; body.stroke()

    // 旋钮刻度环：灰色底轨 270°，陶土色表示当前值
    let value: CGFloat = 0.64
    let start: CGFloat = 225, sweep: CGFloat = 270
    let end = start - sweep * value
    func arc(_ from: CGFloat, _ to: CGFloat, _ hex: UInt32) {
        let p = NSBezierPath()
        p.appendArc(withCenter: center, radius: 245 * s, startAngle: from, endAngle: to, clockwise: true)
        p.lineWidth = 44 * s; p.lineCapStyle = .round
        color(hex).setStroke(); p.stroke()
    }
    arc(start, start - sweep, 0x45443F)
    arc(start, end, 0xD97757)

    // 旋钮本体：象牙色描边的圆盘
    let knob = NSBezierPath(ovalIn: NSRect(x: center.x - 170 * s, y: center.y - 170 * s, width: 340 * s, height: 340 * s))
    color(0x262624).setFill(); knob.fill()
    color(0xF0EEE6).setStroke(); knob.lineWidth = 26 * s; knob.stroke()

    // 指针：从中心指向当前值
    let rad = end * .pi / 180
    let pointer = NSBezierPath()
    pointer.move(to: NSPoint(x: center.x + 20 * s * cos(rad), y: center.y + 20 * s * sin(rad)))
    pointer.line(to: NSPoint(x: center.x + 120 * s * cos(rad), y: center.y + 120 * s * sin(rad)))
    pointer.lineWidth = 30 * s; pointer.lineCapStyle = .round
    color(0xF0EEE6).setStroke(); pointer.stroke()

    // 字样：象牙色衬线体，居中在旋钮下方
    let font = NSFont(name: "Georgia", size: 112 * s) ?? NSFont.systemFont(ofSize: 112 * s)
    let text = NSAttributedString(string: "TotalMix", attributes: [.font: font, .foregroundColor: color(0xF0EEE6), .kern: 2 * s])
    let ts = text.size()
    text.draw(at: NSPoint(x: center.x - ts.width / 2, y: 178 * s))
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
