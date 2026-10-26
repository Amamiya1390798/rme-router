import SwiftUI
import AppKit

/// 读不到 TotalMix 时的小窗：按 Mixer Settings → OSC 的顺序列出要改的项，并看一眼 TotalMix 实际在听哪些端口（只读）。
struct OSCHelpSheet: View {
    @Bindable var model: AppModel
    var close: () -> Void
    @State private var ports: [Int]? = nil
    @State private var checked = false
    @State private var retrying = false

    var body: some View {
        let s = model.settings
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack {
                Label("没读到 TotalMix", systemImage: "exclamationmark.triangle").font(Tokens.Font.cardTitle)
                Spacer()
                AnimeFace(mood: .sleepy)
            }
            Text(diagnosis(s)).font(Tokens.Font.body).fixedSize(horizontal: false, vertical: true)
            Text("在 TotalMix 里打开 Options ▸ Mixer Settings… ▸ OSC，按顺序改：").font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted)
            VStack(alignment: .leading, spacing: 6) {
                step(1, "Select Controller 选一套空闲的（1–4），勾上 In Use")
                step(2, "Port (incoming) 填 \(s.port)")
                step(3, "Remote Controller Address 的 Host 填 \(s.host)，Port (outgoing) 填 \(s.listenPort)")
                step(4, "Compatibility (Mode) 选 Global OSC（不是 TotalMix 1.90 / 1.96）")
                step(5, "想看电平就勾 Send Level Data；Lock Remote to Submix 别勾")
            }
            Text("OSC 设置按设备分开存：换了主卡、切了 TotalMix 的模拟设备，都要再配一次。端口要和“设置 → 连接”里的一致。")
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Palette.textMuted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("打开“设置 → 连接”") {
                    model.settingsTab = .connection
                    model.section = .settings
                    close()
                }
                Spacer()
                Button("关闭", action: close).keyboardShortcut(.cancelAction)
                Button(retrying ? "正在读取…" : "改好了，重新读取") {
                    retrying = true
                    Task {
                        await model.refresh()
                        retrying = false
                        if case .unreachable = model.xtStatus { await check() } else { close() }
                    }
                }
                .keyboardShortcut(.defaultAction).disabled(retrying)
            }
        }
        .padding(Tokens.Space.l)
        .frame(width: 480)
        .task { await check() }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(Tokens.Font.caption.weight(.semibold)).foregroundStyle(Tokens.Palette.textMuted).frame(width: 14)
            Text(text).font(Tokens.Font.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func check() async {
        ports = await Task.detached { TotalMixPorts.listening() }.value
        checked = true
    }

    private func diagnosis(_ s: OSCSettings) -> String {
        guard checked else { return "正在看 TotalMix 在听哪些端口…" }
        guard let ports else { return "没找到正在运行的 TotalMix FX：先打开它（要在后台一直开着）。" }
        let list = ports.map(String.init).joined(separator: "、")
        if ports.isEmpty { return "TotalMix 在运行，但没有打开任何 OSC 端口：OSC 那一套多半没勾 In Use。" }
        if !ports.contains(s.port) { return "TotalMix 现在在听 \(list)，本 App 发往 \(s.port)：端口对不上。" }
        return "TotalMix 在听 \(s.port)，端口对上了，但没有回话：多半是兼容模式不是 Global OSC，或 Remote Host / 发送端口（\(s.listenPort)）不对。"
    }
}

/// TotalMix FX 进程正在听的 UDP 端口（用系统自带的 lsof 只读查看）。TotalMix 没运行返回 nil。
enum TotalMixPorts {
    static func listening() -> [Int]? {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.executableURL?.lastPathComponent == "TotalmixFX" }) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-nP", "-a", "-c", "TotalmixFX", "-i", "UDP"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// 只取本机在听的端口（“*:7001”“127.0.0.1:7011”），不取连出去的（含 “->”）。
    static func parse(_ out: String) -> [Int] {
        let ports = out.split(separator: "\n").compactMap { line -> Int? in
            guard line.contains("UDP"), !line.contains("->"), let name = line.split(separator: " ").last,
                  let colon = name.lastIndex(of: ":") else { return nil }
            return Int(name[name.index(after: colon)...])
        }
        return Array(Set(ports)).sorted()
    }
}
