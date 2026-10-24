import SwiftUI
import RMECore

/// 主窗口：左侧视图与设备列表，中间是当前视图。
public struct RootView: View {
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        NavigationSplitView {
            Sidebar(selection: $model.section, devices: deviceRows)
                .equatable()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch model.section ?? .outputs {
            case .outputs: OutputsView(model: model)
            case .signalFlow: SignalFlowView(model: model)
            case .connection: ConnectionView(model: model)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("从 TotalMix 读取", systemImage: "arrow.clockwise")
                }
                .disabled(model.xtStatus == .loading)
                .help("只读：发送 /sendstate 与 /sendall，不改动 TotalMix")
            }
        }
        .task { if model.xtStatus == .notLoaded { await model.refresh() } }
    }

    private var deviceRows: [Sidebar.DeviceRow] {
        model.snapshot.topology.devices.filter { $0.model != .p16i && $0.model != .p16m }
            .map { .init(id: $0.id, name: $0.name, evidence: deviceEvidence($0.id)) }
    }

    private func deviceEvidence(_ id: String) -> Evidence {
        if id == "xt" {
            switch model.xtStatus {
            case .live: return .confirmed
            case .offlineSaved: return .inferred
            case .unreachable: return .conflict
            default: return .unknown
            }
        }
        return model.isDemo(id) ? .unknown : .confirmed
    }
}

/// 侧边栏。单独成 Equatable 视图：选中变化只改绑定，不重建列表内容
/// （否则 AppKit 在表格回调里收到重建，会报 “reentrant operation in its NSTableView delegate”）。
struct Sidebar: View, Equatable {
    struct DeviceRow: Equatable, Identifiable {
        var id: String
        var name: String
        var evidence: Evidence
    }

    @Binding var selection: AppSection?
    var devices: [DeviceRow]

    static func == (a: Sidebar, b: Sidebar) -> Bool { a.devices == b.devices }

    var body: some View {
        List(selection: $selection) {
            Section("视图") {
                ForEach(AppSection.allCases) { s in
                    Label(s.title, systemImage: s.symbol).tag(s)
                }
            }
            Section("设备") {
                ForEach(devices) { d in
                    HStack(spacing: Tokens.Space.s) {
                        EvidenceDot(d.evidence)
                        Text(d.name)
                    }
                    .selectionDisabled()
                }
            }
        }
    }
}

/// “连接”视图：TotalMix Global OSC 的端口设置与说明。
struct ConnectionView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                ViewHeader(title: "连接", subtitle: "本 App 只读取 TotalMix，不会改动任何设置。")
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    Text("TotalMix FX（Global OSC）").font(Tokens.Font.cardTitle)
                    Grid(alignment: .leading, horizontalSpacing: Tokens.Space.m, verticalSpacing: Tokens.Space.s) {
                        GridRow {
                            Text("TotalMix 地址").foregroundStyle(Tokens.Palette.textMuted)
                            TextField("127.0.0.1", text: $model.settings.host).frame(width: 180)
                        }
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
                    Button("用这些设置读取") { Task { await model.refresh() } }
                        .disabled(model.xtStatus == .loading)
                }
                .card()
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    Text("TotalMix 里需要的设置").font(Tokens.Font.cardTitle)
                    ForEach(Self.steps, id: \.self) { Text($0).font(Tokens.Font.body) }
                    Text("开着 Wi-Fi 时 TotalMix 可能绑定 IPv6；收不到回包时把地址改成 ::1 试试。")
                        .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(Tokens.Space.xl)
        }
        .background(Tokens.Palette.bg)
    }

    static let steps = [
        "1. Options 菜单勾选 OSC Control。",
        "2. Settings → OSC：选一个空闲的 Controller，勾 In Use。",
        "3. Port (incoming) 与 Port (outgoing) 填上面两个端口；Remote Host 填 127.0.0.1。",
        "4. Compatibility (Mode) 选 Global OSC，关闭 Follow Submix。",
    ]
}
