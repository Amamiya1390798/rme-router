import SwiftUI
import UniformTypeIdentifiers
import RMECore

/// 主窗口：左侧视图与设备列表，中间是当前视图。
public struct RootView: View {
    @Bindable var model: AppModel

    @State private var devicesBuilt = false
    @State private var outputsBuilt = false

    public init(model: AppModel) { self.model = model }

    @State private var sidebarVisible = true

    /// 窗口（第 5.1 节，仿 Claude 桌面 App）：没有标题栏；侧边栏与窗口底色一体；内容是浮在底色上的圆角面板。
    public var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                // 只在值变了才写（同值写入也会通知观察者）。
                Sidebar(selection: Binding(get: { model.section },
                                           set: { if model.section != $0 { model.section = $0 } }),
                        devices: deviceRows)
                    .equatable()
                    .frame(width: 208)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            panel
                .padding(.vertical, 8).padding(.trailing, 8).padding(.leading, sidebarVisible ? 0 : 8)
        }
        .id(model.theme)   // 换主题时重画（颜色在绘制时按主题取值）
        .background(Tokens.Palette.chrome)
        .ignoresSafeArea()
        .sheet(isPresented: $model.showConfirm) { ConfirmSheet(model: model) }
        .sheet(item: $model.eqEditing) { t in EQEditor(model: model, target: t) { model.eqEditing = nil } }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingSheet(model: model) {
                model.onboardingDone = true
                model.showOnboarding = false
            }
        }
        .task {
            // 打开时不让搜索框自动抢焦点（会吞掉快捷键）
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
            if !model.onboardingDone { model.showOnboarding = true }
            if model.xtStatus == .notLoaded { await model.refresh() }
        }
    }

    /// 圆角嵌入面板：顶部一条（页名、状态胶囊、工具按钮），下面是当前页与检查器，底部待应用栏。
    private var panel: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                pages
                if model.showInspector {
                    Divider()
                    InspectorPanel(model: model).frame(width: 300)
                        .transition(.move(edge: .trailing))
                }
            }
            if model.hasPending || !model.history.isEmpty || !model.manualTasks.isEmpty { PendingBar(model: model) }
        }
        .background(Tokens.Palette.bg)
        .overlay(PanelAtmosphere().allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(Tokens.Palette.border))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 1)
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.m) {
            if !sidebarVisible { Spacer().frame(width: 64) }   // 让开红黄绿按钮
            Button { withAnimation(.easeOut(duration: 0.15)) { sidebarVisible.toggle() } } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.borderless).help("显示或隐藏侧边栏（⌃⌘S）")
            .keyboardShortcut("s", modifiers: [.control, .command])
            Text((model.section ?? .devices).title).font(.system(size: 13, weight: .semibold))
            Spacer()
            StatusPill(model: model)
            Spacer()
            SendAcrossButton(model: model).labelStyle(.iconOnly).buttonStyle(.borderless)
            Button { withAnimation(.easeOut(duration: 0.15)) { model.showInspector.toggle() } } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.borderless).help("显示或隐藏右侧检查器")
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .disabled(model.xtStatus == .loading || model.twelveMicStatus == .loading)
                .help("只读：读取 TotalMix（/sendstate、/sendall）与 12Mic（JSON，全部为 null），不改动设备")
        }
        .foregroundStyle(Tokens.Palette.textMuted)
        .padding(.horizontal, Tokens.Space.m)
        .frame(height: 40)
        .contentShape(Rectangle())
        .modifier(WindowDraggable())
    }

    private var pages: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.section, initial: true) {
            if onDevices { devicesBuilt = true }
            if onOutputs { outputsBuilt = true }
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
                case .glossary: GlossaryView()
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

    static func == (a: Sidebar, b: Sidebar) -> Bool { a.devices == b.devices && a.selection == b.selection }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            BrandHeader()
                .padding(.top, 40)   // 红黄绿按钮在上面
                .padding(.bottom, Tokens.Space.l)
            ForEach(AppSection.allCases) { s in item(s) }
            Spacer()
            Text("设备").font(.system(size: 11, weight: .medium)).foregroundStyle(Tokens.Palette.textMuted)
                .padding(.horizontal, 10).padding(.bottom, 2)
            ForEach(devices) { d in
                HStack(spacing: Tokens.Space.s) {
                    EvidenceDot(d.evidence)
                    Text(d.name).font(.system(size: 12)).foregroundStyle(Tokens.Palette.textMuted)
                }
                .padding(.horizontal, 10).padding(.vertical, 3)
            }
        }
        .padding(.horizontal, 10).padding(.bottom, Tokens.Space.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .modifier(WindowDraggable())
    }

    /// 页面项：圆角块，选中浅色底（不用系统蓝）。
    private func item(_ s: AppSection) -> some View {
        let on = selection == s
        let theme = UITheme.current, gemini = theme == .gemini
        return Button { selection = s } label: {
            HStack(spacing: 10) {
                Group {
                    if on, let g = Tokens.sparkle { Image(systemName: s.symbol).foregroundStyle(g) }
                    else { Image(systemName: s.symbol).foregroundStyle(on ? Tokens.Palette.accent : Tokens.Palette.textMuted) }
                }
                .frame(width: 18)
                Text(s.title).font(.system(size: 13, weight: on ? (theme.style.title == .heavy ? .bold : .semibold) : .regular,
                                           design: theme.style.bodyRounded ? .rounded : .default))
                    .foregroundStyle(Tokens.Palette.text)
                Spacer()
            }
            .padding(.horizontal, gemini ? 14 : 10).padding(.vertical, gemini ? 8 : 6)
            .background(RoundedRectangle(cornerRadius: theme.itemRadius)
                .fill(on ? (theme.tintedSelection ? Tokens.Palette.accent.opacity(0.16) : Tokens.Palette.border.opacity(0.8)) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 拖空白处移动窗口（没有标题栏时用，第 5.1 节）：macOS 15 用系统的窗口拖动手势；更早的系统让窗口背景可拖。
struct WindowDraggable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.gesture(WindowDragGesture())
        } else {
            content.background(WindowDragArea()).onAppear { NSApp.windows.forEach { $0.isMovableByWindowBackground = true } }
        }
    }
}

/// 拖这里能移动窗口（没有标题栏时用，第 5.1 节）。只放在侧边栏空白处和面板顶部一条，不影响面板里的拖线。
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
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
            LazyVStack(alignment: .leading, spacing: Tokens.Space.xl) {   // 懒加载：设置卡片多，切页时只建看得见的
                ViewHeader(title: "连接", subtitle: model.confirmMode == .quick
                           ? "读取不会改动任何设置；当前为快速方式：改动点下即发送（48V、大幅抬高仍需确认）。"
                           : "读取不会改动任何设置；改动只在“待应用”栏确认后才发送。")
                StudioConfigCard(model: model)
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: Tokens.Space.m, alignment: .leading)],
                      alignment: .leading, spacing: Tokens.Space.m) {
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

/// 侧边栏顶部：App 图标 + 名字（代替标题栏文字，第 5.1 节）。
struct BrandHeader: View {
    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                BrandName()
                Text("路由与监听").font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted)
            }
        }
        .padding(.vertical, Tokens.Space.xs)
    }
}

