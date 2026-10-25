import Foundation

/// 体检规则的中文说明与改法（体检视图用）。和规则放在一起，新增规则时同步补这里（有测试检查覆盖）。
public struct RuleInfo: Equatable, Sendable {
    public var id: String
    /// 短标题，例如“主时钟唯一”。
    public var title: String
    /// 这条规则查什么、为什么重要。
    public var explanation: String
    /// 有问题时怎么改。
    public var fix: String
    /// 无法判断时怎么确认（例如去哪个面板看）。
    public var howToCheck: String

    public init(id: String, title: String, explanation: String, fix: String, howToCheck: String) {
        self.id = id
        self.title = title
        self.explanation = explanation
        self.fix = fix
        self.howToCheck = howToCheck
    }
}

public enum RuleCatalog {
    public static func info(_ id: String) -> RuleInfo? { byID[id] }

    public static let all: [RuleInfo] = [
        RuleInfo(id: "R1", title: "主时钟唯一",
                 explanation: "整个系统只能有一台设备做时钟主机，其余设备跟随它。多个主机或没有主机，都会出现咔哒声、断续或无声。",
                 fix: "选定一台主机（通常是 MADIface XT 的内部时钟），其余设备的时钟源设为接收主机信号的那个 MADI 输入。",
                 howToCheck: "TotalMix 的 Global OSC 读不到时钟源：在 TotalMix 的 Settings → Clock Source 查看 XT；XTC 在面板 CLOCK 菜单查看。"),
        RuleInfo(id: "R2", title: "采样率一致",
                 explanation: "所有设备设置的采样率要相同。从机也要手动设对：在双速（S/MUX）下从机不会自动跟随，会锁定但按错误的速度解读。",
                 fix: "把各设备采样率设成同一个值（例如 48 kHz）：XT 在 TotalMix 的 Settings，12Mic 在 CLOCK 页，XTC 在面板 CLOCK 菜单。",
                 howToCheck: "TotalMix 的 Global OSC 读不到采样率：在 TotalMix 的 Settings 里查看 XT；XTC 在面板上查看。"),
        RuleInfo(id: "R3", title: "链路两端格式一致",
                 explanation: "一根 MADI 线两端的帧（48K/96K）、通道模式（56/64）和速度要一致。设备可能显示 Lock，却按错误的格式解读，表现为通道错位或无声。",
                 fix: "让发送端和接收端的 MADI 格式一致：12Mic 在 OUTPUT → MADI 设置 mode 与 framesize；XTC 在面板的 MADI 设置。",
                 howToCheck: "读不到一端的格式时，在两台设备的面板上分别查看 MADI 帧和通道模式。"),
        RuleInfo(id: "R4", title: "从机时钟源接了线",
                 explanation: "跟随外部时钟的设备，必须锁在一个确实接了线的输入上，否则它其实在“空等”时钟。",
                 fix: "把时钟源改成确实接了线的那个输入，或补上这根线并在连接表里登记。",
                 howToCheck: "在设备的时钟设置里查看当前时钟源。"),
        RuleInfo(id: "R5", title: "接收端 Lock 且 Sync",
                 explanation: "Lock 只表示收到了有效信号，Sync 才表示和当前时钟同步。Lock 但不 Sync 时会有咔哒声或断续。",
                 fix: "检查线缆；确认发送端采样率与本机一致、时钟源设置正确（见 R1、R2）。",
                 howToCheck: "在接收设备的面板或 TotalMix 的 SyncCheck 里查看该输入的 Lock/Sync 灯。"),
        RuleInfo(id: "R6", title: "MADI 收发成对",
                 explanation: "MADI 线是单向的。只接了一个方向，就只能单向传音频，反方向的设备也可能拿不到时钟。",
                 fix: "补上反方向那根线，并在连接表里登记。",
                 howToCheck: "对照实物检查两台设备之间是否有来回两根线。"),
        RuleInfo(id: "R7", title: "终端支持该采样率",
                 explanation: "P16-I 只支持 44.1 / 48 kHz。送过去的 ADAT 采样率超出范围时完全不会出声。",
                 fix: "把送往 P16 的那台设备（XTC）设回 44.1 或 48 kHz。",
                 howToCheck: "在发送端设备（XTC）面板上查看采样率。"),
        RuleInfo(id: "R8", title: "终端时钟口接了线",
                 explanation: "P16-I 只从 ADAT A 口取时钟。只接 ADAT B 时，即使通道路由都对也没有声音。",
                 fix: "把光纤接到 P16-I 的 ADAT A 口。",
                 howToCheck: "看 P16-I 的 ADAT 状态灯和通道信号灯是否亮。"),
        RuleInfo(id: "R9", title: "控制来源不冲突",
                 explanation: "有的设备只接受一个控制来源：XTC 的 MIDI Remote 与 TotalMix Aux Device 不能同时使用，否则设置会互相覆盖。",
                 fix: "关掉多余的遥控来源，只保留一个。",
                 howToCheck: "设备读不到时，看各遥控软件（TotalMix Aux Device、MIDI Remote、RME Connector）是否同时开着。"),
        RuleInfo(id: "R10", title: "设备在线",
                 explanation: "离线或读不到的设备，所有状态都按“未知”处理，其他检查也会因此“无法判断”。",
                 fix: "接上设备并打开远程控制（XT：TotalMix 打开 Global OSC；12Mic：STATE → remote → HTTP Remote），然后点“读取设备”。",
                 howToCheck: "在“连接”页检查地址与端口。"),
        RuleInfo(id: "R11", title: "Aux Device 通道对得上",
                 explanation: "12Mic 的 Mic 1 实际送到 XT 的哪个通道，要和 TotalMix 里 Aux Device 的起始通道一致，否则在 TotalMix 里调的增益会作用在错位的通道上。",
                 fix: "在 12Mic 路由里把 Mic 1 送到 Aux Device 期望的通道，或在 TotalMix 里改 Aux Device 的起始通道。",
                 howToCheck: "读不到 12Mic 路由时，在 12Mic 的 OUTPUT 路由页查看 Mic 1 送到哪个 MADI 通道。"),
        RuleInfo(id: "R12", title: "设备设置符合预期",
                 explanation: "检查你声明过的设备设置（首要是 XTC 的 ADAT 输出源）是否还是预期值。",
                 fix: "在设备面板上把该设置改回预期值（XTC 的 ADAT 输出源在 Digital Routing 菜单）。",
                 howToCheck: "XTC 的这项设置没有可读的协议，请在面板 Digital Routing 菜单里人工确认。"),
        RuleInfo(id: "R13", title: "输出没有被静音",
                 explanation: "路径再通，输出被静音也不会有声音。",
                 fix: "在 TotalMix 里取消该输出的静音。",
                 howToCheck: "在 TotalMix 里查看该输出通道的静音按钮。"),
        RuleInfo(id: "R14", title: "高速模式通道数",
                 explanation: "96 kHz（双速）时 MADI 每口最多 32 路、ADAT 4 路；192 kHz 再减半。超出的通道号会失效。",
                 fix: "不需要高采样率时改回 44.1 / 48 kHz；否则重新检查路由里的通道号。",
                 howToCheck: "确认各设备的采样率（见 R2）。"),
    ]

    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}
