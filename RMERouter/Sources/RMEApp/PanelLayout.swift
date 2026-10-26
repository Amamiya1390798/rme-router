import Foundation
import AppKit

/// 面板上一个实物接口（文档第 6.4 节）。位置按官方产品图目测，待用户核对。
public struct PanelConnector: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case audio     // 参与路由
        case clock     // 字时钟
        case computer  // 连电脑（USB / PCIe）
        case other     // 电源、网络、控制、MIDI
    }

    public var id: String
    public var name: String
    public var kind: Kind
    /// 中心位置：占图片宽、高的比例（0–1）。
    public var x: Double
    public var y: Double
    /// 热区直径：占图片宽度的比例。
    public var size: Double
    /// 这个接口承载的音频端口（D-sub 分线、SFP 等一个口有入有出）。
    public var ports: [String]
    /// 单通道接口（如 XLR 1）对应端口里的通道号。
    public var channel: Int?

    public var routes: Bool { kind == .audio && !ports.isEmpty }
}

public enum PanelFace: String, CaseIterable, Identifiable, Sendable {
    case rear, front
    public var id: String { rawValue }
    public var title: String { self == .rear ? "后面板" : "前面板" }
}

public struct DevicePanel: Sendable {
    public var deviceID: String
    public var face: PanelFace
    public var image: String
    /// 图片宽高比（宽 / 高）。
    public var aspect: Double
    public var connectors: [PanelConnector]
}

public enum PanelLayout {
    private static func c(_ id: String, _ name: String, _ kind: PanelConnector.Kind, _ x: Double, _ y: Double, _ size: Double,
                          _ ports: [String] = [], channel: Int? = nil) -> PanelConnector {
        PanelConnector(id: id, name: name, kind: kind, x: x / 100, y: y / 100, size: size / 100, ports: ports, channel: channel)
    }

    /// 当前设备组成下的全部面板（第 6.4.6 节）：主卡面板按型号，关掉的扩展设备不出现。
    public static var all: [DevicePanel] {
        let config = StudioConfig.current
        let main: [DevicePanel] = config.mainCard == .ufx3 ? ufx3 : config.mainCard == .madifaceXT ? base.filter { $0.deviceID == "xt" } : []
        return main + base.filter { $0.deviceID != "xt" && config.has($0.deviceID) }
    }

