import SwiftUI
import RMECore

extension ControlDomain {
    var displayName: String {
        switch self {
        case .totalMix: return "TotalMix"
        case .twelveMic: return "12Mic"
        case .xtc: return "XTC"
        case .manual: return "人工"
        }
    }
}

extension ConfirmMode {
    /// 当前确认方式（读 App 的设置；编辑器按钮文字用）。
    static var current: ConfirmMode {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(ConfirmMode.init(rawValue:)) ?? .always
    }
    /// 编辑器里提交按钮的文字。
    var applyLabel: String { self == .quick ? "应用" : "加入待应用" }
}

/// 视图标题：衬线 22，下面一行说明。
struct ViewHeader: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(title).font(Tokens.Font.viewTitle).foregroundStyle(Tokens.Palette.text)
            if let subtitle {
                Text(subtitle).font(Tokens.Font.body).foregroundStyle(Tokens.Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 小标签，例如“演示数据”“设备未连接”。
struct Badge: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(Tokens.Font.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1))
    }
}

/// 顶部状态条：XT 读取状态与演示数据提示。
struct StatusStrip: View {
    var status: XTStatus
    var lastLoaded: Date?
    var demoDevices: [String]
    var twelveMic: TwelveMicStatus = .notLoaded

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.s) {
                dot
                Text(text).font(Tokens.Font.body).foregroundStyle(Tokens.Palette.text)
                if let lastLoaded {
                    Text("读取于 \(lastLoaded.formatted(date: .omitted, time: .standard))")
                        .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                }
            }
            if let note = twelveMicNote {
                HStack(spacing: Tokens.Space.s) {
                    EvidenceDot(twelveMic == .live ? .confirmed : (twelveMic == .loading ? .inferred : .conflict))
                    Text(note).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                }
            }
            if !demoDevices.isEmpty {
                Text("\(demoDevices.joined(separator: "、")) 还没有接入，显示的是演示数据（灰色虚线点）。")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var twelveMicNote: String? {
        switch twelveMic {
        case .notLoaded: return nil
        case .loading: return "正在读取 12Mic…"
        case .live: return "12Mic 已连接，显示的是实时配置"
        case let .unreachable(reason): return reason
        }
    }

    private var text: String {
        switch status {
        case .notLoaded: return "还没有从 TotalMix 读取"
        case .loading: return "正在从 TotalMix 读取…"
        case .live: return "MADIface XT 已连接，显示的是实时配置"
        case .offlineSaved: return "MADIface XT 未连接：显示的是 TotalMix 保存的配置"
        case let .unreachable(reason): return reason
        }
    }

    @ViewBuilder private var dot: some View {
        switch status {
        case .live: EvidenceDot(.confirmed)
        case .offlineSaved, .loading: EvidenceDot(.inferred)
        case .notLoaded: EvidenceDot(.unknown)
        case .unreachable: EvidenceDot(.conflict)
        }
    }
}

/// 电平条（文档第 7.7 节）：-60…0 dB；-6 dB 以上黄，0 dB 及以上红。没有信号时写“无信号”，不画 0。
/// 包在 TimelineView 里：信号停了、没有新数据时也会按时变成“无信号”。
struct MeterBar: View {
    var store: MeterStore
    var ref: ChannelRef
    var width: CGFloat = 70

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            if let dB = store.level(ref, now: context.date) {
                let fraction = min(max((dB + 60) / 60, 0), 1)
                HStack(spacing: Tokens.Space.xs) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Tokens.Palette.border)
                        Capsule().fill(color(dB)).frame(width: width * fraction)
                    }
                    .frame(width: width, height: 4)
                    Text(dB <= -60 ? "-∞" : String(format: "%.0f", dB))
                        .font(Tokens.Font.caption.monospacedDigit()).foregroundStyle(Tokens.Palette.textMuted)
                        .frame(width: 26, alignment: .trailing)
                }
                .help("峰值电平 \(String(format: "%.1f", dB)) dB")
            } else {
                Text("无信号").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.unknown)
                    .help("XT 未连接，或 TotalMix 没有发送电平（OSC 设置里勾选 Send Level Data）")
            }
        }
    }

    private func color(_ dB: Double) -> Color {
        dB >= 0 ? Tokens.Palette.problem : dB >= -6 ? Tokens.Palette.warn : Tokens.Palette.ok
    }
}

/// 在线却一直收不到电平时的提示（第 7.7 节）。
struct LevelHint: View {
    var store: MeterStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if store.likelyLevelSendingOff(now: context.date) {
                Label("收不到电平：在 TotalMix 的 Settings → OSC 里勾选 Send Level Data。", systemImage: "waveform.slash")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.warn)
            }
        }
    }
}
