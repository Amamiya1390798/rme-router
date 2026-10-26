import Foundation

/// 切页卡顿测量（开发用）：环境变量 `RME_PERF=1` 启动时，自动轮流切换各页，
/// 记录每次切换后 1.5 秒内主线程最长没响应的时间，打印到标准错误并写进 `RME_PERF_OUT`（若给了路径）。
/// 后台线程每 5 ms 往主线程投一个空任务，看它多久才被执行：主线程在布局、渲染时就排不上。
@MainActor
public enum PerfProbe {
    public static var enabled: Bool { ProcessInfo.processInfo.environment["RME_PERF"] == "1" }

    public static func run(_ model: AppModel, rounds: Int = 3) {
        let watch = Watchdog()
        watch.start()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))   // 等首次读取完成
            while model.xtStatus == .loading || model.xtStatus == .notLoaded { try? await Task.sleep(for: .seconds(0.5)) }
            let strips = model.xtStrips(.input).count + model.xtStrips(.playback).count + model.xtStrips(.output).count
            // RME_PERF_FOCUS=1：先在设备页选中 XT MADI 1 输入、打开检查器（“点开不少东西”的情况）
            if ProcessInfo.processInfo.environment["RME_PERF_FOCUS"] == "1" {
                model.panelSelection = "xt.madi1.in"
                model.showInspector = true
                try? await Task.sleep(for: .seconds(1))
            }
            var lines: [String] = ["XT 状态 \(model.xtStatus)，通道条 \(strips) 条，面板\(UserDefaults.standard.object(forKey: "devices.rackOpen") as? Bool == false ? "收起" : "展开")"
                                   + (model.panelSelection.map { "，选中 \($0)" } ?? ""),
                                   "TotalMix 报的型号 \(model.mainTotalMixName ?? "无")，所选主卡 \(model.studioConfig.mainCard.title)，型号不符 \(model.mainCardMismatch)，Core Audio \(model.xtAudio?.name ?? "没找到")",
                                   "输入：" + model.xtStrips(.input).map(\.name).joined(separator: " "),
                                   "输出：" + model.xtStrips(.output).map(\.name).joined(separator: " "),
                                   "主卡话放：" + (model.snapshot.devices["xt"]?.preamps.map { "\($0.input) \($0.gainDB.knownValue.map { String($0) } ?? "?")" }.joined(separator: " ") ?? "无")]
            var worst: [AppSection: [Double]] = [:]
            for _ in 0 ..< rounds {
                for s in AppSection.allCases where s != model.section {
                    watch.reset()
                    model.section = s
                    try? await Task.sleep(for: .seconds(1.5))
                    worst[s, default: []].append(watch.maxMs)
                }
                // 回到设备页（最重的一页）也量一次
                watch.reset()
                model.section = .devices
                try? await Task.sleep(for: .seconds(1.5))
                worst[.devices, default: []].append(watch.maxMs)
            }
            // 设备页上点接口（选中 / 换一个 / 取消）
            model.section = .devices
            try? await Task.sleep(for: .seconds(1))
            var picks: [String] = []
            for id in ["xt.madi1.in", "xt.madi2.in", "xt.mic.1", nil] as [String?] {
                watch.reset()
                model.panelSelection = id
                try? await Task.sleep(for: .seconds(1.2))
                picks.append(String(format: "%@ %.0f", id ?? "取消", watch.maxMs))
            }
            lines.append("点接口：" + picks.joined(separator: " / ") + " ms")
            for s in AppSection.allCases {
                let v = worst[s] ?? []
                lines.append("切到 \(s.title)：最长卡顿 " + v.map { String(format: "%.0f", $0) }.joined(separator: " / ") + " ms")
            }
            let text = lines.joined(separator: "\n") + "\n"
            FileHandle.standardError.write(Data(text.utf8))
            if let out = ProcessInfo.processInfo.environment["RME_PERF_OUT"] {
                try? text.write(toFile: out, atomically: true, encoding: .utf8)
            }
            exit(0)
        }
    }
}

private final class Watchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var worst = 0.0

    var maxMs: Double { lock.lock(); defer { lock.unlock() }; return worst }
    func reset() { lock.lock(); worst = 0; lock.unlock() }

    func start() {
        Thread.detachNewThread { [self] in
            while true {
                let t = DispatchTime.now().uptimeNanoseconds
                let sem = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { sem.signal() }
                sem.wait()
                let ms = Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6
                lock.lock(); worst = max(worst, ms); lock.unlock()
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
    }
}
