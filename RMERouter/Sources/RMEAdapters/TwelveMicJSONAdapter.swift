import Foundation
import RMECore

/// 12Mic：官方手册公开的 JSON(OSC) 远程接口。
/// - 方法：HTTP POST，`Content-Type: application/json`，地址 `http://<host>/api/v2/self`
///   （USB 直连时为 http://172.20.0.1；mDNS 为 12mic.local）。需在 STATE > Remote 打开 HTTP Remote。
/// - 读：值传 null；写：传新值；无推送，需轮询。
/// - 出处：https://docs.rme-audio.com/12mic/150-1c_remote_overview/ （等级 A）
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
    /// JSON 输入端口名 → 本 App 端口 ID（输入侧端口名手册未列全，首次运行用 schema 核对）。
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
            Capability("clock.read (rate, source, per-source rate/sync)", access: .readOnly, grade: .a, reference: ref),
            Capability("clock.source", access: .readWrite, grade: .a, reference: ref),
            Capability("output.madi.mode (56/64), framesize (48/96)", access: .readWrite, grade: .a, reference: ref),
            Capability("routing.<port>.<1-64> = [inputport, channel]", access: .readWrite, grade: .a, reference: ref),
            Capability("input.analog.n gain/p48/phase/label", access: .readWrite, grade: .a, reference: ref),
            Capability("push notifications", access: .unknown, grade: .a, reference: ref + "（手册：所有值需轮询）"),
        ]
    }

    // MARK: 传输

    func post(_ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/v2/self"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 2
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw AdapterError.badResponse("HTTP status") }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AdapterError.badResponse("not a JSON object")
        }
        return obj
    }

    // MARK: DeviceAdapter

    public func probe() async -> ControlPath {
        let ok = (try? await post(["device": ["model_name": NSNull()]])) != nil
        return ControlPath(controller: "this-app", transport: .http(baseURL: baseURL.absoluteString),
                           state: ok ? .online : .offline, active: ok)
    }

    public func snapshot() async throws -> DeviceSnapshot {
        let now = Date()
        let src = { (path: String) in FactSource(deviceID: deviceID, interface: "12mic-json", reference: path, observedAt: now) }
        let reply = try await post([
            "clock": NSNull(),
            "routing": NSNull(),
            "output": ["madi": NSNull()],
        ])

        // 时钟
        let clock = reply["clock"] as? [String: Any] ?? [:]
        let rate = clock["current_sampling_rate"] as? Int
        let sourceName = clock["source"] as? String
        let source: ClockSource? = sourceName.map { name -> ClockSource in
            switch name {
            case "internal": return .internal
            case "wordclock": return .wordClock
            case "madi_coaxial": return .port("12mic.madi_coaxial.in")
            case "madi_optical": return .port("12mic.madi_optical.in")
            default: return .port("12mic.\(name)")
            }
        }
        var lock: [String: Fact<Bool>] = [:], sync: [String: Fact<Bool>] = [:]
        if let sources = clock["sources"] as? [String: Any] {
            for (name, id) in [("madi_coaxial", "12mic.madi_coaxial.in"), ("madi_optical", "12mic.madi_optical.in")] {
                guard let s = sources[name] as? [String: Any] else { continue }
                if let r = s["rate"] {   // 有锁时是整数 Hz，无锁时是字符串 "NoLock"
                    lock[id] = .confirmed(!(r is String), src("clock/sources/\(name)/rate"))
                }
                if let sy = s["sync"] as? Bool { sync[id] = .confirmed(sy, src("clock/sources/\(name)/sync")) }
            }
        }
        var rateFact = Fact<Int>.unknown(src("clock"))
        if let rate { rateFact = .confirmed(rate, src("clock/current_sampling_rate")) }
        var sourceFact = Fact<ClockSource>.unknown(src("clock/source"))
        if let source { sourceFact = .confirmed(source, src("clock/source")) }
        let clockState = ClockState(configuredRate: rateFact, source: sourceFact, lock: lock, sync: sync)

        // MADI 输出格式（两个 MADI 口共用一个设置，手册：不能分口设置）
        var formats: [String: Fact<StreamFormat>] = [:]
        if let madi = (reply["output"] as? [String: Any])?["madi"] as? [String: Any], let rate {
            let fmt = StreamFormat(sampleRate: rate,
                                   madiFrame: (madi["framesize"] as? Int) == 96 ? .frame96k : .frame48k,
                                   channelMode: MadiChannelMode(rawValue: madi["mode"] as? Int ?? 64))
            for id in portMap.values { formats[id] = .confirmed(fmt, src("output/madi")) }
        }

        // 路由：每个输出口 "1"..."64" → [inputport, channel]
        var routes: [Route] = []
        for (jsonPort, outID) in portMap {
            guard let table = (reply["routing"] as? [String: Any])?[jsonPort] as? [String: Any] else { continue }
            for (key, value) in table {
                guard let outCh = Int(key), let pair = value as? [Any], pair.count == 2,
                      let inName = pair[0] as? String, inName != "unrouted", let inCh = pair[1] as? Int,
                      let inID = inputPortMap[inName] else { continue }
                routes.append(Route(domain: .twelveMic, source: ChannelRef(inID, inCh),
                                    destination: ChannelRef(outID, outCh), kind: .passthrough, evidence: .confirmed))
            }
        }

        let path = await probe()
        return DeviceSnapshot(deviceID: deviceID, reachable: true, clock: clockState, portFormats: formats,
                              routes: routes.sorted { $0.destination < $1.destination },
                              controlPaths: [path])
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
        let reply = try await post([parts[0]: [parts[1]: [parts[2]: NSNull()]]])
        guard let v = ((reply[parts[0]] as? [String: Any])?[parts[1]] as? [String: Any])?[parts[2]],
              let data = try? JSONSerialization.data(withJSONObject: v),
              let text = String(data: data, encoding: .utf8) else { return .unreadable }
        return text.replacingOccurrences(of: " ", with: "") == op.newValue ? .matches : .differs(readBack: text)
    }
}
