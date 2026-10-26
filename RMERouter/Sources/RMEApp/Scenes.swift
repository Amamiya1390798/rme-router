import Foundation
import RMECore
import RMEAdapters

/// 场景（文档第 7.6 节）：一次保存整套可写的状态，之后对比、恢复。地址一律用链路表示法。
public struct StudioScene: Codable, Identifiable, Equatable, Sendable {
    public struct Send: Codable, Hashable, Sendable {
        public var source: ChannelRef
        public var destination: ChannelRef
        public var dB: Double
    }

    public struct Preamp: Codable, Hashable, Sendable {
        public var device: String
        public var input: ChannelRef
        public var gain: Double?
        public var phantom: Bool?
        public var phase: Bool?

        func value(_ f: PreampField) -> PreampValue? {
            switch f {
            case .gain: return gain.map(PreampValue.gain)
            case .phantom: return phantom.map(PreampValue.flag)
            case .phase: return phase.map(PreampValue.flag)
            case .mute, .autoSet, .padInst: return nil   // 场景暂不存（文档第 6.3 节）
            }
        }
    }

    public struct RouteEntry: Codable, Hashable, Sendable {
        public var destination: ChannelRef
        public var source: ChannelRef?
    }

    /// XTC 一个 8 路输出块的来源（第 7.6 节）。
    public struct XTCBlock: Codable, Hashable, Sendable {
        /// 输出块首通道，例如 xtc.madi.out:25。
        public var destination: ChannelRef
        /// 来源块首通道；来源没有登记端口（ADAT IN、AES IN、电脑回放）时为 nil。
        public var source: ChannelRef?
        /// 值表 2 的名字，例如“MADI 17–24”。
        public var sourceLabel: String
    }

    /// 一条 XT 通道条的一个参数（第 7.6 节）：TotalMix 原值；立体声配对 1 / 0。
    public struct Strip: Codable, Hashable, Sendable {
        public var ref: ChannelRef
        public var param: TotalMixStripParam
        public var value: Double
    }

    public var id: UUID
    public var name: String
    public var date: Date
    /// 保存时读到真实数据的设备（"xt"、"12mic"、"xtc"）。
    public var devices: [String]
    public var sends: [Send]
    public var preamps: [Preamp]
    public var routes: [RouteEntry]
    /// 旧场景文件没有这一项（nil）。
    public var xtcRoutes: [XTCBlock]? = nil
    /// 旧场景文件没有这一项（nil）。
    public var strips: [Strip]? = nil

    public var summary: String {
        var parts: [String] = []
        if devices.contains("xt") { parts.append("TotalMix 发送 \(sends.count) 条") }
        if let strips, !strips.isEmpty { parts.append("通道条 \(Set(strips.map(\.ref)).count) 条") }
        if !preamps.isEmpty { parts.append("前级 \(preamps.count) 路") }
        if devices.contains("12mic") { parts.append("12Mic 路由 \(routes.count) 条") }
        if devices.contains("xtc") { parts.append("XTC 路由 \(xtcRoutes?.count ?? 0) 块") }
        return parts.isEmpty ? "空场景" : parts.joined(separator: "、")
    }
}