    /// Fireface UFX III（官方产品图，接口位置按图标注，对照手册 p.9–10；文档第 6.4.6 节）。
    static let ufx3: [DevicePanel] = [
        DevicePanel(deviceID: "xt", face: .rear, image: "fireface-ufx3-rear.png", aspect: 2000.0 / 205, connectors: [
            c("ufx.iec", "IEC 电源", .other, 9.5, 50, 6),
            c("ufx.midi1.out", "MIDI 1 输出", .other, 21.2, 55, 3.3),
            c("ufx.midi1.in", "MIDI 1 输入", .other, 25.6, 55, 3.3),
            c("ufx.usb", "USB 3.0（电脑）", .computer, 31.3, 62, 2.4),
            c("ufx.adat2.out", "ADAT 2 输出", .audio, 31.1, 28, 2.2, ["xt.adat2.out"]),
            c("ufx.adat2.in", "ADAT 2 输入", .audio, 33.9, 28, 2.2, ["xt.adat2.in"]),
            c("ufx.adat1.out", "ADAT 1 输出", .audio, 36.8, 28, 2.2, ["xt.adat1.out"]),
            c("ufx.adat1.in", "ADAT 1 输入", .audio, 39.7, 28, 2.2, ["xt.adat1.in"]),
            c("ufx.remote", "Remote（ARC USB）", .other, 37.9, 68, 2.4),
            c("ufx.madi.out", "MADI 输出（光）", .audio, 42.8, 26, 2.5, ["xt.madi.out"]),
            c("ufx.madi.in", "MADI 输入（光）", .audio, 45.5, 26, 2.5, ["xt.madi.in"]),
            c("ufx.wc.out", "Word / MADI 同轴输出（BNC）", .clock, 41.9, 61, 3.3),
            c("ufx.wc.in", "Word / MADI 同轴输入（BNC）", .clock, 45.5, 61, 3.3),
            c("ufx.aes.out", "AES/EBU 输出（XLR）", .audio, 51.3, 52, 4.5, ["xt.aes.out"]),
            c("ufx.aes.in", "AES/EBU 输入（XLR）", .audio, 56.7, 52, 4.5, ["xt.aes.in"]),
            c("ufx.out.1", "Line 输出 1（XLR）", .audio, 78.9, 50, 4.5, ["xt.an.out"], channel: 1),
            c("ufx.out.2", "Line 输出 2（XLR）", .audio, 73.5, 50, 4.5, ["xt.an.out"], channel: 2),
            c("ufx.out.3", "Line 输出 3（TRS）", .audio, 68.6, 28, 2.2, ["xt.an.out"], channel: 3),
            c("ufx.out.4", "Line 输出 4（TRS）", .audio, 68.6, 63, 2.2, ["xt.an.out"], channel: 4),
            c("ufx.out.5", "Line 输出 5（TRS）", .audio, 65.2, 28, 2.2, ["xt.an.out"], channel: 5),
            c("ufx.out.6", "Line 输出 6（TRS）", .audio, 65.2, 63, 2.2, ["xt.an.out"], channel: 6),
            c("ufx.out.7", "Line 输出 7（TRS）", .audio, 61.7, 28, 2.2, ["xt.an.out"], channel: 7),
            c("ufx.out.8", "Line 输出 8（TRS）", .audio, 61.7, 63, 2.2, ["xt.an.out"], channel: 8),
        ] + [(1, 94.1, 28), (2, 94.1, 62), (3, 90.6, 28), (4, 90.6, 62), (5, 87.1, 28), (6, 87.1, 62), (7, 83.7, 28), (8, 83.7, 62)].map { n, x, y in
            c("ufx.in.\(n)", "Line 输入 \(n)（TRS）", .audio, x, y, 2.2, ["xt.line.in"], channel: n)
        }),
        DevicePanel(deviceID: "xt", face: .front, image: "fireface-ufx3-front.png", aspect: 2000.0 / 198, connectors: [
            c("ufx.mic.9", "Mic/Line/Inst 9", .audio, 9.1, 50, 4.6, ["xt.mic.in"], channel: 1),
            c("ufx.mic.10", "Mic/Line/Inst 10", .audio, 17.2, 50, 4.6, ["xt.mic.in"], channel: 2),
            c("ufx.mic.11", "Mic/Line/Inst 11", .audio, 25.3, 50, 4.6, ["xt.mic.in"], channel: 3),
            c("ufx.mic.12", "Mic/Line/Inst 12", .audio, 33.3, 50, 4.6, ["xt.mic.in"], channel: 4),
            c("ufx.phones.1", "耳机 1（输出 9/10）", .audio, 40.3, 62, 2.4, ["xt.phones.out"], channel: 1),
            c("ufx.phones.2", "耳机 2（输出 11/12）", .audio, 40.3, 28, 2.4, ["xt.phones.out"], channel: 3),
            c("ufx.midi2.in", "MIDI 2 输入", .other, 44.7, 45, 3.3),
            c("ufx.midi2.out", "MIDI 2 输出", .other, 49.0, 45, 3.3),
            c("ufx.memory", "Memory（DURec U 盘）", .other, 54.0, 45, 2.4),
            c("ufx.power", "电源开关", .other, 91.0, 47, 3.5),
        ]),
    ]

