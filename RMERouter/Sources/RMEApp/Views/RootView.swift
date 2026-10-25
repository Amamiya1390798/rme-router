import SwiftUI
import RMECore

/// 主窗口：左侧视图与设备列表，中间是当前视图。
public struct RootView: View {
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        NavigationSplitView {
            // 只在值变了才写（同值写入也会通知观察者）。
            Sidebar(selection: Binding(get: { model.section },
                                       set: { if model.section != $0 { model.section = $0 } }),
                    devices: deviceRows)
                .equatable()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch model.section ?? .outputs {
                case .outputs: OutputsView(model: model)
                case .signalFlow: SignalFlowView(model: model)
                case .preamps: PreampsView(model: model)
                case .checkup: CheckupView(model: model)
                case .connection: ConnectionView(model: model)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.hasPending || !model.history.isEmpty { PendingBar(model: model) }
            }
        }
        .sheet(isPresented: $model.showConfirm) { ConfirmSheet(model: model) }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("读取设备", systemImage: "arrow.clockwise")
                }
                .disabled(model.xtStatus == .loading || model.twelveMicStatus == .loading)
                .help("只读：读取 TotalMix（/sendstate、/sendall）与 12Mic（JSON，全部为 null），不改动设备")
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
        if id == "12mic" {
            switch model.twelveMicStatus {
            case .live: return .confirmed
            case .unreachable: return .conflict
            case .loading: return .inferred
            case .notLoaded: return .unknown
            }
        }
        return model.isDemo(id) ? .unknown : .confirmed
    }
}

/// 侧边栏。单独成 Equatable 视图：设备状态不变时不重建列表内容。
/// 注：进入“信号流”页时终端仍会打印 “reentrant operation in its NSTableView delegate”，原因待查（见文档第 2 节）。
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
                ViewHeader(title: "连接", subtitle: model.confirmMode == .quick
                           ? "读取不会改动任何设置；当前为快速方式：改动点下即发送（48V、大幅抬高仍需确认）。"
                           : "读取不会改动任何设置；改动只在“待应用”栏确认后才发送。")
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
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    Text("确认方式").font(Tokens.Font.cardTitle)
                    Picker("确认方式", selection: $model.confirmMode) {
                        ForEach(ConfirmMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    Text(model.confirmMode == .quick
                         ? "快速：点下改动就发送并回读核对，可撤销。打开 48V、一次抬高超过 10 dB 仍会弹确认框。"
                         : "每次确认：改动先进底部“待应用”栏，点“应用…”并在确认框里确认后才发送。")
                        .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    Text("12Mic（HTTP JSON）").font(Tokens.Font.cardTitle)
                    Grid(alignment: .leading, horizontalSpacing: Tokens.Space.m, verticalSpacing: Tokens.Space.s) {
                        GridRow {
                            Text("12Mic 地址").foregroundStyle(Tokens.Palette.textMuted)
                            TextField("http://12mic.local", text: $model.twelveMicURL).frame(width: 240)
                        }
                    }
                    .font(Tokens.Font.body)
                    Button("读取 12Mic") { Task { await model.refreshTwelveMic() } }
                        .disabled(model.twelveMicStatus == .loading)
                    Text(verbatim: "网线连接用 http://12mic.local（有的系统要写成 12mic.local.）；USB 直连用 http://172.20.0.1。设备上需打开 STATE → remote → HTTP Remote。12Mic 没有密码保护，本 App 只发读取请求。")
                        .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