/// 场景与当前状态的一处差异。
public struct SceneDiff: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case send(source: ChannelRef, destination: ChannelRef, scene: Double?, now: Double?)
        case preamp(device: String, input: ChannelRef, field: PreampField, scene: PreampValue, now: PreampValue?)
        case route(destination: ChannelRef, scene: ChannelRef?, now: ChannelRef?)
        case xtcRoute(scene: StudioScene.XTCBlock, now: String?)
        case strip(ref: ChannelRef, param: TotalMixStripParam, scene: Double, now: Double?)
    }

    public var kind: Kind
    public var id: String {
        switch kind {
        case let .send(s, d, _, _): return "send|\(s)|\(d)"
        case let .preamp(dev, i, f, _, _): return "pre|\(dev)|\(i)|\(f.rawValue)"
        case let .route(d, _, _): return "route|\(d)"
        case let .xtcRoute(b, _): return "xtc|\(b.destination)"
        case let .strip(r, p, _, _): return "strip|\(r)|\(p.rawValue)"
        }
    }

    public var text: String {
        switch kind {
        case let .send(s, d, scene, now):
            return "TotalMix 发送 \(s) → \(d)：现在 \(PendingChange.format(now))，场景 \(PendingChange.format(scene))"
        case let .preamp(dev, i, f, scene, now):
            return "\(Self.deviceLabel(dev)) 前级 \(i) \(f.label)：现在 \(now?.text ?? "?")，场景 \(scene.text)"
        case let .route(d, scene, now):
            return "12Mic 路由 \(d)：现在 \(PendingRouteChange.text(now))，场景 \(PendingRouteChange.text(scene))"
        case let .xtcRoute(b, now):
            return "XTC 路由 \(b.destination.portID):\(b.destination.channel)–\(b.destination.channel + 7)：现在 \(now ?? "?")，场景 \(b.sourceLabel)"
        case let .strip(r, p, scene, now):
            return "通道条 \(r) \(p.label)：现在 \(Self.stripText(p, now))，场景 \(Self.stripText(p, scene))"
        }
    }

    static func stripText(_ p: TotalMixStripParam, _ v: Double?) -> String {
        guard let v else { return "?" }
        return p == .stereo ? (v >= 0.5 ? "立体声" : "单声道") : p.text(v)
    }

    static func deviceLabel(_ dev: String) -> String {
        switch dev { case "xt": return "\(mainName)"; case "xtc": return "XTC"; default: return "12Mic" }
    }
}

/// 场景文件的存取：一个场景一个 JSON 文件。
public struct SceneStore: Sendable {
    public var directory: URL?

    public init(directory: URL?) { self.directory = directory }

    public static var standard: SceneStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return SceneStore(directory: base?.appendingPathComponent("RME Router/scenes", isDirectory: true))
    }

    public static let none = SceneStore(directory: nil)

    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }()

    public func load() -> [StudioScene] {
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(StudioScene.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    public func save(_ scene: StudioScene) {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Self.encoder.encode(scene).write(to: directory.appendingPathComponent("\(scene.id).json"), options: .atomic)
    }

    public func delete(_ id: UUID) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).json"))
    }
}

extension AppModel {
    // MARK: 当前状态

    /// 能存进场景的设备：XT 已从 TotalMix 读到；12Mic 实时在线。
    public var sceneDevices: [String] {
        var d: [String] = []
        if lastLoaded != nil, xtStatus == .live || xtStatus == .offlineSaved { d.append("xt") }
        if twelveMicStatus == .live { d.append("12mic") }
        if xtcStatus == .live, !isDemo("xtc") { d.append("xtc") }
        return d
    }

    /// 当前打开的 TotalMix 发送（取 TotalMix 原始节点，左声道地址；对照表缺项的跳过）。
    func currentSends() -> [StudioScene.Send] {
        tmState.nodes.keys.compactMap { key -> StudioScene.Send? in
            guard let dB = tmState.gainDB(key), let s = xtMap[key.source]?.ref, let d = xtMap[key.output]?.ref else { return nil }
            return StudioScene.Send(source: s, destination: d, dB: dB)
        }
        .sorted { ($0.destination, $0.source) < ($1.destination, $1.source) }
    }

    func currentPreamps(_ devices: [String]) -> [StudioScene.Preamp] {
        devices.flatMap { dev in
            (snapshot.devices[dev]?.preamps ?? []).map {
                StudioScene.Preamp(device: dev, input: $0.input, gain: $0.gainDB.knownValue, phantom: $0.phantom.knownValue,
                             phase: $0.phase.knownValue)
            }
        }
    }