/// 工具栏中间的状态胶囊：XT 连接与采样率；点了去“设置 → 连接”（第 5.1 节）。
struct StatusPill: View {
    var model: AppModel

    var body: some View {
        let (dot, text) = summary
        Button {
            model.settingsTab = .connection
            model.section = .settings
        } label: {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 7, height: 7)
                Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Capsule().fill(Tokens.Palette.border.opacity(0.55)))
            .overlay { if let g = Tokens.sparkle { Capsule().strokeBorder(g, lineWidth: 1.2) } }
        }
        .buttonStyle(.plain)
        .help("设备连接状态；点了打开“设置 → 连接”")
    }

    private var summary: (Color, String) {
        let rate = model.xtAudio?.sampleRate.map(AppModel.rateText)
        switch model.xtStatus {
        case .live: return (Tokens.Palette.ok, "XT 已连接" + (rate.map { " · \($0)" } ?? ""))
        case .offlineSaved: return (Tokens.Palette.warn, "XT 未连接 · 显示保存的配置")
        case .loading: return (Tokens.Palette.warn, "正在读取…")
        case .unreachable: return (Tokens.Palette.problem, "TotalMix 没有回应")
        case .notLoaded: return (Tokens.Palette.unknown, "还没读取")
        }
    }
}

/// macOS 15 起工具栏底色透明，和内容连成一片；更早的系统保持默认。
struct TransparentToolbar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}

/// 侧栏名字按主题：普通 / 加粗 / 渐变字 / 实色徽章（第 5.1 节）。
struct BrandName: View {
    var body: some View {
        let t = UITheme.current
        let colors = t.gradientColors.map { Color(nsColor: NSColor(hex: $0)) }
        switch t.style.brand {
        case .plain:
            Text("RME Router").font(.system(size: 14, weight: .semibold, design: t.style.title == .serif ? .serif : .default))
        case .bold:
            Text("RME Router").font(.system(size: 15, weight: .bold))
        case .gradient:
            Text("RME Router").font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
        case .badge:
            Text("RME Router").font(.system(size: 12, weight: .heavy))
                .foregroundStyle(t == .kimi ? Tokens.Palette.bg : Color.white)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(t == .kimi ? Tokens.Palette.text : Tokens.Palette.accent))
        }
    }
}

/// “设备组成”（第 6.4.6 节）：主卡型号、扩展设备开关。改了立即重建并重新读取。
struct StudioConfigCard: View {
    @Bindable var model: AppModel

    static func note(_ c: MainCard) -> String {
        switch c {
        case .madifaceXT: return "MADIface XT：完整档案（接口名、面板图、按位置对照）。"
        case .ufx3: return "Fireface UFX III：接口名按官方手册（Line 1–8、Mic 9–12、AES、ADAT 1/2、MADI，话放增益到 75 dB）；TotalMix 通道顺序按手册推断，接上真机后核对；还没有面板图。"
        case .generic: return "通用：不需要型号资料，任何 TotalMix FX 设备都能用；TotalMix 第 n 路就是主卡第 n 路，没有面板图，接线在“接线”里自己加。"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("设备组成").font(Tokens.Font.cardTitle)
            HStack {
                Text("主卡").foregroundStyle(Tokens.Palette.textMuted)
                Picker("主卡", selection: $model.studioConfig.mainCard) {
                    ForEach(MainCard.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 260)
            }
            .font(Tokens.Font.body)
            Text(Self.note(model.studioConfig.mainCard))
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Tokens.Space.l) {
                Text("扩展设备").foregroundStyle(Tokens.Palette.textMuted)
                ForEach(StudioConfig.expansionNames, id: \.id) { e in
                    Toggle(e.name, isOn: Binding(
                        get: { model.studioConfig.expansions.contains(e.id) },
                        set: { on in
                            var c = model.studioConfig
                            if on { c.expansions.insert(e.id) } else { c.expansions.remove(e.id) }
                            model.studioConfig = c
                        }))
                    .toggleStyle(.checkbox)
                }
            }
            .font(Tokens.Font.body)
            Text("关掉的设备不再读取，也不出现在设备页、接线和路径搜索里。")
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
