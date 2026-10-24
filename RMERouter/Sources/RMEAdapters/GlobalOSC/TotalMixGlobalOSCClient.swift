import Foundation

/// TotalMix Global OSC 只读客户端（开发顺序第 3 步）。
/// 只暴露 `request(_:)`，消息再经 `OSCSendGate` 按白名单复核；写入在第 6 步接入“待应用”栏后再加。
public actor TotalMixGlobalOSCClient {
    public struct Stats: Equatable, Sendable {
        public var packetsReceived = 0
        public var messagesReceived = 0
        public var decodeErrors = 0
        public var messagesSent = 0
    }

    private let transport: OSCTransport
    private let gate = OSCSendGate(mode: .readOnly)
    private let minSendInterval: Duration
    private let clock = ContinuousClock()

    public private(set) var state = TotalMixState()
    public private(set) var stats = Stats()
    private var started = false
    private var pump: Task<Void, Never>?
    private var lastSend: ContinuousClock.Instant?
    private var lastReceive: ContinuousClock.Instant?
    private var lastStatus: ContinuousClock.Instant?

    /// minSendInterval：发送限速（文档第 7 节安全规则 6），默认 20 ms。
    public init(transport: OSCTransport, minSendInterval: Duration = .milliseconds(20)) {
        self.transport = transport
        self.minSendInterval = minSendInterval
    }

    public func start() async throws {
        guard !started else { return }
        // 经 AsyncStream 串行处理，保证消息按收到的顺序进入状态。
        let (stream, cont) = AsyncStream<Data>.makeStream()
        try await transport.start { cont.yield($0) }
        started = true
        pump = Task { [weak self] in
            for await data in stream { await self?.ingest(data) }
        }
    }

    public func stop() {
        transport.stop()
        pump?.cancel()
        pump = nil
        started = false
    }

    /// 发送一个只读请求。
    public func request(_ r: TotalMixRequest) async throws {
        guard started else { throw OSCTransportError.notStarted }
        let message = r.message
        try gate.check(message)
        if let last = lastSend {
            let wait = last.advanced(by: minSendInterval) - clock.now
            if wait > .zero { try await Task.sleep(for: wait) }
        }
        lastSend = clock.now
        try await transport.send(OSCCodec.encode(message))
        stats.messagesSent += 1
    }

    /// 请求全量状态（/sendall 2：只含打开的混音节点），等回包停顿 quiet 后返回。
    /// 返回值：超时前是否收到过任何回包。
    @discardableResult
    public func refreshAll(quiet: Duration = .milliseconds(300), timeout: Duration = .seconds(3)) async throws -> Bool {
        let before = stats.packetsReceived
        try await request(.sendAll(activeNodesOnly: true))
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
            if stats.packetsReceived > before, let last = lastReceive, clock.now - last >= quiet { return true }
        }
        return stats.packetsReceived > before
    }

    /// 在线探测：发 /sendstate，超时内收到任意 /status/ 消息即在线。
    public func probe(timeout: Duration = .seconds(1)) async -> Bool {
        let sentAt = clock.now
        do { try await request(.sendState) } catch { return false }
        let deadline = sentAt.advanced(by: timeout)
        while clock.now < deadline {
            if let s = lastStatus, s >= sentAt { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func ingest(_ data: Data) {
        stats.packetsReceived += 1
        lastReceive = clock.now
        guard let packet = try? OSCCodec.decode(data) else { stats.decodeErrors += 1; return }
        for m in packet.messages {
            stats.messagesReceived += 1
            if m.address.hasPrefix("/status/") { lastStatus = clock.now }
            state.apply(m)
        }
    }
}
