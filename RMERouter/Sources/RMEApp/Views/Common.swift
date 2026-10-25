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
