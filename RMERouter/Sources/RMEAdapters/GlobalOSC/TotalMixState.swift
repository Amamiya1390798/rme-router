import Foundation
import RMECore

/// TotalMix 通道 ↔ `xt.<接口>.<方向>:<通道>` 的对照表（文档第 7 节安全规则 7）。
/// 来源（文档第 7 节规则 7，2026-10-26 改）：用户确认 > 按 XT 固定的通道顺序（位置）> 硬件默认名。
/// 名字可以被改成任何东西（实测有 TotalMix 把 MADI 命名为连续数字），所以名字只用来核对位置。
/// 回放按定义映射：TotalMix 回放 n 就是电脑回放第 n 路，即 `<设备>.playback.in:n`。
public struct TotalMixChannelMap: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public var ref: ChannelRef
        public var evidence: Evidence
    }

    public var deviceID: String
    public private(set) var entries: [TotalMixChannel: Entry] = [:]

    public init(deviceID: String = "xt", confirmed: [TotalMixChannel: ChannelRef] = [:]) {
        self.deviceID = deviceID
        for (ch, ref) in confirmed { entries[ch] = Entry(ref: ref, evidence: .confirmed) }
    }

    public subscript(_ ch: TotalMixChannel) -> Entry? {
        if let e = entries[ch] { return e }
        if ch.bus == .playback { return Entry(ref: ChannelRef("\(deviceID).playback.in", ch.number), evidence: .confirmed) }
        return nil
    }

    public mutating func confirm(_ ch: TotalMixChannel, _ ref: ChannelRef) {
        entries[ch] = Entry(ref: ref, evidence: .confirmed)
    }

    /// 用 TotalMix 回读的状态补全未确认的条目（结果为 inferred，不覆盖已确认条目）：
    /// 1. 按名字解析硬件默认名（见 `parseHardwareName`）；输出被控制室改名（如 “Main”、“Phones 1”）
    ///    解析不出时，用同号回放的名字——回放 n 与输出 n 是同一个硬件口，回放名保持默认。
    /// 2. 立体声对的右声道 TotalMix 不发名字：左声道为 `:c` 时右声道记为 `:c+1`。
    public mutating func infer(from state: TotalMixState) {
        let names = state.names
        var byName: [TotalMixChannel: ChannelRef] = [:]
        for (ch, name) in names where ch.bus != .playback {
            let fallback = ch.bus == .output ? names[TotalMixChannel(.playback, ch.number)] : nil
            guard let ref = Self.parseHardwareName(name, bus: ch.bus, deviceID: deviceID)
                ?? fallback.flatMap({ Self.parseHardwareName($0, bus: ch.bus, deviceID: deviceID) }) else { continue }
            byName[ch] = ref
        }
        for (ch, ref) in byName where state.isStereo(ch) == true {
            let right = TotalMixChannel(ch.bus, ch.number + 1)
            if byName[right] == nil { byName[right] = ChannelRef(ref.portID, ref.channel + 1) }
        }
        var inferred: [TotalMixChannel: Entry] = [:]
        for bus in [TotalMixBus.input, .output] {
            let maxNumber = state.channels.keys.filter { $0.bus == bus }.map(\.number).max() ?? 0
            guard let layout = Self.layout(bus: bus, maxNumber: maxNumber, deviceID: deviceID) else { continue }
            for (n, ref) in layout.enumerated() {
                let ch = TotalMixChannel(bus, n + 1)
                // 名字能解析：一致记 confirmed，矛盾记 conflict（仍按位置）；解析不出只按位置
                let evidence: Evidence = byName[ch].map { $0 == ref ? .confirmed : .conflict } ?? .inferred
                inferred[ch] = Entry(ref: ref, evidence: evidence)
            }
        }
        for (ch, ref) in byName where inferred[ch] == nil { inferred[ch] = Entry(ref: ref, evidence: .inferred) }
        for (ch, e) in inferred where entries[ch]?.evidence != .confirmed || e.evidence == .conflict {
            entries[ch] = e
        }
    }

    /// XT 的 TotalMix 通道顺序（硬件决定）：每个序号对应的接口通道。MADI 每口路数按最大序号推出，
    /// 只接受 64 / 32 / 16（单速 / 双速 / 四速）；推不出时返回 nil。
    public static func layout(bus: TotalMixBus, maxNumber: Int, deviceID: String = "xt") -> [ChannelRef]? {
        let fixed: [(String, Int)]
        let dir: String
        switch bus {
        case .input: fixed = [("mic", 2), ("aes", 2)]; dir = "in"
        case .output: fixed = [("an", 2), ("aes", 2), ("phones", 2)]; dir = "out"
        case .playback: return nil
        }
        let head = fixed.reduce(0) { $0 + $1.1 }
        guard maxNumber > head, (maxNumber - head) % 3 == 0 else { return nil }
        let perPort = (maxNumber - head) / 3
        guard [64, 32, 16].contains(perPort) else { return nil }
        var out: [ChannelRef] = []
        for (iface, n) in fixed { out += (1 ... n).map { ChannelRef("\(deviceID).\(iface).\(dir)", $0) } }
        for k in 1 ... 3 { out += (1 ... perPort).map { ChannelRef("\(deviceID).madi\(k).\(dir)", $0) } }
        return out
    }

    /// 只认 XT 的硬件默认名（2026-10-25 从 TotalMix 读回，见文档第 7 节规则 7）：
    /// `M<k>-<n>`、`M<k>-<n>/<n+1>` → madi<k>；`Mic <n>` → mic.in；`AES` → aes；`AN <n>`、`AN <n>/<n+1>` → an.out；`PH` → phones.out。
    /// 控制室名 “Main”、“Phones 1” 不解析（它们随控制室设置变化）。
    static func parseHardwareName(_ name: String, bus: TotalMixBus, deviceID: String) -> ChannelRef? {
        let direction: String
        switch bus {
        case .input: direction = "in"
        case .output: direction = "out"
        case .playback: return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // 立体声名只取左声道号：“M1-13/14” → “M1-13”，“AN 1/2” → “AN 1”
        let left = String(trimmed.split(separator: "/").first ?? "")
        func port(_ iface: String) -> String { "\(deviceID).\(iface).\(direction)" }

        if left.hasPrefix("M"), !left.hasPrefix("Mic") {
            let parts = left.dropFirst().split(separator: "-")
            guard parts.count == 2, let k = Int(parts[0]), let n = Int(parts[1]), k >= 1, n >= 1 else { return nil }
            return ChannelRef(port("madi\(k)"), n)
        }
        if left == "AES" { return ChannelRef(port("aes"), 1) }
        let words = left.split(separator: " ")
        if words.count == 2, let n = Int(words[1]), n >= 1 {
            switch (words[0], bus) {
            case ("Mic", .input): return ChannelRef(port("mic"), n)
            case ("AN", .output): return ChannelRef(port("an"), n)
            default: return nil
            }
        }
        if left == "PH", bus == .output { return ChannelRef(port("phones"), 1) }
        return nil
    }
}

