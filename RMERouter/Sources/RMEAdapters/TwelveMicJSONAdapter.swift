import Foundation
import RMECore

/// 只读请求检查：12Mic 的 JSON 接口没有认证，读与写用同一个 POST，
/// 唯一区别是叶子值是否为 null（文档第 6.2 节）。只读路径发出的请求体必须所有叶子都是 null。
public enum TwelveMicReadGate {
    public static func isReadOnly(_ body: Any) -> Bool {
        switch body {
        case is NSNull: return true
        case let dict as [String: Any]: return !dict.isEmpty && dict.values.allSatisfy(isReadOnly)
        default: return false
        }
    }
}

/// 12Mic：官方手册公开的 JSON(OSC) 远程接口（文档第 6.2 节）。
/// - 方法：HTTP POST，`Content-Type: application/json`，地址 `http://<host>/api/v2/self`
///   （USB 直连时为 http://172.20.0.1；mDNS 为 12mic.local）。需在 STATE > Remote 打开 HTTP Remote。
/// - 读：值传 null；写：传新值；无推送，需轮询；无认证。
/// - 出处：https://docs.rme-audio.com/12mic/150-1c_remote_overview/ （等级 A，2026-10-25 核对）
public struct TwelveMicJSONAdapter: DeviceAdapter {
    public let deviceID: String
    public let domain = ControlDomain.twelveMic
    public let baseURL: URL
    let session: URLSession

    /// 本 App 用的端口 ID 前缀与 12Mic JSON 端口名的对应。
    public var portMap: [String: String] = [
        "madi_coaxial": "12mic.madi_coaxial.out",
        "madi_optical": "12mic.madi_optical.out",
        "phones": "12mic.phones.out",
    ]
    /// JSON 输入端口名 → 本 App 端口 ID（手册未列全；读到未登记的名字时计数提示，见 snapshot 的 settings）。
    public var inputPortMap: [String: String] = [
        "analog": "12mic.analog.in",
        "madi_coaxial": "12mic.madi_coaxial.in",
        "madi_optical": "12mic.madi_optical.in",
    ]

    public init(deviceID: String = "12mic", baseURL: URL, session: URLSession = .shared) {
        self.deviceID = deviceID
        self.baseURL = baseURL
        self.session = session
    }

    public var capabilities: [Capability] {
        let ref = "https://docs.rme-audio.com/12mic/150-1c_remote_overview/"
        return [
            Capability("clock.read (rate, source, per-source rate/sync, soundness)", access: .readOnly, grade: .a, reference: ref),
            Capability("clock.source", access: .readWrite, grade: .a, reference: ref),
            Capability("output.madi.mode (56/64), framesize (48/96)", access: .readWrite, grade: .a, reference: ref),
            Capability("routing.<port>.<1-64> = [inputport, channel]", access: .readWrite, grade: .a, reference: ref),
            Capability("input.analog.n gain/p48/phase/label", access: .readWrite, grade: .a, reference: ref),
            Capability("push notifications", access: .unknown, grade: .a, reference: ref + "（手册：所有值需轮询）"),
            Capability("authentication", access: .unknown, grade: .a, reference: ref + "（手册：无认证，网络上任何人可改）"),
        ]
    }

    // MARK: 传输

    /// 只读请求：请求体先过 TwelveMicReadGate。
    func read(_ query: [String: Any]) async throws -> [String: Any] {
        guard TwelveMicReadGate.isReadOnly(query) else {
            throw AdapterError.badResponse("只读请求里出现了非 null 的值，已拦截")
        }
        return try await post(query)
    }

