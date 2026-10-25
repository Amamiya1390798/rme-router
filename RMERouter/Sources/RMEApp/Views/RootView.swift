import SwiftUI
import UniformTypeIdentifiers
import RMECore

/// 主窗口：左侧视图与设备列表，中间是当前视图。
public struct RootView: View {
    @Bindable var model: AppModel

    @State private var devicesBuilt = false
    @State private var outputsBuilt = false

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        NavigationSplitView {
            // 只在值变了才写（同值写入也会通知观察者）。
            Sidebar(selection: Binding(get: { model.section },
                                       set: { if model.section != $0 { model.section = $0 } }),
                    devices: deviceRows)
                .equatable()
                .id(model.theme)   // 换主题时重画（颜色在绘制时按主题取值）；只重建内容，不动窗口和工具栏
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            ZStack {
                // 设备页建一次就一直留着（藏在后面），切回来不用重建：200 多条通道条重建一次要 0.2 秒以上
                if devicesBuilt {
                    DevicesView(model: model)
                        .opacity(onDevices ? 1 : 0)
                        .allowsHitTesting(onDevices)
                        .accessibilityHidden(!onDevices)
                        .environment(\.pageActive, onDevices)
                }
                // 输出页同样常驻（卡片多，重建一次约 0.15 秒）
                if outputsBuilt {
                    OutputsView(model: model)
                        .opacity(onOutputs ? 1 : 0)
                        .allowsHitTesting(onOutputs)
                        .accessibilityHidden(!onOutputs)
                }
                if !onDevices && !onOutputs { otherPage }
            }
            .id(model.theme)
            .onChange(of: model.section, initial: true) {
                if onDevices { devicesBuilt = true }
                if onOutputs { outputsBuilt = true }
            }
            .inspector(isPresented: $model.showInspector) {
                InspectorPanel(model: model).inspectorColumnWidth(min: 260, ideal: 300, max: 420)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.hasPending || !model.history.isEmpty || !model.manualTasks.isEmpty { PendingBar(model: model) }
            }
        }
        .sheet(isPresented: $model.showConfirm) { ConfirmSheet(model: model) }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingSheet(model: model) {
                model.onboardingDone = true
                model.showOnboarding = false
            }
        }
        .toolbar {
            ToolbarItem { SendAcrossButton(model: model) }
            ToolbarItem {
                Button { model.showInspector.toggle() } label: { Label("检查器", systemImage: "sidebar.right") }
                    .help("显示或隐藏右侧检查器")
            }
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
        .task {
            if !model.onboardingDone { model.showOnboarding = true }
            if model.xtStatus == .notLoaded { await model.refresh() }
        }
    }

    private var onDevices: Bool { (model.section ?? .devices) == .devices }
    private var onOutputs: Bool { model.section == .outputs }

    @ViewBuilder private var otherPage: some View {
        switch model.section ?? .devices {
        case .devices: EmptyView()
        case .outputs: EmptyView()
        case .preamps: PreampsView(model: model)
        case .checkup:
            PageTabs(selection: $model.checkupTab) {
                switch model.checkupTab {
                case .checkup: CheckupView(model: model)
                case .clock: ClockView(model: model)
                }
            }
        case .scenes: ScenesView(model: model)
        case .settings:
            PageTabs(selection: $model.settingsTab) {
                switch model.settingsTab {
                case .connection: ConnectionView(model: model)
                case .wiring: WiringView(model: model)
                }
            }
        }
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
            Section("页面") {
                ForEach(AppSection.allCases) { s in
                    Label(s.title, systemImage: s.symbol).tag(s)
                }
            }
            Section("设备状态") {
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

/// 页内分栏（第 6.8 节）：顶部居中一组分段按钮，下面是当前分栏。
struct PageTabs<Tab: Hashable & Identifiable & CaseIterable & TitledTab, Content: View>: View where Tab.AllCases: RandomAccessCollection {
    @Binding var selection: Tab
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Picker("分栏", selection: $selection) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .padding(.vertical, Tokens.Space.s)
            .frame(maxWidth: .infinity)
            .background(Tokens.Palette.bg)
            Divider()
            content()
        }
    }
}