/// 从 Global OSC 收到的 TotalMix 状态（只增量更新，不推断）。
public struct TotalMixState: Sendable, Equatable {
    public struct NodeKey: Hashable, Sendable {
        public var source: TotalMixChannel
        public var output: TotalMixChannel
        public init(source: TotalMixChannel, output: TotalMixChannel) {
            self.source = source
            self.output = output
        }
    }

    public private(set) var nodes: [NodeKey: [String: OSCValue]] = [:]
    public private(set) var channels: [TotalMixChannel: [String: OSCValue]] = [:]
    public private(set) var status: [String: OSCValue] = [:]
    /// 控制室、全局静音、快照状态（第 7.9 节）。
    public private(set) var globals: [String: OSCValue] = [:]
    public private(set) var levels: [TotalMixChannel: Double] = [:]
    public private(set) var unparsedCount = 0
    /// 除电平以外的内容每变一次加 1（App 据此判断要不要重建快照，第 6.4.3 节“与 TotalMix 同步”）。
    public private(set) var revision = 0

    public init() {}

    public mutating func apply(_ event: TotalMixEvent) {
        switch event {
        case let .mixNode(src, out, parameter, value):
            let key = NodeKey(source: src, output: out)
            if nodes[key]?[parameter] != value { revision += 1 }
            nodes[key, default: [:]][parameter] = value
        case let .channel(ch, parameter, value):
            if channels[ch]?[parameter] != value { revision += 1 }
            channels[ch, default: [:]][parameter] = value
        case let .level(ch, dB):
            levels[ch] = dB
        case let .status(key, value):
            // 只有“连没连上”算变化；DSP 负载等状态 TotalMix 大约每秒发一个，不触发重建
            if key == "connection", status[key] != value { revision += 1 }
            status[key] = value
        case let .global(key, value):
            if globals[key] != value { revision += 1 }
            globals[key] = value
        case .other:
            unparsedCount += 1
        }
    }

