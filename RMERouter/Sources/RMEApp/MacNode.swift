import Foundation
import AppKit
import RMECore
import RMEAdapters

/// “这台 Mac”节点（文档第 6.6 节）：Core Audio 读到的 XT 连接、采样率、在用的程序。
extension AppModel {
    /// 读一次 Core Audio（很快，只读）。XT 的采样率并进 XT 快照的时钟。
    public func refreshAudio() {
        let info = audioSystem.device(nameContains: "MADIface XT")
        if info != xtAudio { xtAudio = info }
        audioChecked = true
        mergeAudioIntoXT()
    }

    /// 把 Core Audio 的采样率填进 XT 时钟（TotalMix 的 OSC 读不到这一项）。只有值变了才改快照。
    func mergeAudioIntoXT() {
        guard let rate = xtAudio?.sampleRate.map({ Int($0.rounded()) }), var xt = snapshot.devices["xt"],
              !(xt.clock.configuredRate.knownValue == rate && xt.clock.configuredRate.source.interface == "coreaudio") else { return }
        xt.clock.configuredRate = .confirmed(rate, FactSource(deviceID: "xt", interface: "coreaudio",
                                                              reference: "kAudioDevicePropertyNominalSampleRate", observedAt: Date()))
        var devices = snapshot.devices
        devices["xt"] = xt
        replaceDevices(devices)
    }

    /// 在用 XT 的程序，换成看得懂的名字（Logic Pro 等）。
    public var xtAudioClients: [(name: String, input: Bool, output: Bool)] {
        (xtAudio?.clients ?? []).map { c in
            let name = NSRunningApplication(processIdentifier: c.pid)?.localizedName ?? c.bundleID ?? "进程 \(c.pid)"
            return (name, c.input, c.output)
        }
        .sorted { $0.name < $1.name }
    }

    /// 改 XT 采样率（界面先弹确认框）。返回错误说明；nil 表示已核对。
    public func setXTSampleRate(_ rate: Double) async -> String? {
        guard let info = xtAudio else { return "没找到 XT" }
        do { try audioSystem.setSampleRate(rate, device: info.id) }
        catch AudioSystemError.notAllowed { return "XT 不支持 \(Self.rateText(rate))" }
        catch { return "改采样率失败：\(error)" }
        try? await Task.sleep(for: .milliseconds(500))
        refreshAudio()
        guard let now = xtAudio?.sampleRate else { return "改完读不到采样率" }
        return abs(now - rate) < 1 ? nil : "读回 \(Self.rateText(now))，不是 \(Self.rateText(rate))"
    }

    public static func rateText(_ r: Double) -> String {
        r.truncatingRemainder(dividingBy: 1000) == 0 ? "\(Int(r / 1000)) kHz" : String(format: "%.1f kHz", r / 1000)
    }
}
