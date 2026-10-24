import Foundation
import Network

/// 收发原始 OSC 包。TotalMix 发往它设置里的远端端口，不回发到来源端口，所以收、发是两个端点。
public protocol OSCTransport: AnyObject, Sendable {
    /// 开始监听；每收到一个 UDP 包回调一次（回调可能在任意线程）。
    func start(onReceive: @escaping @Sendable (Data) -> Void) async throws
    func send(_ packet: Data) async throws
    func stop()
}

public enum OSCTransportError: Error, Equatable {
    case badPort(Int)
    case listenerFailed(String)
    case sendFailed(String)
    case notStarted
}

/// Network.framework 上的 UDP 传输。
/// - 发送：到 TotalMix 的接收端口（Settings → OSC → Details 的 “Port incoming”）。
/// - 接收：在本机 localPort 监听（TotalMix 的 “Port outgoing”）；传 0 由系统分配，`boundPort` 给出实际端口。
/// 开 Wi-Fi 时 TotalMix 可能绑定 IPv6（文档第 7 节），此时 remoteHost 用 "::1"。
public final class UDPOSCTransport: OSCTransport, @unchecked Sendable {
    public let remoteHost: String
    public let remotePort: Int
    public let localPort: Int

    private let queue = DispatchQueue(label: "rme.osc.udp")
    private var listener: NWListener?
    private var sender: NWConnection?
    private var inbound: [NWConnection] = []
    private let lock = NSLock()

    public init(remoteHost: String = "127.0.0.1", remotePort: Int, localPort: Int) {
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.localPort = localPort
    }

    /// 监听就绪后的实际端口。
    public var boundPort: Int? {
        lock.withLock { listener?.port.map { Int($0.rawValue) } }
    }

    public func start(onReceive: @escaping @Sendable (Data) -> Void) async throws {
        guard let remote = NWEndpoint.Port(rawValue: UInt16(clamping: remotePort)), remotePort > 0 else {
            throw OSCTransportError.badPort(remotePort)
        }
        guard (0 ... 65535).contains(localPort) else { throw OSCTransportError.badPort(localPort) }

        let l = try NWListener(using: .udp, on: NWEndpoint.Port(rawValue: UInt16(localPort)) ?? .any)
        l.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            self.lock.withLock { self.inbound.append(conn) }
            conn.start(queue: self.queue)
            Self.receiveLoop(conn, onReceive)
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = OnceFlag()
            l.stateUpdateHandler = { state in
                switch state {
                case .ready: if once.take() { cont.resume() }
                case let .failed(e): if once.take() { cont.resume(throwing: OSCTransportError.listenerFailed("\(e)")) }
                case .cancelled: if once.take() { cont.resume(throwing: OSCTransportError.listenerFailed("cancelled")) }
                default: break
                }
            }
            l.start(queue: queue)
        }

        let c = NWConnection(host: NWEndpoint.Host(remoteHost), port: remote, using: .udp)
        c.start(queue: queue)
        lock.withLock {
            listener = l
            sender = c
        }
    }

    private static func receiveLoop(_ conn: NWConnection, _ onReceive: @escaping @Sendable (Data) -> Void) {
        conn.receiveMessage { data, _, _, error in
            if let data, !data.isEmpty { onReceive(data) }
            if error == nil { receiveLoop(conn, onReceive) }
        }
    }

    public func send(_ packet: Data) async throws {
        let c = lock.withLock { sender }
        guard let c else { throw OSCTransportError.notStarted }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            c.send(content: packet, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: OSCTransportError.sendFailed("\(error)")) } else { cont.resume() }
            })
        }
    }

    public func stop() {
        let (l, c, ins) = lock.withLock {
            defer { listener = nil; sender = nil; inbound = [] }
            return (listener, sender, inbound)
        }
        l?.cancel()
        c?.cancel()
        ins.forEach { $0.cancel() }
    }
}

/// 只允许第一次 take() 返回 true（continuation 只能 resume 一次）。
private final class OnceFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func take() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// 测试用：记录发出的包，并可注入“收到”的包。不碰网络。
public final class MockOSCTransport: OSCTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (Data) -> Void)?
    private var _sent: [Data] = []
    /// 每次 send 后调用，可用来模拟 TotalMix 的回包。
    public var respond: (@Sendable (OSCMessage, MockOSCTransport) -> Void)?

    public init() {}

    public var sent: [OSCMessage] {
        lock.withLock { _sent }.compactMap { try? OSCCodec.decode($0).messages.first }
    }

    public func start(onReceive: @escaping @Sendable (Data) -> Void) async throws {
        lock.withLock { handler = onReceive }
    }

    public func send(_ packet: Data) async throws {
        let r: (@Sendable (OSCMessage, MockOSCTransport) -> Void)?? = lock.withLock {
            guard handler != nil else { return nil }
            _sent.append(packet)
            return .some(respond)
        }
        guard let r else { throw OSCTransportError.notStarted }
        if let r, let m = try? OSCCodec.decode(packet).messages.first { r(m, self) }
    }

    public func inject(_ packet: OSCPacket) {
        let h = lock.withLock { handler }
        h?(OSCCodec.encode(packet))
    }

    public func inject(_ messages: [OSCMessage]) {
        inject(.bundle(timeTag: 1, elements: messages.map(OSCPacket.message)))
    }

    public func stop() {
        lock.withLock { handler = nil }
    }
}