    public mutating func apply(_ message: OSCMessage) { apply(TotalMixEvent.parse(message)) }

    // MARK: 派生值

    public var names: [TotalMixChannel: String] {
        channels.compactMapValues { $0["name"]?.text }
    }

    /// 立体声配对；未收到时为 nil（按单声道处理）。
    public func isStereo(_ ch: TotalMixChannel) -> Bool? {
        channels[ch]?["stereo"]?.number.map { $0 >= 0.5 }
    }

    /// 控制室 / 快照的当前值；没收到为 nil。
    public func globalValue(_ g: TotalMixGlobal) -> Double? { globals[g.key]?.number }

    /// 节点声像（-1…+1）；没收到为 nil。
    public func nodePan(_ key: NodeKey) -> Double? { nodes[key]?["balpan"]?.number }

    /// 通道条参数的当前值；没收到为 nil。
    public func stripValue(_ ch: TotalMixChannel, _ param: TotalMixStripParam) -> Double? {
        channels[ch]?[param.rawValue]?.number
    }

    /// 通道条参数写到哪个 TotalMix 通道：立体声右声道（偶数号、左声道是立体声）除 L/R 参数外改用左声道。
    public func stripTarget(_ ch: TotalMixChannel, _ param: TotalMixStripParam) -> TotalMixChannel {
        // 配对一律写在奇数号（左）通道上
        if param == .stereo { return ch.number % 2 == 0 ? TotalMixChannel(ch.bus, ch.number - 1) : ch }
        guard !param.isPerSide, ch.number % 2 == 0 else { return ch }
        let left = TotalMixChannel(ch.bus, ch.number - 1)
        return isStereo(left) == true ? left : ch
    }

    /// 节点电平 dB：优先 fader，其次由 faderlin 换算；关闭时为 nil。
    public func gainDB(_ key: NodeKey) -> Double? {
        guard let params = nodes[key] else { return nil }
        if let dB = params["fader"]?.number { return TotalMixFader.isOn(dB) ? dB : nil }
        if let lin = params["faderlin"]?.number { return TotalMixFader.dB(fromLinear: lin) }
        return nil
    }

    public var deviceName: String? { status["device"]?.text }
    public var connected: Bool? { status["connection"]?.number.map { $0 >= 0.5 } }

