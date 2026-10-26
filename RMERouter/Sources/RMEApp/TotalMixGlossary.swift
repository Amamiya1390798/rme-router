import Foundation

/// TotalMix 中文对照（“设置 → TotalMix 对照”页，文档第 6.8 节）。
/// 出处：TotalMix FX 自带帮助、程序里各窗口的文字（本机 2.x 版只读提取）、Global OSC 协议表。没有出处的写“推断”。
public struct GlossaryRow: Identifiable, Hashable, Sendable {
    public enum App: Sendable { case done, required, planned, no, info }
    public var en: String
    public var zh: String
    public var note: String = ""
    public var app: App = .no
    /// 本 App 里在哪（app 为 done / required 时）。
    public var appWhere: String = ""
    public var id: String { en + "|" + zh }
}

public struct GlossarySection: Identifiable, Sendable {
    public var title: String
    /// 在 TotalMix 里怎么打开。
    public var path: String
    public var rows: [GlossaryRow]
    public var id: String { title }
}

public enum TotalMixGlossary {
    typealias R = GlossaryRow

    public static let sections: [GlossarySection] = [
        GlossarySection(title: "通道条（输入、回放）", path: "主窗口上两行", rows: [
            R(en: "Name", zh: "通道名", note: "双击可改名", app: .done, appWhere: "通道条顶部（只读显示）"),
            R(en: "MONO / Stereo", zh: "单声道 / 立体声", app: .done, appWhere: "通道条“单声道 / 立体声”按钮"),
            R(en: "Gain（话筒图标 + 数字）", zh: "话放增益", app: .done, appWhere: "通道条“🎙 数字”、前级页"),
            R(en: "Pan（L100 / C / R100）", zh: "声像：送到当前输出时偏左偏右", note: "居中时衰减 -3 dB", app: .done, appWhere: "点电平数字的弹窗"),
            R(en: "M", zh: "静音 Mute", app: .done, appWhere: "通道条 M"),
            R(en: "S", zh: "独奏 Solo（Live 模式下变成 PFL 预听）", note: "本机读不到每条的状态", app: .no),
            R(en: "UFL / OVR / 数字", zh: "电平数字：UFL 低于显示下限（没信号，推断）、OVR 过载", app: .done, appWhere: "通道条电平条"),
            R(en: "Fader", zh: "推子：这一路送到当前选中输出的电平（不是总音量）", app: .done, appWhere: "通道条上的电平数字"),
            R(en: "T", zh: "Trim：推子一次改这一路送到所有输出的电平", app: .no),
            R(en: "⚙ (Settings)", zh: "打开这条的设置面板", app: .info),
            R(en: "EQ", zh: "均衡器：3 段参数 EQ + 低切", note: "类型、低切斜率暂只读", app: .done, appWhere: "通道条“EQ”按钮"),
            R(en: "D", zh: "动态：压缩 / 扩展 / 自动电平", app: .planned),
            R(en: "底部输出名 ⌄", zh: "推子当前送去的输出", app: .done, appWhere: "设备页点一个输出条"),
        ]),
        GlossarySection(title: "通道设置面板（点 ⚙）", path: "通道条上的 ⚙", rows: [
            R(en: "stereo", zh: "合并 / 拆分立体声", app: .done, appWhere: "通道条"),
            R(en: "+48V", zh: "幻象电源", note: "打开一律确认", app: .done, appWhere: "前级页"),
            R(en: "auto set", zh: "自动降增益防过载，保持约 6 dB 余量", app: .done, appWhere: "检查器“通道条”第二行"),
            R(en: "gain", zh: "话放增益", app: .done, appWhere: "通道条、前级页"),
            R(en: "send FX", zh: "送到效果总线（混响、回声）的量", app: .done, appWhere: "检查器“送效果”"),
            R(en: "width", zh: "立体声宽度：+1 全立体声、0 单声道、-1 左右互换", app: .done, appWhere: "检查器“宽度”"),
            R(en: "MS proc.", zh: "M/S 处理：单声道信息送左、立体声信息送右", app: .done, appWhere: "检查器“M/S”"),
            R(en: "phase / ØL / ØR", zh: "相位反转（立体声可左右分开）", app: .done, appWhere: "通道条 Ø"),
            R(en: "return FX（输出）", zh: "效果混进这个输出的量", app: .done, appWhere: "检查器“效果返回”"),
            R(en: "talkback（输出）", zh: "这个输出接收对讲", app: .done, appWhere: "检查器“收对讲”"),
            R(en: "no trim（输出）", zh: "这个输出不受 T（Trim）影响", app: .no),
            R(en: "loopback（输出）", zh: "把这个输出的混音送进电脑同号录音通道（顶替那一路硬件输入）", app: .done, appWhere: "输出条“录”"),
            R(en: "Level（部分设备）", zh: "模拟参考电平（-10 dBV / +4 dBu / Lo/HiGain）", note: "XT 没有", app: .info),
        ]),
        GlossarySection(title: "控制室与右侧控制条", path: "主窗口右侧", rows: [
            R(en: "Assign → Main Out", zh: "主输出接哪一对", app: .done, appWhere: "控制室“主输出”"),
            R(en: "Assign → Phones", zh: "耳机用哪一对", app: .done, appWhere: "控制室“耳机 1 / 2”"),
            R(en: "Dim", zh: "主输出临时降音量", app: .done, appWhere: "控制室"),
            R(en: "Mono", zh: "主输出合成单声道", app: .done, appWhere: "控制室“Main 单声道”"),
            R(en: "Talkback", zh: "对讲", note: "先在 Mixer Settings 指定对讲话筒", app: .done, appWhere: "控制室“对讲”"),
            R(en: "External In", zh: "外部立体声输入替换主输出", app: .done, appWhere: "控制室“外部输入”"),
            R(en: "Mute FX", zh: "主输出静音效果返回", app: .done, appWhere: "控制室“静音效果”"),
            R(en: "Recall", zh: "主输出回到预设音量", app: .no),
            R(en: "Snapshots 1–8", zh: "快照：整套混音", note: "保存只能在 TotalMix 里做", app: .done, appWhere: "控制室“快照”（调用）"),
            R(en: "Global Mute / Solo", zh: "全局静音 / 独奏", app: .done, appWhere: "控制室“全局静音”（独奏做不了）"),
            R(en: "Undo / Redo", zh: "TotalMix 自己的撤销", note: "本 App 有自己的撤销", app: .no),
        ]),
        GlossarySection(title: "TotalMix FX 菜单", path: "菜单栏 TotalMix FX", rows: [
            R(en: "About TotalMix FX", zh: "版本信息", app: .info),
            R(en: "Settings…", zh: "偏好设置（见下面“Preferences”）", app: .info),
            R(en: "Quit TotalMix FX / Quit and Keep Windows", zh: "退出", note: "本 App 需要 TotalMix 在后台运行；不想看见用 Hide", app: .info),
        ]),
        GlossarySection(title: "File 菜单", path: "菜单栏 File", rows: [
            R(en: "New TotalMix Window", zh: "再开一个 TotalMix 窗口"),
            R(en: "Load Snapshot… / Save Snapshot As…", zh: "从文件读 / 把快照存成文件"),
            R(en: "Preload all Snapshots…", zh: "一次读入全部 8 个快照"),
            R(en: "Load Workspace… / Save Workspace As…", zh: "读取 / 另存工作区（整套混音 + 界面）", note: "本 App 的“场景”可存整套路由与通道条", app: .info),
            R(en: "Workspace Quick Select", zh: "快速切换常用工作区"),
            R(en: "Open Recent / Close Window / Close All", zh: "最近文件 / 关窗口"),
        ]),
        GlossarySection(title: "Function 菜单", path: "菜单栏 Function", rows: [
            R(en: "Mixer View / Matrix View", zh: "调音台视图 / 矩阵视图"),
            R(en: "Toggle Mixer Window / Toggle Matrix Window", zh: "打开或关闭这两个窗口"),
        ]),
        GlossarySection(title: "Options 菜单", path: "菜单栏 Options", rows: [
            R(en: "Enable MIDI Control", zh: "允许 MIDI 控制 TotalMix"),
            R(en: "Submix linked to MIDI Controller", zh: "MIDI 切子混音时界面跟着切"),
            R(en: "Enable OSC Control", zh: "允许 OSC 控制", note: "本 App 靠它工作", app: .required, appWhere: "必须勾上"),
            R(en: "Submix linked to OSC Controller", zh: "OSC 切子混音时界面跟着切（Follow Submix）", app: .required, appWhere: "Global OSC 下要关掉"),
            R(en: "Mixer Settings…", zh: "设置窗口（General / MIDI / OSC / Aux Devices，见下面）", app: .info),
            R(en: "Channel Layout…", zh: "隐藏 / 显示通道、布局预设（见下面）", app: .info),
            R(en: "ARC & Key Command Settings…", zh: "ARC 遥控器与快捷键（见下面）"),
            R(en: "Reset Mix ▸ Straight playback, mix to Main Out", zh: "回放直通并混到主输出", note: "会清掉现有混音"),
            R(en: "Reset Mix ▸ Straight playback", zh: "回放直通（不混到主输出）", note: "会清掉现有混音"),
            R(en: "Reset Mix ▸ Clear all submixes", zh: "清空全部子混音", note: "慎用"),
            R(en: "Reset Mix ▸ Set output volumes", zh: "重设输出音量"),
            R(en: "Reset Mix ▸ Clear all channel effects (w/o Room EQ)", zh: "清掉所有通道效果（可保留 Room EQ）"),
            R(en: "Reset Mix ▸ Reset channel names", zh: "恢复通道默认名"),
            R(en: "Reset Mix ▸ Set all channels mono / stereo", zh: "全部设成单声道 / 立体声", note: "会改变通道布局"),
            R(en: "Reset Mix ▸ Set inputs mono / outputs stereo", zh: "输入单声道、输出立体声"),
            R(en: "Reset Mix ▸ Total Reset (w/o Room EQ)", zh: "全部重置", note: "慎用"),
            R(en: "Operational Mode…", zh: "工作模式：Full（混音全开）/ DAW（回放直通、无输入混音）", note: "本 App 需要 Full 模式"),
            R(en: "Offline Device Setup…", zh: "设备没接时也能编辑它的配置"),
            R(en: "Network Remote Settings…", zh: "网络遥控（TotalMix Remote）设置"),
            R(en: "Always on Top", zh: "窗口总在最前"),
            R(en: "Prevent Sleep", zh: "运行时阻止 Mac 睡眠"),
            R(en: "Store current State into Device ▸ Setup 1–6", zh: "把当前状态存进设备（脱机时用）"),
        ]),
        GlossarySection(title: "Window 菜单", path: "菜单栏 Window", rows: [
            R(en: "Set Scale to ▸ 100% / 135% / 180% / 200%", zh: "界面缩放"),
            R(en: "Toggle Old-New Design", zh: "新旧两种界面外观切换"),
            R(en: "Hide Control Strip", zh: "隐藏右侧控制条"),
            R(en: "Minimize / Zoom / Fill / Center / Full Screen / 标签页相关", zh: "系统窗口操作"),
            R(en: "RME TotalMix FX: 设备 (序列号) - disconnected", zh: "当前窗口对应的设备与连接状态", app: .info),
        ]),
        GlossarySection(title: "Mixer Settings → General（混音）", path: "Options ▸ Mixer Settings…", rows: [
            R(en: "Talkback → Input", zh: "对讲话筒用哪一路输入", note: "默认 None", app: .info, appWhere: "指定后本 App 出现“对讲”"),
            R(en: "Talkback → Dim", zh: "对讲时耳机里其他声音降多少 dB"),
            R(en: "Listenback → Input", zh: "回听话筒（录音间里的话筒）用哪一路输入"),
            R(en: "Listenback → Dim", zh: "回听时主输出降多少 dB"),
            R(en: "Main Out → Recall", zh: "主输出的预设音量（按 Recall 回到这个音量）"),
            R(en: "Main Out → Dim", zh: "按 Dim 时主输出降多少 dB"),
            R(en: "Main Out → Ext. Input / Gain", zh: "外部输入用哪一对、音量多少", app: .info, appWhere: "指定后本 App 出现“外部输入”"),
            R(en: "Live Mode, PFL replaces Solo", zh: "Live 模式：Solo 按钮变成 PFL 预听"),
            R(en: "Exclusive Solo/PFL Mode", zh: "同时只能有一个 Solo / PFL"),
            R(en: "2-Row Mode with only Input in first row", zh: "两行模式：回放挪到下面和输出同一行"),
        ]),
        GlossarySection(title: "Mixer Settings → MIDI", path: "Options ▸ Mixer Settings… ▸ MIDI", rows: [
            R(en: "Select Controller / In Use", zh: "四套 MIDI 遥控设置选一套 / 启用这一套"),
            R(en: "MIDI In / MIDI Out", zh: "接收 / 发送遥控数据的 MIDI 端口"),
            R(en: "Disable MIDI in background", zh: "TotalMix 不在前台时停用 MIDI 遥控"),
            R(en: "Enable Protocol Support", zh: "启用 Mackie Control 协议（关掉只认普通 CC）"),
            R(en: "Extender to", zh: "这台遥控器当另一台的扩展"),
            R(en: "Map Stereo to 2 Mono Channels", zh: "一个推子只控一个单声道"),
            R(en: "Submix Selection in Input/Playback Row", zh: "在上两行也能选子混音"),
            R(en: "Full LC Display Support", zh: "Mackie 屏幕显示完整通道名和数值"),
            R(en: "Send user defined Names", zh: "把自定义通道名发给遥控器"),
            R(en: "Send Level Messages / Peak Hold", zh: "发送电平数据 / 峰值保持"),
        ]),
        GlossarySection(title: "Mixer Settings → OSC", path: "Options ▸ Mixer Settings… ▸ OSC", rows: [
            R(en: "Select Controller", zh: "四套 OSC 遥控设置选一套", app: .required, appWhere: "选一套空闲的给本 App"),
            R(en: "In Use", zh: "启用这一套", app: .required, appWhere: "勾上"),
            R(en: "TotalMix FX OSC Service → Host / Port (incoming)", zh: "TotalMix 接收端口", app: .required, appWhere: "填 7011（= 本 App“设置 → 连接”里的同名项）"),
            R(en: "Port (outgoing)", zh: "TotalMix 发送端口", app: .required, appWhere: "填 9011"),
            R(en: "Remote Controller Address", zh: "遥控方的地址", app: .required, appWhere: "填 127.0.0.1（开 Wi-Fi 收不到时试 ::1）"),
            R(en: "Send Level Data", zh: "发送电平数据", app: .required, appWhere: "想看电平就勾上"),
            R(en: "Peak Hold", zh: "电平峰值保持"),
            R(en: "Lock Remote to Submix", zh: "这个遥控只能改选定的一个子混音", note: "本 App 需要改全部，别勾"),
            R(en: "Number of faders per bank", zh: "每组推子数（8–48）", note: "Global OSC 下用不到"),
            R(en: "Compatibility (Mode) → TotalMix 1.90 / 1.96 / Global OSC", zh: "兼容模式", app: .required, appWhere: "选 Global OSC"),
            R(en: "Details", zh: "打开 Global OSC 详细设置（见下面）"),
        ]),
        GlossarySection(title: "Global OSC 详细设置", path: "Mixer Settings ▸ OSC ▸ Details", rows: [
            R(en: "Faders → Set all faders in group", zh: "改一个推子时同组的一起改"),
            R(en: "Faders → Send faders in linear scale", zh: "推子值用 0–1 线性值发（否则发 dB）", note: "本 App 两种都认"),
            R(en: "Send changes", zh: "有变化就发出来", app: .required, appWhere: "要开（本 App 靠它一秒内同步）"),
            R(en: "Send all data on start (enable)", zh: "启动时把全部数据发一遍"),
            R(en: "Send status", zh: "发送状态（连接、DSP 负载等）", app: .required, appWhere: "要开（状态胶囊靠它）"),
            R(en: "Receive to hidden channels", zh: "隐藏的通道也接收控制", note: "关着时 Channel Layout 里隐藏的通道本 App 改不了"),
            R(en: "Re-send received (use carefully!)", zh: "把收到的再发回去（可能来回打架）", note: "别开"),
            R(en: "Re-send if different", zh: "收到的值和实际不同时再发一次"),
            R(en: "Bandwidth Limitation 200k / 500k / none", zh: "发送带宽上限", note: "RME 建议从 500 kByte/s 起"),
        ]),
        GlossarySection(title: "Mixer Settings → Aux Devices", path: "Options ▸ Mixer Settings… ▸ Aux. Devices", rows: [
            R(en: "Device Type / Device 1 / Device 2", zh: "外接设备类型（目前只有 OctaMic XTC）"),
            R(en: "Channels (Bank) / Audio Channels (select first)", zh: "XTC 的 8 路进到哪几路输入"),
            R(en: "Device ID", zh: "XTC 的设备 ID（多台时各不相同）"),
            R(en: "MIDI In / MIDI Out", zh: "和 XTC 通信的 MIDI 端口"),
            R(en: "启用后", zh: "这些输入通道条上出现 48V、Inst/PAD、Gain、AutoSet，直接控制 XTC", note: "和本 App 改 XTC 二选一，不能同时控制", app: .info, appWhere: "“设置 → 连接”XTC 一节有说明"),
        ]),
        GlossarySection(title: "Preferences（偏好设置）", path: "TotalMix FX ▸ Settings…（F2）", rows: [
            R(en: "Level Meters → Full scale samples for OVR", zh: "连续几个满幅采样算过载（1–10）"),
            R(en: "Level Meters → Peak Hold time [s]", zh: "峰值保持时间（0.1–9.9 秒）"),
            R(en: "Level Meters → RMS +3dB", zh: "RMS 读数加 3 dB，和峰值在 0 dBFS 对齐"),
            R(en: "FX Send follows highest submix", zh: "送效果跟着这一路最高的那个推子走"),
            R(en: "FX Send follows Main Out mix", zh: "送效果只跟着主输出的推子走（现场常用）"),
            R(en: "Center Balance/Pan when changing Mono/Stereo", zh: "拆成单声道时声像放中间（否则一左一右）"),
            R(en: "Disable double click fader actions", zh: "禁用双击推子（防触控板误触）"),
            R(en: "Store channel open/cl. in Layout Preset", zh: "布局预设里记住各面板开 / 关"),
            R(en: "Dynamic Meters → Compressor/Expander / Include Gain setting / Auto Level", zh: "电平表里显示压缩、增益、自动电平的变化"),
            R(en: "Snapshots → Do not load: Main Volume / Main and Phones / Control Room", zh: "调用快照时不改这些（主音量 / 主输出和耳机 / 控制室）"),
            R(en: "Load Room EQs / Groups / Record/Play with Snapshot", zh: "调用快照时一起读 Room EQ / 编组 / 录放"),
            R(en: "Load old Workspaces in old Design", zh: "旧工作区用旧界面打开"),
            R(en: "Always init DSP devices with TotalMix FX setting", zh: "启动时用 TotalMix 的设置覆盖设备"),
            R(en: "Count MADI channels per port", zh: "MADI 通道号按每个口从 1 数（否则连续编号）", note: "影响 TotalMix 里的通道名；本 App 按位置对照，不受影响"),
            R(en: "Read back AUX devices on start", zh: "启动时读回外接设备（XTC）设置"),
            R(en: "Reduce volume peaks on snapshot load", zh: "调用快照时防止音量突跳"),
            R(en: "Graphics → Brightness correction / Normal / Light / High Contr.", zh: "界面亮度与对比度"),
            R(en: "Highlight submix frame", zh: "高亮当前子混音的框"),
            R(en: "Light Theme / Do not color channel names", zh: "浅色主题 / 通道名不着色"),
            R(en: "Lock User Interface", zh: "锁住界面防误操作"),
            R(en: "Store settings for all users", zh: "设置对这台电脑所有用户生效"),
        ]),
        GlossarySection(title: "Channel Layout（通道布局）", path: "Options ▸ Channel Layout…", rows: [
            R(en: "Inputs / Playbacks / Outputs", zh: "分三页：输入 / 回放 / 输出"),
            R(en: "Hide Channel in Mixer/Matrix", zh: "在调音台 / 矩阵里隐藏这个通道", note: "隐藏的通道 Global OSC 也收不到（除非开了 Receive to hidden channels）"),
            R(en: "MIDI Controller 1–4 / OSC Controller 1–4", zh: "对某一套遥控隐藏这个通道"),
            R(en: "Name (User)", zh: "自定义通道名"),
            R(en: "Layout Presets", zh: "布局预设（存 / 调用一套隐藏方案）", app: .planned),
        ]),
        GlossarySection(title: "其他窗口", path: "Options 菜单里", rows: [
            R(en: "Operational Mode → Full Mode", zh: "完整模式：混音全开，所有路由可用", note: "本 App 需要这个模式", app: .required, appWhere: "选 Full"),
            R(en: "Operational Mode → Digital Audio Workstation Mode", zh: "DAW 模式：回放直通、没有输入混音"),
            R(en: "Offline Device Setup → Configured / Available Devices / Serial Number", zh: "离线设备：已配置 / 可选设备、序列号"),
            R(en: "Network Remote → Enable TotalMix Remote Server", zh: "开网络遥控服务（给 iPad 等用）"),
            R(en: "Network Remote → Host Name / Port (in/out) / Label", zh: "主机名 / 端口 / 名称"),
            R(en: "Network Remote → Enable User Management / Password / Rights / Submix", zh: "用户管理：密码、权限、限定子混音"),
            R(en: "ARC & Key Commands → Remote Control Keys / Foot Switch / Key Function", zh: "ARC 遥控器按键、脚踏开关各对应什么功能"),
        ]),
    ]

    /// 搜索：英文、中文、说明里任一包含即算。
    public static func search(_ q: String) -> [GlossarySection] {
        let k = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !k.isEmpty else { return sections }
        return sections.compactMap { s in
            let rows = s.rows.filter { ($0.en + " " + $0.zh + " " + $0.note + " " + $0.appWhere).lowercased().contains(k) }
            return rows.isEmpty ? nil : GlossarySection(title: s.title, path: s.path, rows: rows)
        }
    }
}