    private func post(_ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/v2/self"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 3
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch { throw AdapterError.unreachable }
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw AdapterError.badResponse("HTTP status") }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AdapterError.badResponse("not a JSON object")
        }
        return obj
    }

    // MARK: DeviceAdapter

    public func probe() async -> ControlPath {
        let ok = (try? await read(["device": ["entity_name": NSNull()]])) != nil
        return ControlPath(controller: "this-app", transport: .http(baseURL: baseURL.absoluteString),
                           state: ok ? .online : .offline, active: ok)
    }

    public func snapshot() async throws -> DeviceSnapshot {
        let reply = try await read([
            "device": ["entity_name": NSNull()],
            "clock": NSNull(),
            "routing": NSNull(),
            "output": ["madi": NSNull()],
            "input": ["analog": NSNull()],
        ])
        return Self.parseSnapshot(reply, deviceID: deviceID, portMap: portMap, inputPortMap: inputPortMap,
                                  controlPath: ControlPath(controller: "this-app", transport: .http(baseURL: baseURL.absoluteString),
                                                           state: .online, active: true),
                                  observedAt: Date())
    }

    /// 把一次读取的回包翻译成快照（纯函数，便于测试）。
    static func parseSnapshot(_ reply: [String: Any], deviceID: String, portMap: [String: String],
                              inputPortMap: [String: String], controlPath: ControlPath, observedAt: Date) -> DeviceSnapshot {
        let src = { (path: String) in FactSource(deviceID: deviceID, interface: "12mic-json", reference: path, observedAt: observedAt) }

        // 时钟
        let clock = reply["clock"] as? [String: Any] ?? [:]
        let rate = clock["current_sampling_rate"] as? Int
        let source: ClockSource? = (clock["source"] as? String).map { name in
            switch name {
            case "internal": return .internal
            case "wordclock": return .wordClock
            default: return inputPortMap[name].map(ClockSource.port) ?? .port("12mic.\(name)")
            }
        }
        var lock: [String: Fact<Bool>] = [:], sync: [String: Fact<Bool>] = [:]
        if let sources = clock["sources"] as? [String: Any] {
            for (name, id) in [("madi_coaxial", "12mic.madi_coaxial.in"), ("madi_optical", "12mic.madi_optical.in")] {
                guard let s = sources[name] as? [String: Any] else { continue }
                // 锁定时 rate 为整数 Hz；未锁定时的取值手册未写，按“非正整数即未锁定”处理，证据记为 inferred。
                if let r = s["rate"] {
                    let locked = (r as? Int).map { $0 > 0 } ?? false
                    lock[id] = Fact(locked, (r is Int) ? .confirmed : .inferred, source: src("clock/sources/\(name)/rate"))
                }
                if let sy = s["sync"] as? Bool { sync[id] = .confirmed(sy, src("clock/sources/\(name)/sync")) }
            }
        }
        let clockState = ClockState(
            configuredRate: rate.map { .confirmed($0, src("clock/current_sampling_rate")) } ?? .unknown(src("clock")),
            source: source.map { .confirmed($0, src("clock/source")) } ?? .unknown(src("clock/source")),
            lock: lock, sync: sync)

        // MADI 输出格式（两个 MADI 口共用一个设置）
        var formats: [String: Fact<StreamFormat>] = [:]
        if let madi = (reply["output"] as? [String: Any])?["madi"] as? [String: Any], let rate {
            let fmt = StreamFormat(sampleRate: rate,
                                   madiFrame: (madi["framesize"] as? Int) == 96 ? .frame96k : .frame48k,
                                   channelMode: MadiChannelMode(rawValue: madi["mode"] as? Int ?? 64))
            for (json, id) in portMap where json.hasPrefix("madi") { formats[id] = .confirmed(fmt, src("output/madi")) }
        }

        // 路由：每个输出口 "1"..."64" → [inputport, channel]
        var routes: [Route] = []
        var unknownInputs: [String: Int] = [:]
        let routing = reply["routing"] as? [String: Any] ?? [:]
        for (jsonPort, outID) in portMap {
            guard let table = routing[jsonPort] as? [String: Any] else { continue }
            for (key, value) in table {
                guard let outCh = Int(key), let pair = value as? [Any], pair.count == 2,
                      let inName = pair[0] as? String, inName != "unrouted", let inCh = pair[1] as? Int else { continue }
                guard let inID = inputPortMap[inName] else { unknownInputs[inName, default: 0] += 1; continue }
                routes.append(Route(domain: .twelveMic, source: ChannelRef(inID, inCh),
                                    destination: ChannelRef(outID, outCh), kind: .passthrough, evidence: .confirmed))
            }
        }

        var settings: [String: Fact<String>] = [:]
        if let name = (reply["device"] as? [String: Any])?["entity_name"] as? String {
            settings["12mic.entityName"] = .confirmed(name, src("device/entity_name"))
        }
        if let soundness = clock["soundness"] as? [String: Any] {
            if let state = soundness["state"] as? String { settings["12mic.clock.soundness"] = .confirmed(state, src("clock/soundness/state")) }
            if let cause = soundness["cause"] as? String { settings["12mic.clock.soundnessCause"] = .confirmed(cause, src("clock/soundness/cause")) }
        }
        if !unknownInputs.isEmpty {
            let text = unknownInputs.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
            settings["12mic.unknownInputPorts"] = .confirmed(text, src("routing"))
        }

        let analog = (reply["input"] as? [String: Any])?["analog"] as? [String: Any] ?? [:]
        let preamps = parsePreamps(analog, inputPortID: inputPortMap["analog"] ?? "\(deviceID).analog.in", src: src)

        return DeviceSnapshot(deviceID: deviceID, reachable: true, clock: clockState, portFormats: formats,
                              routes: routes.sorted { $0.destination < $1.destination },
                              controlPaths: [controlPath], settings: settings, preamps: preamps)
    }

    /// `input/analog/<n>` → 前级状态。手册未写字段的确切类型：布尔也接受 0/1；读不到的字段记 unknown。
    static func parsePreamps(_ analog: [String: Any], inputPortID: String,
                             src: (String) -> FactSource) -> [PreampChannel] {
        analog.compactMap { key, value -> PreampChannel? in
            guard let n = Int(key), let ch = value as? [String: Any] else { return nil }
            let path = "input/analog/\(n)"
            func bool(_ k: String) -> Fact<Bool> {
                let v = ch[k]
                if let b = v as? Bool { return .confirmed(b, src("\(path)/\(k)")) }
                if let i = v as? Int, i == 0 || i == 1 { return .confirmed(i == 1, src("\(path)/\(k)")) }
                return .unknown(src("\(path)/\(k)"))
            }
            func string(_ k: String) -> Fact<String> {
                if let t = ch[k] as? String { return .confirmed(t, src("\(path)/\(k)")) }
                if let i = ch[k] as? Int { return .confirmed(String(i), src("\(path)/\(k)")) }
                return .unknown(src("\(path)/\(k)"))
            }
            let gain: Fact<Double> = (ch["gain"] as? NSNumber).map { .confirmed($0.doubleValue, src("\(path)/gain")) }
                ?? .unknown(src("\(path)/gain"))
            return PreampChannel(input: ChannelRef(inputPortID, n), label: string("label"), gainDB: gain,
                                 phantom: bool("p48"), phase: bool("phase"), hiZ: bool("hiz"),
                                 autoGain: bool("gain_autoset"), gainGroup: string("gain_group"))
        }
        .sorted { $0.input < $1.input }
    }

    public func plan(_ change: RouteChange, current: DeviceSnapshot) -> [PlannedOperation] {
        guard let jsonPort = portMap.first(where: { $0.value == change.destination.portID })?.key,
              let inName = inputPortMap.first(where: { $0.value == change.source.portID })?.key else { return [] }
        let old = current.routes.first { $0.destination == change.destination }
        let oldValue = old.map { r -> String in
            let n = inputPortMap.first { $0.value == r.source.portID }?.key ?? "?"
            return "[\"\(n)\",\(r.source.channel)]"
        } ?? "[\"unrouted\",1]"
        return [PlannedOperation(deviceID: deviceID, parameter: "routing/\(jsonPort)/\(change.destination.channel)",
                                 oldValue: oldValue, newValue: "[\"\(inName)\",\(change.source.channel)]",
                                 access: .readWrite)]
    }

    /// 写入：只在用户确认后（precheck 检查 UserConfirmation 与 access）。App 尚未接入 12Mic 写入。
    public func apply(_ op: PlannedOperation, confirmation: UserConfirmation) async throws {
        try precheck(op, confirmation)
        let parts = op.parameter.split(separator: "/").map(String.init)   // routing / port / channel
        guard parts.count == 3,
              let data = op.newValue.data(using: .utf8),
              let value = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw AdapterError.badResponse("bad operation \(op.parameter)")
        }
        _ = try await post([parts[0]: [parts[1]: [parts[2]: value]]])
    }

    public func verify(_ op: PlannedOperation) async throws -> VerificationResult {
        let parts = op.parameter.split(separator: "/").map(String.init)
        guard parts.count == 3 else { return .unreadable }
        let reply = try await read([parts[0]: [parts[1]: [parts[2]: NSNull()]]])
        guard let v = ((reply[parts[0]] as? [String: Any])?[parts[1]] as? [String: Any])?[parts[2]],
              let data = try? JSONSerialization.data(withJSONObject: v),
              let text = String(data: data, encoding: .utf8) else { return .unreadable }
        return text.replacingOccurrences(of: " ", with: "") == op.newValue ? .matches : .differs(readBack: text)
    }
}
