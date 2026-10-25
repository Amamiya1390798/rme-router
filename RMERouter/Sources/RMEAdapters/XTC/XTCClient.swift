import Foundation

/// XTC 的 SysEx 客户端：收报文、合并状态；读取 = 发“请求全部参数”（只读，不改设备）。
public actor XTCClient {
    public let transport: XTCMIDITransport
    /// XTC 面板 Options → General Settings 里的 MIDI 设备 ID（0–7）。
    public let midiDeviceID: Int

    public private(set) var state = XTCState()
    public private(set) var levels: [Int: Double] = [:]        // Mic 1…8 → dB
    private var started = false
    private var received = 0
    private var lastReceive: Date?

    public init(transport: XTCMIDITransport, midiDeviceID: Int = 0) {
        self.transport = transport
        self.midiDeviceID = midiDeviceID
    }

    public func start() async throws {
        guard !started else { return }
        try await transport.start { [weak self] bytes in
            guard let self else { return }
            Task { await self.handle(bytes) }
        }
        started = true
    }

    public func stop() {
        transport.stop()
        started = false
    }

    func handle(_ bytes: [UInt8]) {
        guard let msg = XTCSysEx.parse(bytes), msg.device == midiDeviceID,
              msg.command == XTCSysEx.Command.send.rawValue else { return }
        state.apply(msg.params)
        for p in msg.params where (26 ... 29).contains(p.index) {
            let first = Int(p.index - 26) * 2 + 1
            levels[first] = XTCLevel.dB(p.lsb)
            levels[first + 1] = XTCLevel.dB(p.msb)
        }
        received += 1
        lastReceive = Date()
    }

    public enum ReadError: Error, Equatable { case noReply }

    /// 请求全部参数，等到回包并且静默 `quiet` 秒；`timeout` 内一个回包都没有则报错。
    public func readAll(timeout: Duration = .seconds(1.5), quiet: Duration = .milliseconds(150)) async throws -> XTCState {
        try await start()
        let before = received
        try await transport.send(XTCSysEx.request(.requestAll, device: midiDeviceID))
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            if received > before, let last = lastReceive,
               Date().timeIntervalSince(last) >= Double(quiet.components.attoseconds) / 1e18 + Double(quiet.components.seconds) {
                return state
            }
        }
        if received > before { return state }
        throw ReadError.noReply
    }

    /// 设置参数（命令 20）。只应由适配器在用户确认后调用；闸门在传输层再查一次。
    func set(_ params: [XTCSysEx.Param]) async throws {
        try await start()
        let msg = try XTCSysEx.set(params, device: midiDeviceID)
        try XTCSendGate.check(msg)
        try await transport.send(msg)
    }
}