    static let base: [DevicePanel] = [
        DevicePanel(deviceID: "xt", face: .rear, image: "madiface-xt-rear.png", aspect: 2000.0 / 426, connectors: [
            c("xt.dc", "DC 电源", .other, 5.9, 27.9, 4),
            c("xt.power", "电源开关", .other, 14, 27.9, 3),
            c("xt.dsub", "MIDI / AES 分线（AES 入 2 出 2、MIDI 入出）", .audio, 30.6, 27.9, 6, ["xt.aes.in", "xt.aes.out"]),
            c("xt.remote", "Remote（Mini-DIN）", .other, 43.6, 28.7, 4),
            c("xt.wck.out", "字时钟输出", .clock, 54.1, 25.8, 5),
            c("xt.wck.in", "字时钟输入", .clock, 63.8, 25.8, 5),
            c("xt.pcie", "PCI Express（电脑）", .computer, 9.7, 70.4, 6),
            c("xt.usb", "USB 3.0（电脑）", .computer, 20, 65.1, 4.5),
            c("xt.madi1.out", "MADI 1 输出（光）", .audio, 27.9, 66, 5, ["xt.madi1.out"]),
            c("xt.madi1.in", "MADI 1 输入（光）", .audio, 34.3, 66, 5, ["xt.madi1.in"]),
            c("xt.madi2.out", "MADI 2 输出（光）", .audio, 40.8, 66, 5, ["xt.madi2.out"]),
            c("xt.madi2.in", "MADI 2 输入（光）", .audio, 47, 66, 5, ["xt.madi2.in"]),
            c("xt.madi3.out", "MADI 3 输出（同轴）", .audio, 54.1, 60.1, 5, ["xt.madi3.out"]),
            c("xt.madi3.in", "MADI 3 输入（同轴）", .audio, 63.8, 60.1, 5, ["xt.madi3.in"]),
            c("xt.an.out.1", "模拟输出 1（XLR）", .audio, 75.3, 52.8, 7, ["xt.an.out"], channel: 1),
            c("xt.an.out.2", "模拟输出 2（XLR）", .audio, 90, 52.8, 7, ["xt.an.out"], channel: 2),
        ]),
        DevicePanel(deviceID: "xt", face: .front, image: "madiface-xt-front.png", aspect: 2000.0 / 430, connectors: [
            c("xt.mic.1", "Mic/Line 1", .audio, 13.1, 48, 7, ["xt.mic.in"], channel: 1),
            c("xt.mic.2", "Mic/Line 2", .audio, 30.1, 48, 7, ["xt.mic.in"], channel: 2),
            c("xt.phones", "耳机（TotalMix 输出 5/6）", .audio, 46.6, 62.5, 4.5, ["xt.phones.out"]),
        ]),
        DevicePanel(deviceID: "12mic", face: .rear, image: "12mic-rear.png", aspect: 2000.0 / 198, connectors: [
            c("12mic.net.sec", "NET (SEC) · AVB", .other, 12.6, 48, 4.5),
            c("12mic.net.pri", "NET (PRI) · AVB", .other, 18.4, 48, 4.5),
            c("12mic.usb", "USB 2.0", .other, 23, 65.7, 2.5),
            c("12mic.sfp", "MADI SFP 槽（LC，入 / 出）", .audio, 26.8, 65.7, 3, ["12mic.madi_optical.in", "12mic.madi_optical.out"]),
            c("12mic.coax.in", "MADI 同轴输入", .audio, 30.9, 65.7, 3, ["12mic.madi_coaxial.in"]),
            c("12mic.coax.out", "MADI 同轴输出", .audio, 34.6, 65.7, 3, ["12mic.madi_coaxial.out"]),
            c("12mic.wck.in", "字时钟输入", .clock, 38.7, 65.7, 3),
            c("12mic.wck.out", "字时钟输出", .clock, 42.4, 65.7, 3),
            c("12mic.adat3", "ADAT 输出 3", .audio, 46.3, 65.7, 2.5, ["12mic.adat3.out"]),
            c("12mic.adat2", "ADAT 输出 2", .audio, 49.6, 65.7, 2.5, ["12mic.adat2.out"]),
            c("12mic.adat1", "ADAT 输出 1", .audio, 52.9, 65.7, 2.5, ["12mic.adat1.out"]),
            c("12mic.dc", "12 V DC 电源", .other, 65.9, 65.7, 2.5),
            c("12mic.iec", "IEC 电源与开关", .other, 87.5, 43, 6),
        ]),
        DevicePanel(deviceID: "12mic", face: .front, image: "12mic-front.png", aspect: 2000.0 / 198,
                    connectors: (1 ... 12).map { n in
                        c("12mic.mic.\(n)", "Mic/Line \(n)" + (n <= 4 ? "（可接乐器 Hi-Z）" : ""), .audio,
                          (160 + Double(n - 1) * 90.8 - 15) / 15.7, 50, 4.2, ["12mic.analog.in"], channel: n)
                    } + [c("12mic.phones", "耳机", .audio, 77.7, 63, 2.5, ["12mic.phones.out"])]),
        DevicePanel(deviceID: "xtc", face: .rear, image: "octamic-xtc-rear.png", aspect: 2000.0 / 194, connectors: [
            c("xtc.iec", "IEC 电源", .other, 10.3, 48, 5),
            c("xtc.midi.out", "MIDI 输出", .other, 18.1, 58, 3.5),
            c("xtc.midi.in", "MIDI 输入", .other, 22.6, 58, 3.5),
            c("xtc.madi.out", "MADI 输出（光）", .audio, 28, 29, 2.8, ["xtc.madi.out"]),
            c("xtc.madi.in", "MADI 输入（光）", .audio, 30.6, 29, 2.8, ["xtc.madi.in"]),
            c("xtc.usb", "USB 2.0", .other, 27.4, 64.5, 2.5),
            c("xtc.aes", "AES/EBU D-sub 25（4 入 4 出）", .audio, 35.5, 64.5, 6, ["xtc.aes.in", "xtc.aes.out"]),
            c("xtc.wck.out", "字时钟输出", .clock, 37.4, 25.8, 3),
            c("xtc.wck.in", "字时钟输入", .clock, 41.4, 25.8, 3),
            c("xtc.adat.in", "ADAT 输入", .audio, 46.6, 29, 2.5, ["xtc.adat.in"]),
            c("xtc.adat2.out", "ADAT 输出 2", .audio, 43.1, 64.5, 2.5, ["xtc.adat2.out"]),
            c("xtc.adat1.out", "ADAT 输出 1", .audio, 46.6, 64.5, 2.5, ["xtc.adat1.out"]),
        ] + (1 ... 8).map { n in
            c("xtc.mic.\(n)", "Mic/Line \(n)" + (n >= 5 ? "（TS 为乐器输入）" : "（1–4 有 PAD）"), .audio,
              (830 + Double(8 - n) * 92.6) / 16, 48, 4.2, ["xtc.mic.in"], channel: n)
        }),
        DevicePanel(deviceID: "xtc", face: .front, image: "octamic-xtc-front.png", aspect: 2000.0 / 182, connectors: [
            c("xtc.phones.1", "耳机 1", .audio, 55, 27.4, 2.5, ["xtc.phones.out"], channel: 1),
            c("xtc.phones.2", "耳机 2", .audio, 55, 65, 2.5, ["xtc.phones.out"], channel: 3),
        ]),
    ]