    /// 把打开的混音节点翻译成路由。立体声展开：双立体声左对左、右对右；单声道进立体声输出送左右两路；
    /// 立体声进单声道输出两路合入。节点本身（左声道）为 confirmed，展开出的其余各路为 inferred；
    /// 对照表条目为 inferred 时整条路由降为 inferred。对照表缺项的节点计入 unmapped，不生成路由。
    public func routes(using map: TotalMixChannelMap) -> (routes: [Route], unmapped: Int) {
        var routes: [Route] = []
        var unmapped = 0
        for key in nodes.keys.sorted(by: { ($0.output, $0.source) < ($1.output, $1.source) }) {
            guard let dB = gainDB(key) else { continue }
            let srcStereo = isStereo(key.source) ?? false
            let outStereo = isStereo(key.output) ?? false
            let s = key.source, o = key.output
            func ch(_ c: TotalMixChannel, _ plus: Int) -> TotalMixChannel { TotalMixChannel(c.bus, c.number + plus) }
            var pairs: [(TotalMixChannel, TotalMixChannel)] = [(s, o)]
            switch (srcStereo, outStereo) {
            case (true, true): pairs.append((ch(s, 1), ch(o, 1)))
            case (false, true): pairs.append((s, ch(o, 1)))
            case (true, false): pairs.append((ch(s, 1), o))
            case (false, false): break
            }
            for (i, (from, to)) in pairs.enumerated() {
                guard let a = map[from], let b = map[to] else { unmapped += 1; continue }
                let fromMap = a.evidence == .confirmed && b.evidence == .confirmed
                let evidence: Evidence = (i == 0 && fromMap) ? .confirmed : .inferred
                routes.append(Route(domain: .totalMix, source: a.ref, destination: b.ref,
                                    kind: .mixSend(gainDB: dB), evidence: evidence))
            }
        }
        return (routes, unmapped)
    }

    /// XT 自带话放（文档第 7.0 节）：只取对照表映射到 `<设备>.mic.in` 的输入。
    /// 48v / phase / autoset 为 0/1；gain 单位为 dB（2026-10-25 实测：TotalMix 里调到 60 dB，读回 60.0）。
    public func preamps(using map: TotalMixChannelMap, micPortID: String, source: FactSource) -> [PreampChannel] {
        channels.keys.filter { $0.bus == .input }.compactMap { ch -> PreampChannel? in
            guard let entry = map[ch], entry.ref.portID == micPortID, let params = channels[ch] else { return nil }
            func src(_ key: String) -> FactSource {
                var s = source
                s.reference = "/input/\(ch.wireIndex)/\(key)"
                return s
            }
            func flag(_ key: String) -> Fact<Bool> {
                params[key]?.number.map { .confirmed($0 >= 0.5, src(key)) } ?? .unknown(src(key))
            }
            let defaultName = "Mic \(entry.ref.channel)"
            let label: Fact<String> = params["name"]?.text.map { name in
                .confirmed(name == defaultName ? "" : name, src("name"))
            } ?? .unknown(src("name"))
            let gain: Fact<Double> = params["gain"]?.number.map { .confirmed($0, src("gain")) } ?? .unknown(src("gain"))
            return PreampChannel(input: entry.ref, label: label, gainDB: gain, phantom: flag("48v"), phase: flag("phase"),
                                 hiZ: params["instrument"] == nil ? .unknown(src("instrument")) : flag("instrument"),
                                 autoGain: flag("autoset"), gainGroup: .unknown(src("gaingroup")))
        }
        .sorted { $0.input < $1.input }
    }

    /// 输出静音（R13）。立体声输出左右都记。
    public func outputMuted(using map: TotalMixChannelMap, source: FactSource) -> [ChannelRef: Fact<Bool>] {
        var out: [ChannelRef: Fact<Bool>] = [:]
        for (ch, params) in channels where ch.bus == .output {
            guard let muted = params["mute"]?.number.map({ $0 >= 0.5 }) else { continue }
            let members = (isStereo(ch) ?? false) ? [ch, TotalMixChannel(ch.bus, ch.number + 1)] : [ch]
            for m in members {
                guard let e = map[m] else { continue }
                var src = source
                src.reference = "/output/\(m.wireIndex)/mute"
                out[e.ref] = Fact(muted, e.evidence == .confirmed ? .confirmed : .inferred, source: src)
            }
        }
        return out
    }
}