extension EnvironmentValues {
    /// 这一页是不是当前显示的页（设备页藏在后面时为 false：不响应 Esc 等快捷键）。
    @Entry var pageActive = true
}

protocol TitledTab { var title: String { get } }
extension CheckupTab: TitledTab {}
extension SettingsTab: TitledTab {}
extension DevicesPane: TitledTab {}

/// “连接”视图：TotalMix Global OSC 的端口设置与说明。
struct ConnectionView: View {
    @Bindable var model: AppModel
    @State private var exporting = false
    @State private var importing = false
    @State private var backupDoc: BackupDocument?
    @State private var backupMessage: String?

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
                         ? "快速：点下改动就发送并回读核对，可撤销。切换 48V、一次抬高超过 20 dB 仍会弹确认框。"
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
                XTCConnectionCard(model: model)
                AppearanceCard(model: model)
                Button("重新打开首次设置向导") { model.showOnboarding = true }
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    Text("备份").font(Tokens.Font.cardTitle)
                    HStack {
                        Button("导出…") {
                            do { backupDoc = BackupDocument(data: try model.exportBackup()); exporting = true }
                            catch { backupMessage = "导出失败：\(error)" }
                        }
                        Button("导入…") { importing = true }
                    }
                    Text("包含连接设置、确认方式、接线和全部场景。导入会替换当前设置与接线，场景合并。")
                        .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
                    if let backupMessage {
                        Text(backupMessage).font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                .fileExporter(isPresented: $exporting, document: backupDoc, contentType: .json,
                              defaultFilename: "RME Router 备份 \(Date().formatted(.iso8601.year().month().day()))") { result in
                    if case let .failure(e) = result { backupMessage = "导出失败：\(e.localizedDescription)" }
                    else { backupMessage = "已导出。" }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    switch result {
                    case let .success(url):
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        do { backupMessage = try model.importBackup(Data(contentsOf: url)).text }
                        catch let e as BackupError { backupMessage = e.text }
                        catch { backupMessage = "导入失败：\(error.localizedDescription)" }
                    case let .failure(e):
                        backupMessage = "导入失败：\(e.localizedDescription)"
                    }
                }
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

/// “外观”一节（第 5.1 节）：浅色 / 深色、主题。只换颜色。
struct AppearanceCard: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("外观").font(Tokens.Font.cardTitle)
            Picker("外观", selection: $model.appearance) {
                ForEach(UIAppearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 260)
            HStack(spacing: Tokens.Space.m) {
                ForEach(UITheme.allCases) { t in swatch(t) }
            }
            Text("只换颜色，不改布局。绿 = 已确认、黄 = 推断、红 = 有问题，在每套主题里意义都一样。")
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// 主题样块：底色、卡片、强调色、三种状态色。
    private func swatch(_ t: UITheme) -> some View {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        func c(_ k: UITheme.Token) -> Color { let v = t.value(k); return Color(nsColor: NSColor(hex: dark ? v.1 : v.0)) }
        return Button { model.theme = t } label: {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 6).fill(c(.surface))
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 3) {
                            Capsule().fill(c(.accent)).frame(width: 22, height: 6)
                            Circle().fill(c(.ok)).frame(width: 6, height: 6)
                            Circle().fill(c(.warn)).frame(width: 6, height: 6)
                            Circle().fill(c(.problem)).frame(width: 6, height: 6)
                        }
                        .padding(6)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text("Aa 通道").font(.system(size: 10)).foregroundStyle(c(.text)).padding(6)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(c(.border)))
                    .frame(width: 110, height: 56)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(c(.bg)))
                Text(t.title).font(Tokens.Font.caption)
            }
            .padding(4)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.theme == t ? Tokens.Palette.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help("切换到“\(t.title)”")
    }
}
