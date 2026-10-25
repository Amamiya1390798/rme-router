import Foundation
import Observation
import RMECore
import RMEAdapters

/// 电平（文档第 7.7 节）。单独的可观察对象：每 100 ms 更新时只让电平条重绘，不重绘整页。
@MainActor
@Observable
public final class MeterStore {
    /// 各通道最近的峰值（dB），地址用链路表示法。
    public private(set) var levels: [ChannelRef: Double] = [:]
    /// 最近一次电平有变化的时间。
    public private(set) var lastUpdate: Date?
    /// XT 是否在线（离线时一律“无信号”）。
    public var deviceLive = false
    /// 开始轮询的时间（用来判断“在线但一直收不到电平”）。
    public private(set) var pollingSince: Date?

    /// 慢变的“有信号”信息（文档第 6.4.3 节）：最多每秒更新一次，且只有内容变了才赋值。
    /// 大页面（设备页、通道条）只读这两个，电平每 100 ms 的变化不会让整页重画。
    public private(set) var active: Set<ChannelRef> = []
    public private(set) var live = false
    private var activeUpdatedAt: Date?

    public init() {}

    /// 2 秒内收到过电平，并且设备在线。
    public func receiving(now: Date = Date()) -> Bool {
        deviceLive && (lastUpdate.map { now.timeIntervalSince($0) < 2 } ?? false)
    }

    /// 某通道的电平；没有信号时为 nil（界面显示“无信号”，不显示 0）。
    public func level(_ ref: ChannelRef, now: Date = Date()) -> Double? {
        receiving(now: now) ? levels[ref] : nil
    }

    /// 在线、轮询超过 3 秒却从没收到电平：多半是 TotalMix 没勾 Send Level Data。
    public func likelyLevelSendingOff(now: Date = Date()) -> Bool {
        guard deviceLive, lastUpdate == nil, let since = pollingSince else { return false }
        return now.timeIntervalSince(since) > 3
    }

    func update(_ new: [ChannelRef: Double], now: Date = Date()) {
        if new != levels {
            levels = new
            lastUpdate = now
        }
        guard activeUpdatedAt.map({ now.timeIntervalSince($0) >= 1 }) ?? true else { return }
        activeUpdatedAt = now
        let isLive = receiving(now: now)
        let nowActive = isLive ? Set(levels.filter { $0.value > -60 }.keys) : []
        if nowActive != active { active = nowActive }
        if isLive != live { live = isLive }
    }

    func startPolling(now: Date = Date()) { if pollingSince == nil { pollingSince = now } }
    func stopPolling() { pollingSince = nil }
}

extension AppModel {
    /// 从 TotalMix 客户端取一次电平，映射成链路地址（对照表里没有的跳过）。
    public func pollMetersOnce() async {
        guard let adapter else { return }
        let raw = await adapter.client.state.levels
        var out: [ChannelRef: Double] = [:]
        for (ch, dB) in raw {
            if ch.bus == .playback { out[ChannelRef("xt.playback.in", ch.number)] = dB; continue }
            if let ref = xtMap[ch]?.ref { out[ref] = dB }
        }
        meters.deviceLive = xtStatus == .live
        meters.startPolling()
        meters.update(out)
        identifySample()
    }

    /// 持续轮询电平（每 100 ms）。App 启动读取成功后开始；读取失败时停止。
    public func startMeterLoop() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                await self?.pollMetersOnce()
                // 每秒一次：把 TotalMix 里的改动（立体声配对、名字、发送）同步过来
                if tick % 10 == 0 { await self?.syncFromTotalMix() }
                tick += 1
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    public func stopMeterLoop() {
        meterTask?.cancel()
        meterTask = nil
        meters.stopPolling()
    }
}