    public static func panel(_ deviceID: String, _ face: PanelFace) -> DevicePanel? {
        all.first { $0.deviceID == deviceID && $0.face == face }
    }

    /// 承载某个端口的接口（找线缆两端画在哪）：先找后面板，整口优先于单通道口。
    public static func connector(for portID: String) -> (DevicePanel, PanelConnector)? {
        for face in [PanelFace.rear, .front] {
            for p in all where p.face == face {
                let matches = p.connectors.filter { $0.ports.contains(portID) }
                if let c = matches.first(where: { $0.channel == nil }) ?? matches.first { return (p, c) }
            }
        }
        return nil
    }

    // MARK: 图片

    /// 面板图所在目录：.app 里的 Resources/Panels；`swift run` 与测试时用仓库里的 Resources/Panels。
    static let directory: URL? = {
        let fm = FileManager.default
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Panels"), fm.fileExists(atPath: r.path) { return r }
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 3 { u.deleteLastPathComponent() }   // Sources/RMEApp/PanelLayout.swift → 包根目录
        let repo = u.appendingPathComponent("Resources/Panels")
        return fm.fileExists(atPath: repo.path) ? repo : nil
    }()

    @MainActor static var cache: [String: NSImage] = [:]

    @MainActor public static func image(_ name: String) -> NSImage? {
        if let i = cache[name] { return i }
        guard let url = directory?.appendingPathComponent(name), let i = NSImage(contentsOf: url) else { return nil }
        cache[name] = i
        return i
    }
}