    func currentTwelveMicRoutes() -> [StudioScene.RouteEntry] {
        (snapshot.devices["12mic"]?.routes ?? []).map { StudioScene.RouteEntry(destination: $0.destination, source: $0.source) }
            .sorted { $0.destination < $1.destination }
    }

    /// XTC 各输出块当前的来源（读回的设置），按块顺序。
    func currentXTCRoutes() -> [StudioScene.XTCBlock] {
        guard let settings = snapshot.devices["xtc"]?.settings else { return [] }
        return XTCRoutingOutput.all.compactMap { out in
            let port = out.port(), first = out.firstChannel
            guard let label = settings["\(port).\(first)-\(first + 7).source"]?.knownValue else { return nil }
            let dst = ChannelRef(port, first)
            return StudioScene.XTCBlock(destination: dst, source: xtcSource(ofBlock: dst), sourceLabel: label)
        }
    }

    /// 当前每条通道条的静音、相位（输出另有音量、平衡），奇数号通道的立体声配对（第 7.6 节）。
    func currentStrips() -> [StudioScene.Strip] {
        var out: [StudioScene.Strip] = []
        for bus in [TotalMixBus.input, .playback, .output] {
            for s in xtStrips(bus) {
                guard let ref = s.ref else { continue }
                for p in [TotalMixStripParam.mute, .phase, .volume, .balpan, .loopback, .fxsend, .fxreturn, .width, .msproc, .autoset, .talkbacksel]
                    + TotalMixStripParam.allCases.filter { $0.isEQ && $0.isWritable } where p.applies(to: bus) {
                    if let v = stripValue(ref, p) { out.append(.init(ref: ref, param: p, value: v)) }
                }
                if s.tm.number % 2 == 1, let st = tmState.isStereo(s.tm) {
                    out.append(.init(ref: ref, param: .stereo, value: st ? 1 : 0))
                }
            }
        }
        return out.sorted { ($0.ref, $0.param.rawValue) < ($1.ref, $1.param.rawValue) }
    }

    // MARK: 保存、删除

