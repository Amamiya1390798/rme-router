import Foundation
import RMECore
import RMEAdapters

// rme-probe：只读检查 TotalMix Global OSC（开发顺序第 3 步的完成标准：读回的发送表与 TotalMix 屏幕一致）。
// 只发请求类消息（/sendstate、/sendall 2.0），经 OSCSendGate 白名单；不发任何写入。
//
// 用法：swift run rme-probe --port <TotalMix 接收端口> --listen <TotalMix 发送端口> [--host 127.0.0.1]

func argument(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

guard let port = argument("--port").flatMap(Int.init), let listen = argument("--listen").flatMap(Int.init) else {
    print("""
    用法：swift run rme-probe --port <TotalMix 接收端口> --listen <TotalMix 发送端口> [--host 127.0.0.1]
    TotalMix 设置：Options 打开 OSC Control；Settings → OSC 选 Global OSC，关闭 Follow Submix；
    在 Details 里把远端 IP 设为本机、发送端口设为 --listen 的值。开 Wi-Fi 时若收不到，试 --host ::1。
    """)
    exit(2)
}
let host = argument("--host") ?? "127.0.0.1"

let adapter = TotalMixOSCAdapter(host: host, port: port, localPort: listen)
let path = await adapter.probe()
print("在线探测（/sendstate）：\(path.state == .online ? "收到状态回包" : "超时，无回包")")

do {
    guard try await adapter.client.refreshAll() else {
        print("/sendall 无回包。检查 TotalMix 的 OSC 设置与端口。")
        exit(1)
    }
} catch {
    print("请求失败：\(error)")
    exit(1)
}

let state = await adapter.client.state
let stats = await adapter.client.stats
let names = state.names
func label(_ ch: TotalMixChannel) -> String { names[ch].map { "\(ch)（\($0)）" } ?? "\(ch)" }

print("设备：\(state.deviceName ?? "未收到")；连接：\(state.connected.map { $0 ? "已连接" : "未连接" } ?? "未收到")")
if state.connected == false {
    print("⚠️ 设备未连接：以下是 TotalMix 保存的配置，不是设备的实时状态。")
}
print("状态原始值：" + state.status.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "，"))
print("收到 \(stats.packetsReceived) 个包、\(stats.messagesReceived) 条消息；解码失败 \(stats.decodeErrors)；未解析地址 \(state.unparsedCount)")

if CommandLine.arguments.contains("--names") {
    print("\n== 通道名与立体声（TotalMix 序号从 1 起）==")
    for bus in TotalMixBus.allCases {
        let chans = Set(state.channels.keys.filter { $0.bus == bus }).sorted()
        let items = chans.map { ch -> String in
            let st = state.isStereo(ch) == true ? "[st]" : ""
            return "\(ch.number)=\(names[ch] ?? "?")\(st)"
        }
        print("\(bus.rawValue)（\(chans.count)）：" + items.joined(separator: " "))
    }
}
print("\n== TotalMix 原始混音节点（> -65 dB，与 TotalMix 屏幕逐条对照）==")
let open = state.nodes.keys.compactMap { k in state.gainDB(k).map { (k, $0) } }
    .sorted { ($0.0.output, $0.0.source) < ($1.0.output, $1.0.source) }
for (k, dB) in open {
    print("  \(label(k.source)) → \(label(k.output))  \(String(format: "%.1f dB", dB))")
}
if open.isEmpty { print("  （无）") }

let snap = TotalMixOSCAdapter.makeSnapshot(deviceID: adapter.deviceID, state: state, map: adapter.channelMap,
                                           controlPath: path, observedAt: Date())
print("\n== 按链路表示法（硬件口来自通道名解析，为 inferred；回放按定义）==")
for r in snap.routes {
    print("  " + Hop.route(from: r.source, to: r.destination, domain: r.domain, kind: r.kind).description + "  [\(r.evidence.rawValue)]")
}
if snap.routes.isEmpty { print("  （无）") }
print("对照表缺项的节点：\(snap.settings["totalmix.unmappedNodes"]?.knownValue ?? "?")")
await adapter.client.stop()
exit(0)
