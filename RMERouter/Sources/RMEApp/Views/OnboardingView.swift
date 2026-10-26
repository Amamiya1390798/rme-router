import SwiftUI
import RMECore

/// 首次使用向导（阶段 D2）：TotalMix 连接、12Mic 地址、接线确认、确认方式。随时可从“设置 → 连接”重新打开。
struct OnboardingSheet: View {
    @Bindable var model: AppModel
    var finish: () -> Void
    @State private var step = 0

    static let titles = ["欢迎", "连接 TotalMix", "连接 12Mic", "确认接线", "确认方式"]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            HStack {
                Text(Self.titles[step]).font(Tokens.Font.viewTitle)
                Spacer()
                Text("\(step + 1) / \(Self.titles.count)").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            }
            Group {
                switch step {
                case 0: welcome
                case 1: totalMix
                case 2: twelveMic
                case 3: wiring
                default: confirm
                }
            }
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
            HStack {
                Button("跳过向导") { finish() }
                Spacer()
                if step > 0 { Button("上一步") { step -= 1 } }
                if step < Self.titles.count - 1 {
                    Button("下一步") { step += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("开始使用") { finish() }.keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent).tint(Tokens.Palette.accent)
                }
            }
        }
        .padding(Tokens.Space.xl)
        .frame(width: 600)
        .background(Tokens.Palette.bg)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("RME Router 用“谁的声音送到哪里”的方式，管理 MADIface XT、12Mic、OctaMic XTC 之间的路由。TotalMix 要在后台运行。")
            Text("几条安全承诺：").font(Tokens.Font.cardTitle)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text("• 读取不会改动任何设备。")
                Text("• 任何改动都先让你看清要发什么；默认要确认后才发送。")
                Text("• 切换 48V、一次抬高超过 20 dB 总是要再确认。")
                Text("• 读不到的状态一律显示“未知”，不显示假数据。")
            }
            Text("接下来几步帮你连上设备，大约一分钟。").foregroundStyle(Tokens.Palette.textMuted)
        }
        .font(Tokens.Font.body)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var totalMix: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("在 TotalMix 里：").font(Tokens.Font.cardTitle)
            ForEach(ConnectionView.steps, id: \.self) { Text($0).font(Tokens.Font.body) }
            Grid(alignment: .leading, horizontalSpacing: Tokens.Space.m, verticalSpacing: Tokens.Space.s) {
                GridRow {
                    Text("Port (incoming)").foregroundStyle(Tokens.Palette.textMuted)
                    TextField("7011", value: $model.settings.port, format: .number.grouping(.never)).frame(width: 100)
                }
                GridRow {
                    Text("Port (outgoing)").foregroundStyle(Tokens.Palette.textMuted)
                    TextField("9011", value: $model.settings.listenPort, format: .number.grouping(.never)).frame(width: 100)
                }
            }
            .font(Tokens.Font.body)
            HStack {
                Button("测试连接") { Task { await model.refreshTotalMix() } }
                    .disabled(model.xtStatus == .loading)
                xtResult
            }
        }
    }

    @ViewBuilder private var xtResult: some View {
        switch model.xtStatus {
        case .notLoaded: EmptyView()
        case .loading: Text("正在连接…").foregroundStyle(Tokens.Palette.textMuted)
        case .live: HStack { Label("已连上，\(mainName) 在线", systemImage: "checkmark.circle").foregroundStyle(Tokens.Palette.ok); AnimeFace(mood: .delighted, size: 40) }
        case .offlineSaved: Label("已连上 TotalMix；\(mainName) 未连接（显示保存的配置）", systemImage: "checkmark.circle").foregroundStyle(Tokens.Palette.ok)
        case let .unreachable(r): Text(r).foregroundStyle(Tokens.Palette.problem).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var twelveMic: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text(verbatim: "网线连接用 http://12mic.local（有的系统要写成 12mic.local.）；USB 直连用 http://172.20.0.1。设备上打开 STATE → remote → HTTP Remote。没有 12Mic 可以跳过这一步。")
                .font(Tokens.Font.body).fixedSize(horizontal: false, vertical: true)
            TextField("http://12mic.local", text: $model.twelveMicURL).frame(width: 260)
            HStack {
                Button("测试连接") { Task { await model.refreshTwelveMic() } }
                    .disabled(model.twelveMicStatus == .loading)
                switch model.twelveMicStatus {
                case .notLoaded: EmptyView()
                case .loading: Text("正在连接…").foregroundStyle(Tokens.Palette.textMuted)
                case .live: Label("已连上 12Mic", systemImage: "checkmark.circle").foregroundStyle(Tokens.Palette.ok)
                case let .unreachable(r): Text(r).foregroundStyle(Tokens.Palette.problem).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var wiring: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("App 按下面这张接线表计算信号路径。和实物不一样的话，之后在“设置 → 接线”改。")
                .font(Tokens.Font.body).fixedSize(horizontal: false, vertical: true)
            ForEach(model.links) { link in
                Text(verbatim: "\(name(link.from)) ⇒ \(name(link.to))").font(Tokens.Font.body)
            }
        }
    }

    private var confirm: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Picker("确认方式", selection: $model.confirmMode) {
                ForEach(ConfirmMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 240)
            Text("每次确认：改动先进底部“待应用”栏，确认后才发送（推荐刚开始用）。\n快速：点下改动就发送；切换 48V、一次抬高超过 20 dB 仍会确认。\n之后在“设置 → 连接”随时可以改。")
                .font(Tokens.Font.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func name(_ portID: String) -> String {
        guard let p = model.snapshot.topology.port(portID) else { return portID }
        return "\(model.snapshot.topology.device(p.deviceID)?.name ?? p.deviceID) · \(p.name)"
    }
}