    /// 把当前读到的真实状态存成场景。没有任何设备可存时返回 nil。
    @discardableResult
    public func saveScene(named name: String) -> StudioScene? {
        let devices = sceneDevices
        guard !devices.isEmpty else { return nil }
        let scene = StudioScene(id: UUID(), name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "未命名场景" : name,
                          // 取整到秒：与存盘的 ISO 8601 时间一致，内存里的场景与文件读回的完全相同。
                          date: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)), devices: devices,
                          sends: devices.contains("xt") ? currentSends() : [],
                          preamps: currentPreamps(devices),
                          routes: devices.contains("12mic") ? currentTwelveMicRoutes() : [],
                          xtcRoutes: devices.contains("xtc") ? currentXTCRoutes() : nil,
                          strips: devices.contains("xt") ? currentStrips() : nil)
        sceneStore.save(scene)
        scenes.insert(scene, at: 0)
        return scene
    }

    public func deleteScene(_ id: UUID) {
        sceneStore.delete(id)
        scenes.removeAll { $0.id == id }
    }

    // MARK: 对比、恢复

    /// 场景与当前的差异；只比较现在可读、且场景里存过的设备。
    public func diff(_ scene: StudioScene) -> [SceneDiff] {
        let now = sceneDevices
        var out: [SceneDiff] = []
        if scene.devices.contains("xt"), now.contains("xt") {
            let a = Dictionary(uniqueKeysWithValues: scene.sends.map { ("\($0.source)|\($0.destination)", $0) })
            let b = Dictionary(uniqueKeysWithValues: currentSends().map { ("\($0.source)|\($0.destination)", $0) })
            for key in Set(a.keys).union(b.keys).sorted() {
                let s = a[key], c = b[key]
                if let s, let c, abs(s.dB - c.dB) < 0.05 { continue }
                let ref = s ?? c!
                out.append(SceneDiff(kind: .send(source: ref.source, destination: ref.destination, scene: s?.dB, now: c?.dB)))
            }
        }
        if scene.devices.contains("xt"), now.contains("xt"), let saved = scene.strips {
            let current = Dictionary(currentStrips().map { ("\($0.ref)|\($0.param.rawValue)", $0.value) }, uniquingKeysWith: { a, _ in a })
            for st in saved {
                let have = current["\(st.ref)|\(st.param.rawValue)"]
                if let have, abs(have - st.value) < 0.05 { continue }
                // 场景里是立体声右声道的条，现在没有了（被合并）：配对差异里已经体现，不重复列
                if have == nil, st.param != .stereo, tmChannel(for: st.ref) == nil { continue }
                out.append(SceneDiff(kind: .strip(ref: st.ref, param: st.param, scene: st.value, now: have)))
            }
        }
        for p in scene.preamps where now.contains(p.device) {
            let cur = snapshot.devices[p.device]?.preamps.first { $0.input == p.input }
            for f in PreampField.allCases {
                guard let want = p.value(f) else { continue }
                let have = cur?.value(f)
                if Self.same(have, want) { continue }
                out.append(SceneDiff(kind: .preamp(device: p.device, input: p.input, field: f, scene: want, now: have)))
            }
        }
        if scene.devices.contains("12mic"), now.contains("12mic") {
            let a = Dictionary(uniqueKeysWithValues: scene.routes.map { ($0.destination, $0.source) })
            let b = Dictionary(uniqueKeysWithValues: currentTwelveMicRoutes().map { ($0.destination, $0.source) })
            for d in Set(a.keys).union(b.keys).sorted() {
                let s = a[d] ?? nil, c = b[d] ?? nil
                if s == c { continue }
                out.append(SceneDiff(kind: .route(destination: d, scene: s, now: c)))
            }
        }
        if scene.devices.contains("xtc"), now.contains("xtc"), let saved = scene.xtcRoutes {
            let current = Dictionary(uniqueKeysWithValues: currentXTCRoutes().map { ($0.destination, $0.sourceLabel) })
            for b in saved where current[b.destination] != b.sourceLabel {
                out.append(SceneDiff(kind: .xtcRoute(scene: b, now: current[b.destination])))
            }
        }
        return out
    }

    /// 恢复场景：差异做成待应用改动，并打开确认框（不论确认方式，第 7.6 节）。返回出错说明。
    @discardableResult
    public func restore(_ scene: StudioScene) -> [String] {
        var errors: [String] = []
        var diffs = diff(scene)
        // 立体声配对先恢复：它改变通道布局，其余项按旧布局算会错（第 7.6 节）
        let pairs = diffs.filter { if case let .strip(_, p, _, _) = $0.kind { return p == .stereo } else { return false } }
        if !pairs.isEmpty, pairs.count < diffs.count {
            diffs = pairs
            errors.append("这次先恢复立体声配对（\(pairs.count) 处）；确认发送后再点一次“恢复…”恢复其余项。")
        }
        for d in diffs {
            let e: StageError?
            switch d.kind {
            case let .send(s, dst, sceneDB, _): e = stageGain(source: s, destination: dst, dB: sceneDB)
            case let .preamp(dev, i, f, want, _): e = stagePreamp(deviceID: dev, input: i, field: f, value: want)
            case let .route(dst, src, _): e = stageTwelveMicRoute(destination: dst, source: src)
            case let .xtcRoute(b, _):
                guard let src = b.source else {
                    errors.append("\(d.text)：来源“\(b.sourceLabel)”本 App 不能设置，需在 XTC 面板上设置")
                    continue
                }
                e = stageXTCRoute(destination: b.destination, source: src)
            case let .strip(r, p, want, _): e = stageStrip(r, p, want)
            }
            if let e { errors.append("\(d.text)：\(e.text)") }
        }
        if hasPending { showConfirm = true }
        return errors
    }
}
