import SwiftUI
import RMECore

/// 路径模式的线（文档第 6.4.4 节）：设备内部的路由画成面板上方的弧线，写通道和电平；
/// 不在这一面的接口画在面板左上角的标签上；进电脑画虚线到“这台 Mac”。线缆段由 CableLayer 加亮。
struct PathLayer: View {
    var model: AppModel
    var path: SignalPathInfo
    var face: PanelFace
    var anchors: [String: CGRect]

    private struct Drawn: Identifiable {
        var id: String
        var a: CGPoint, b: CGPoint
        var label: String
        var dashed: Bool
    }

    /// 锚点 → 点；另一面的接口按设备排成标签，返回标签位置。
    private func point(_ ref: ChannelRef, tags: inout [String: [String]]) -> (CGPoint, tag: (String, CGPoint)?)? {
        guard let (key, off) = model.pathAnchor(ref, face: face), let r = anchors[key] else { return nil }
        if let off {
            var list = tags[key, default: []]
            let i = list.firstIndex(of: off) ?? { list.append(off); return list.count - 1 }()
            tags[key] = list
            let p = CGPoint(x: r.minX + 70, y: r.minY + 12 + CGFloat(i) * 18)
            return (p, (off, p))
        }
        if key.hasPrefix("node:") { return (CGPoint(x: r.minX, y: r.midY), nil) }
        return (CGPoint(x: r.midX, y: r.midY), nil)
    }

    var body: some View {
        var tags: [String: [String]] = [:]
        var shown: [(String, CGPoint)] = []
        var lines: [Drawn] = []
        for s in path.segments {
            guard let (a, ta) = point(s.from, tags: &tags) else { continue }
            if let ta { shown.append(ta) }
            switch s.kind {
            case .cable:
                continue
            case let .route(label):
                guard let to = s.to, let (b, tb) = point(to, tags: &tags) else { continue }
                if let tb { shown.append(tb) }
                lines.append(Drawn(id: s.id, a: a, b: b, label: label, dashed: !s.verified))
            case let .recording(n):
                guard let mac = anchors["node:mac"] else { continue }
                lines.append(Drawn(id: s.id, a: a, b: CGPoint(x: mac.minX, y: mac.maxY - 12), label: "录音 \(n)", dashed: true))
            }
        }
        return ZStack {
            ForEach(lines) { d in
                let lift = max(28, abs(d.b.x - d.a.x) * 0.15)
                let top = min(d.a.y, d.b.y) - lift
                Path { p in
                    p.move(to: d.a)
                    p.addCurve(to: d.b, control1: CGPoint(x: d.a.x, y: top), control2: CGPoint(x: d.b.x, y: top))
                }
                .stroke(Tokens.Palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: d.dashed ? [6, 4] : []))
                Circle().fill(Tokens.Palette.accent).frame(width: 9, height: 9).position(d.a)
                Circle().fill(Tokens.Palette.accent).frame(width: 9, height: 9).position(d.b)
                Text(d.label).font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Tokens.Palette.bg.opacity(0.9)))
                    .foregroundStyle(Tokens.Palette.accent)
                    .fixedSize()
                    .position(x: (d.a.x + d.b.x) / 2, y: top + lift * 0.25)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, t in
                Text(t.0).font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Tokens.Palette.accent.opacity(0.85)))
                    .foregroundStyle(Color.white)
                    .fixedSize()
                    .position(t.1)
            }
        }
    }
}
