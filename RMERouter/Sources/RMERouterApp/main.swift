import AppKit
import SwiftUI
import RMECore
import RMEEngine
import RMEApp

// swift run RMERouterApp                 打开窗口
// swift run RMERouterApp --render <目录>  从 TotalMix 只读读取一次，把各视图渲染成 PNG（浅色/深色）用于检查

if let i = CommandLine.arguments.firstIndex(of: "--render"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1], isDirectory: true)
    Task { @MainActor in
        await Renderer.renderAll(to: dir)
        exit(0)
    }
    RunLoop.main.run()
} else {
    RMERouterApp.main()
}

@MainActor
enum Renderer {
    static func renderAll(to dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "rme.render") ?? .standard
        // 设备组成跟本机设置一样（检查面板与线缆）
        if let c = UserDefaults.standard.data(forKey: StudioConfig.defaultsKey) ?? UserDefaults(suiteName: "local.rme.router")?.data(forKey: StudioConfig.defaultsKey) { defaults.set(c, forKey: StudioConfig.defaultsKey) }
        let model = AppModel(defaults: defaults)
        await model.refresh()
        print("XT 状态：\(model.xtStatus)")
        let trace = SignalTrace(snapshot: model.snapshot)
        let demo = ["12Mic", "OctaMic XTC"]

        for (name, appearance) in [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)] {
            render(OutputsContent(outputs: model.outputs, status: model.xtStatus, lastLoaded: model.lastLoaded,
                                  demoDevices: demo, showPlayback: .constant(false), columns: 3),
                   width: 1000, appearance: appearance, to: dir.appendingPathComponent("outputs-\(name).png"))
            render(RackRender.rear(model), width: 1300, appearance: appearance,
                   to: dir.appendingPathComponent("rack-rear-\(name).png"))
            for target in [ChannelRef("xt.mic.in", 1), ChannelRef("12mic.analog.in", 1)] {
                render(SignalFlowContent(target: target, deviceName: model.deviceName(of: target), trace: trace,
                                         deviceNameOf: model.deviceName(of:)),
                       width: 640, appearance: appearance,
                       to: dir.appendingPathComponent("flow-\(target.portID)-\(target.channel)-\(name).png"))
            }
        }
    }

    static func render<V: View>(_ view: V, width: CGFloat, appearance: NSAppearance, to url: URL) {
        appearance.performAsCurrentDrawingAppearance {
            let content = view
                .padding(24)
                .frame(width: width)
                .background(Tokens.Palette.bg)
                .environment(\.colorScheme, appearance.name == .darkAqua ? .dark : .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("渲染失败：\(url.lastPathComponent)")
                return
            }
            try? png.write(to: url)
            print("已写入 \(url.lastPathComponent)  \(Int(image.size.width))×\(Int(image.size.height))")
        }
    }
}
