import XCTest
@testable import RMECore
@testable import RMEAdapters

/// 第 7 节 Global OSC：编解码、0 起编号换算（安全规则 1 要求编码层必须有测试）、发送白名单、状态解析。
final class GlobalOSCTests: XCTestCase {

    // MARK: OSC 1.0 编解码

    func testEncodeKnownBytes() {
        let data = OSCCodec.encode(OSCMessage("/sendall", [.float(2.0)]))
        var expected = Array("/sendall".utf8) + [0, 0, 0, 0]        // 8 字符 + 结尾 0，补到 12
        expected += Array(",f".utf8) + [0, 0]                       // 类型标签补到 4
        expected += [0x40, 0x00, 0x00, 0x00]                        // 2.0f 大端
        XCTAssertEqual([UInt8](data), expected)
    }

    func testRoundTripAllTypes() throws {
        let m = OSCMessage("/x/y", [.float(-1.5), .int(-7), .string("M1-9"), .blob(Data([1, 2, 3])),
                                     .bool(true), .bool(false), .double(0.25), .int64(1 << 40), .null, .impulse])
        XCTAssertEqual(try OSCCodec.decode(OSCCodec.encode(m)), .message(m))
    }

    func testNestedBundleFlattensInOrder() throws {
        let a = OSCMessage("/a", [.float(1)]), b = OSCMessage("/b", [.string("x")]), c = OSCMessage("/c", [.int(3)])
        let packet = OSCPacket.bundle(timeTag: 1, elements: [.message(a), .bundle(timeTag: 1, elements: [.message(b)]), .message(c)])
        XCTAssertEqual(try OSCCodec.decode(OSCCodec.encode(packet)).messages, [a, b, c])
    }

    func testTruncatedPacketThrows() {
        let data = OSCCodec.encode(OSCMessage("/output/0/volume", [.float(0.5)]))
        XCTAssertThrowsError(try OSCCodec.decode(data.dropLast(2)))
        XCTAssertThrowsError(try OSCCodec.decode(Data("no-slash\0\0\0\0".utf8)))
    }

    // MARK: 0 起编号只在地址层换算

    func testRequestAddressesAreZeroBased() {
        XCTAssertEqual(TotalMixRequest.sendChannel(TotalMixChannel(.input, 3)).message.address, "/sendchan/input/2")
        XCTAssertEqual(TotalMixRequest.sendChannel(TotalMixChannel(.playback, 1)).message.address, "/sendchan/playback/0")
        XCTAssertEqual(TotalMixRequest.sendSubmix(output: TotalMixChannel(.output, 1), activeNodesOnly: true).message,
                       OSCMessage("/sendsubmix/0", [.float(2)]))
        XCTAssertEqual(TotalMixRequest.sendAll(activeNodesOnly: true).message, OSCMessage("/sendall", [.float(2)]))
        XCTAssertEqual(TotalMixRequest.sendAll(activeNodesOnly: false).message, OSCMessage("/sendall", [.float(1)]))
    }

    func testParseIncomingConvertsToOneBased() {
        // 协议表例：/mix/in/0/2/faderlin = 输入通道 1 到输出通道 3
        XCTAssertEqual(TotalMixEvent.parse(OSCMessage("/mix/in/0/2/faderlin", [.float(0.8)])),
                       .mixNode(source: TotalMixChannel(.input, 1), output: TotalMixChannel(.output, 3),
                                parameter: "faderlin", value: .float(0.8)))
        XCTAssertEqual(TotalMixEvent.parse(OSCMessage("/mix/pb/4/0/fader", [.float(-3)])),
                       .mixNode(source: TotalMixChannel(.playback, 5), output: TotalMixChannel(.output, 1),
                                parameter: "fader", value: .float(-3)))
        XCTAssertEqual(TotalMixEvent.parse(OSCMessage("/output/2/eq/enable", [.float(1)])),
                       .channel(TotalMixChannel(.output, 3), parameter: "eq/enable", value: .float(1)))
        XCTAssertEqual(TotalMixEvent.parse(OSCMessage("/level/pb/0", [.float(-12)])),
                       .level(TotalMixChannel(.playback, 1), dB: -12))
        XCTAssertEqual(TotalMixEvent.parse(OSCMessage("/status/device", [.string("MADIface XT")])),
                       .status(key: "device", value: .string("MADIface XT")))
        // 输出不能做混音节点来源；无值、未知地址都归入 other
        for m in [OSCMessage("/mix/out/0/1/fader", [.float(0)]), OSCMessage("/input/0/mute"),
                  OSCMessage("/controlroom/dim", [.float(1)]), OSCMessage("/input/-1/mute", [.float(1)])] {
            XCTAssertEqual(TotalMixEvent.parse(m), .other(m))
        }
    }

    // MARK: 发送白名单（安全规则 2、3）

    func testEveryRequestPassesGate() throws {
        let gate = OSCSendGate()
        let all: [TotalMixRequest] = [
            .sendAll(activeNodesOnly: true), .sendAll(activeNodesOnly: false), .sendSettings,
            .sendChannel(TotalMixChannel(.input, 1)), .sendChannel(TotalMixChannel(.output, 64)),
            .sendMix(activeNodesOnly: true), .sendSubmix(output: TotalMixChannel(.output, 2), activeNodesOnly: false),
            .sendState,
        ]
        for r in all {
            XCTAssertFalse(r.message.arguments.isEmpty, "\(r) 必须带值")
            XCTAssertNoThrow(try gate.check(r.message), "\(r)")
        }
    }

    func testGateRejectsUnsafeMessages() {
        let gate = OSCSendGate()
        XCTAssertThrowsError(try gate.check(OSCMessage("/sendall"))) {
            XCTAssertEqual($0 as? OSCGateError, .missingValue("/sendall"))
        }
        XCTAssertThrowsError(try gate.check(OSCMessage("/input/0/mute", [.float(1)]))) {
            XCTAssertEqual($0 as? OSCGateError, .writeInReadOnlyMode("/input/0/mute"))
        }
        XCTAssertThrowsError(try gate.check(OSCMessage("/sendall", [.float(0)]))) {
            XCTAssertEqual($0 as? OSCGateError, .triggerValueTooLow("/sendall"))
        }
        for address in ["/sendchan/input/", "/sendchan/input/1/mute", "/sendchan/aux/1", "/sendsubmix/x", "/sendall/1"] {
            XCTAssertFalse(OSCSendGate.isRequest(address), address)
        }
        XCTAssertTrue(OSCSendGate.isRequest("/sendchan/output/63"))
    }

    @MainActor
    func testWriteNeedsReadWriteModeAndConfirmation() throws {
        let msg = OSCMessage("/mix/in/0/0/fader", [.float(-90)])
        let op = PlannedOperation(deviceID: "xt", parameter: msg.address, oldValue: nil, newValue: "-90", access: .readWrite)
        let other = PlannedOperation(deviceID: "xt", parameter: msg.address, oldValue: nil, newValue: "-90", access: .readWrite)
        let confirmation = ConfirmationGate.userConfirmed([op])

        XCTAssertThrowsError(try OSCSendGate(mode: .readOnly).checkWrite(msg, for: op, confirmation: confirmation))
        XCTAssertThrowsError(try OSCSendGate(mode: .readWrite).checkWrite(msg, for: other, confirmation: confirmation))
        XCTAssertThrowsError(try OSCSendGate(mode: .readWrite).checkWrite(OSCMessage(msg.address), for: op, confirmation: confirmation))
        XCTAssertNoThrow(try OSCSendGate(mode: .readWrite).checkWrite(msg, for: op, confirmation: confirmation))
    }

    // MARK: 推子曲线（协议表 Fader curve 页）

    func testFaderCurve() throws {
        XCTAssertEqual(TotalMixFader.linear(fromDB: 0), 836.0 / 1023, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(TotalMixFader.dB(fromLinear: 1)), 6.0, accuracy: 0.001)
        XCTAssertNil(TotalMixFader.dB(fromLinear: 0))
        for dB in [-60.0, -20, -6, -1, 0, 3, 6] {
            XCTAssertEqual(try XCTUnwrap(TotalMixFader.dB(fromLinear: TotalMixFader.linear(fromDB: dB))), dB, accuracy: 0.01)
        }
        XCTAssertFalse(TotalMixFader.isOn(-300))
        XCTAssertFalse(TotalMixFader.isOn(-65))
        XCTAssertTrue(TotalMixFader.isOn(-64))
    }

    // MARK: 对照表与路由

    /// 用 2026-10-25 从真机 TotalMix 读回的命名（右声道不发名字；输出 1、5 被控制室改名为 Main、Phones 1）。
    func testChannelMapInfersFromRealXTNaming() {
        var s = TotalMixState()
        func name(_ bus: String, _ wire: Int, _ n: String, stereo: Bool = false) {
            s.apply(OSCMessage("/\(bus)/\(wire)/name", [.string(n)]))
            s.apply(OSCMessage("/\(bus)/\(wire)/stereo", [.float(stereo ? 1 : 0)]))
        }
        name("input", 0, "Mic 1"); name("input", 1, "Mic 2"); name("input", 2, "AES", stereo: true)
        name("input", 12, "M1-9"); name("input", 68, "M2-1/2", stereo: true)
        name("playback", 0, "AN 1/2", stereo: true); name("playback", 4, "PH", stereo: true)
        name("output", 0, "Main", stereo: true); name("output", 4, "Phones 1", stereo: true)
        name("output", 6, "M1-1"); name("output", 8, "M1-3/4", stereo: true)
        name("input", 4, "M1-1")                      // 已确认为别的口，不覆盖

        var map = TotalMixChannelMap(confirmed: [TotalMixChannel(.input, 5): ChannelRef("xt.madi3.in", 1)])
        map.infer(from: s)
        func ref(_ bus: TotalMixBus, _ n: Int) -> String? { map[TotalMixChannel(bus, n)].map { "\($0.ref)" } }

        XCTAssertEqual(ref(.input, 1), "xt.mic.in:1")
        XCTAssertEqual(ref(.input, 2), "xt.mic.in:2")
        XCTAssertEqual(ref(.input, 3), "xt.aes.in:1")
        XCTAssertEqual(ref(.input, 4), "xt.aes.in:2")            // 立体声右声道
        XCTAssertEqual(ref(.input, 13), "xt.madi1.in:9")
        XCTAssertEqual(ref(.input, 69), "xt.madi2.in:1")
        XCTAssertEqual(ref(.input, 70), "xt.madi2.in:2")
        XCTAssertEqual(ref(.output, 1), "xt.an.out:1")           // “Main” 退回回放名 “AN 1/2”
        XCTAssertEqual(ref(.output, 2), "xt.an.out:2")
        XCTAssertEqual(ref(.output, 5), "xt.phones.out:1")       // “Phones 1” 退回回放名 “PH”
        XCTAssertEqual(ref(.output, 6), "xt.phones.out:2")
        XCTAssertEqual(ref(.output, 7), "xt.madi1.out:1")
        XCTAssertEqual(ref(.output, 10), "xt.madi1.out:4")
        XCTAssertEqual(ref(.playback, 7), "xt.playback.in:7")    // 回放按定义
        XCTAssertEqual(map[TotalMixChannel(.playback, 7)]?.evidence, .confirmed)
        XCTAssertEqual(map[TotalMixChannel(.input, 13)]?.evidence, .inferred)
        XCTAssertEqual(map[TotalMixChannel(.input, 5)], .init(ref: ChannelRef("xt.madi3.in", 1), evidence: .confirmed))
        XCTAssertNil(map[TotalMixChannel(.input, 100)])          // 没收到名字（隐藏通道）
    }

    /// XT 自带话放（第 7.0 节）：只取映射到 xt.mic.in 的输入；默认名视为无标签；gain 证据为 inferred。
    func testXTPreampsFromTotalMix() {
        var s = TotalMixState()
        for m in [
            OSCMessage("/input/0/name", [.string("Mic 1")]), OSCMessage("/input/0/48v", [.float(1)]),
            OSCMessage("/input/0/gain", [.float(23.5)]), OSCMessage("/input/0/phase", [.float(0)]),
            OSCMessage("/input/0/autoset", [.float(0)]),
            OSCMessage("/input/1/name", [.string("Kick mic")]), OSCMessage("/input/1/48v", [.float(0)]),
            OSCMessage("/input/12/name", [.string("M1-9")]), OSCMessage("/input/12/48v", [.float(1)]),   // MADI 通道：不算 XT 话放
        ] { s.apply(m) }
        var map = TotalMixChannelMap()
        map.confirm(TotalMixChannel(.input, 2), ChannelRef("xt.mic.in", 2))   // 改了名，按用户确认的对照表
        map.infer(from: s)
        let p = s.preamps(using: map, micPortID: "xt.mic.in", source: FactSource(interface: "totalmix-osc"))
        XCTAssertEqual(p.map(\.input.description), ["xt.mic.in:1", "xt.mic.in:2"])
        XCTAssertEqual(p[0].label.knownValue, "")                 // 默认名 → 无标签
        XCTAssertEqual(p[0].phantom.knownValue, true)
        XCTAssertEqual(p[0].gainDB.knownValue, 23.5)
        XCTAssertEqual(p[0].gainDB.evidence, .confirmed)          // 单位已实测核对为 dB
        XCTAssertEqual(p[0].phase.knownValue, false)
        XCTAssertEqual(p[0].autoGain.knownValue, false)
        XCTAssertNil(p[0].hiZ.knownValue)                         // XT 话放没有 instrument 参数
        XCTAssertEqual(p[0].gainDB.source.reference, "/input/0/gain")
        XCTAssertEqual(p[1].label.knownValue, "Kick mic")
        XCTAssertNil(p[1].gainDB.knownValue)                      // 没收到 → unknown
    }

    func testHardwareNameParserRejectsControlRoomNames() {
        for (n, bus) in [("Main", TotalMixBus.output), ("Phones 1", .output), ("Mic 1", .output), ("AN 1", .input),
                         ("PH", .input), ("M1-", .input), ("Mx-1", .input), ("M1-1", .playback)] {
            XCTAssertNil(TotalMixChannelMap.parseHardwareName(n, bus: bus, deviceID: "xt"), "\(n) @ \(bus)")
        }
    }

    /// 文档第 6.1 节示例的 TotalMix 一跳：xt.madi2.in:1-2 →[totalmix 发送 0.0 dB] xt.madi1.out:33-34。
    func testStateBuildsRoutesWithStereoExpansion() {
        let inL = TotalMixChannel(.input, 65), inR = TotalMixChannel(.input, 66)
        let outL = TotalMixChannel(.output, 33), outR = TotalMixChannel(.output, 34)
        let map = TotalMixChannelMap(confirmed: [
            inL: ChannelRef("xt.madi2.in", 1), inR: ChannelRef("xt.madi2.in", 2),
            outL: ChannelRef("xt.madi1.out", 33), outR: ChannelRef("xt.madi1.out", 34),
            TotalMixChannel(.input, 9): ChannelRef("xt.madi1.in", 9),
        ])
        var s = TotalMixState()
        s.apply(OSCMessage("/input/64/stereo", [.float(1)]))
        s.apply(OSCMessage("/output/32/stereo", [.float(1)]))
        s.apply(OSCMessage("/mix/in/64/32/fader", [.float(0)]))
        s.apply(OSCMessage("/mix/in/8/32/fader", [.float(-300)]))     // 关：不生成路由
        s.apply(OSCMessage("/mix/in/8/0/fader", [.float(-6)]))        // 输出 1 不在对照表：计入 unmapped
        s.apply(OSCMessage("/output/32/mute", [.float(1)]))

        let (routes, unmapped) = s.routes(using: map)
        XCTAssertEqual(routes, [
            Route(domain: .totalMix, source: ChannelRef("xt.madi2.in", 1), destination: ChannelRef("xt.madi1.out", 33),
                  kind: .mixSend(gainDB: 0), evidence: .confirmed),
            Route(domain: .totalMix, source: ChannelRef("xt.madi2.in", 2), destination: ChannelRef("xt.madi1.out", 34),
                  kind: .mixSend(gainDB: 0), evidence: .inferred),
        ])
        XCTAssertEqual(unmapped, 1)

        let muted = s.outputMuted(using: map, source: FactSource(interface: "totalmix-osc"))
        XCTAssertEqual(muted[ChannelRef("xt.madi1.out", 33)]?.knownValue, true)
        XCTAssertEqual(muted[ChannelRef("xt.madi1.out", 34)]?.knownValue, true)
    }

    func testMonoIntoStereoAndFaderlinFallback() {
        let map = TotalMixChannelMap(confirmed: [
            TotalMixChannel(.input, 9): ChannelRef("xt.madi1.in", 9),
            TotalMixChannel(.output, 1): ChannelRef("xt.madi2.out", 1),
            TotalMixChannel(.output, 2): ChannelRef("xt.madi2.out", 2),
        ])
        var s = TotalMixState()
        s.apply(OSCMessage("/output/0/stereo", [.bool(true)]))
        s.apply(OSCMessage("/mix/in/8/0/faderlin", [.float(Float(TotalMixFader.linear(fromDB: 0)))]))
        let routes = s.routes(using: map).routes
        XCTAssertEqual(routes.map(\.destination), [ChannelRef("xt.madi2.out", 1), ChannelRef("xt.madi2.out", 2)])
        XCTAssertTrue(routes.allSatisfy { $0.source == ChannelRef("xt.madi1.in", 9) })
        guard case let .mixSend(gain?) = routes[0].kind else { return XCTFail() }
        XCTAssertEqual(gain, 0, accuracy: 0.01)
    }

    // MARK: 客户端与适配器（Mock 传输，不碰网络）

    /// 模拟 TotalMix：收到 /sendall 回一个 bundle，收到 /sendstate 回状态。
    func makeFakeTotalMix() -> MockOSCTransport {
        let t = MockOSCTransport()
        t.respond = { m, t in
            switch m.address {
            case "/sendall":
                t.inject([
                    OSCMessage("/input/8/name", [.string("M1-9")]),
                    OSCMessage("/output/64/name", [.string("M2-1")]),
                    OSCMessage("/mix/in/8/64/fader", [.float(-3)]),
                    OSCMessage("/output/64/mute", [.float(0)]),
                    OSCMessage("/status/device", [.string("MADIface XT")]),
                    OSCMessage("/status/connection", [.float(1)]),
                ])
            case "/sendstate":
                t.inject([OSCMessage("/status/connection", [.float(1)])])
            default: break
            }
        }
        return t
    }

    func testClientRefreshSendsOnlySendAllWithValue() async throws {
        let t = makeFakeTotalMix()
        let client = TotalMixGlobalOSCClient(transport: t)
        try await client.start()
        let got = try await client.refreshAll(quiet: .milliseconds(50), timeout: .seconds(2))
        XCTAssertTrue(got)
        XCTAssertEqual(t.sent, [OSCMessage("/sendall", [.float(2)])])
        let state = await client.state
        XCTAssertEqual(state.deviceName, "MADIface XT")
        XCTAssertEqual(state.gainDB(.init(source: TotalMixChannel(.input, 9), output: TotalMixChannel(.output, 65))), -3)
    }

    func testClientProbe() async throws {
        let online = TotalMixGlobalOSCClient(transport: makeFakeTotalMix())
        try await online.start()
        let isOnline = await online.probe(timeout: .milliseconds(500))
        XCTAssertTrue(isOnline)

        let silent = TotalMixGlobalOSCClient(transport: MockOSCTransport())
        try await silent.start()
        let isSilentOnline = await silent.probe(timeout: .milliseconds(100))
        XCTAssertFalse(isSilentOnline)
    }

    func testClientRateLimitsSends() async throws {
        let t = MockOSCTransport()
        let client = TotalMixGlobalOSCClient(transport: t, minSendInterval: .milliseconds(30))
        try await client.start()
        let start = ContinuousClock.now
        for _ in 0 ..< 4 { try await client.request(.sendState) }
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - start, .milliseconds(90))
        XCTAssertEqual(t.sent.count, 4)
    }

    func testAdapterSnapshotUsesNamesAndKeepsClockUnknown() async throws {
        let adapter = TotalMixOSCAdapter(port: 7001, transport: makeFakeTotalMix())
        let snap = try await adapter.snapshot()
        XCTAssertEqual(snap.routes.map { "\($0.source) -> \($0.destination)" }, ["xt.madi1.in:9 -> xt.madi2.out:1"])
        XCTAssertEqual(snap.routes.first?.evidence, .inferred)        // 对照表来自名字解析
        XCTAssertEqual(snap.routes.first?.kind, .mixSend(gainDB: -3))
        XCTAssertEqual(snap.outputMuted[ChannelRef("xt.madi2.out", 1)]?.knownValue, false)
        XCTAssertNil(snap.clock.configuredRate.knownValue)
        XCTAssertEqual(snap.settings["totalmix.unmappedNodes"]?.knownValue, "0")
        XCTAssertTrue(snap.reachable)
    }

    /// 实测：XT 未连接时 TotalMix 仍回发保存的配置，/status/connection = 0。
    func testAdapterSnapshotMarksDeviceOfflineFromConnectionStatus() {
        var s = TotalMixState()
        s.apply(OSCMessage("/mix/in/8/64/fader", [.float(-3)]))
        s.apply(OSCMessage("/status/connection", [.float(0)]))
        let snap = TotalMixOSCAdapter.makeSnapshot(
            deviceID: "xt", state: s, map: TotalMixChannelMap(),
            controlPath: ControlPath(controller: "this-app", transport: .osc(host: "127.0.0.1", port: 7011), state: .online, active: true),
            observedAt: Date())
        XCTAssertFalse(snap.reachable)
        XCTAssertEqual(snap.settings["totalmix.connection"]?.knownValue, "0")
    }

    func testAdapterSnapshotThrowsWhenSilent() async {
        let adapter = TotalMixOSCAdapter(port: 7001, transport: MockOSCTransport())
        do {
            _ = try await adapter.snapshot()       // 默认 3 秒超时
            XCTFail("无回包时应当抛出")
        } catch {
            XCTAssertEqual(error as? AdapterError, .unreachable)
        }
    }

    // MARK: 真 UDP 回环（只在本机 127.0.0.1 两个临时端口之间收发）

    func testUDPLoopback() async throws {
        let receiver = UDPOSCTransport(remoteHost: "127.0.0.1", remotePort: 9, localPort: 0)
        let got = expectation(description: "received")
        let box = MessageBox()
        try await receiver.start { data in
            if let m = try? OSCCodec.decode(data).messages.first { box.set(m); got.fulfill() }
        }
        defer { receiver.stop() }
        let port = try XCTUnwrap(receiver.boundPort)

        let sender = UDPOSCTransport(remoteHost: "127.0.0.1", remotePort: port, localPort: 0)
        try await sender.start { _ in }
        defer { sender.stop() }
        try await sender.send(OSCCodec.encode(OSCMessage("/status/connection", [.float(1)])))

        await fulfillment(of: [got], timeout: 2)
        XCTAssertEqual(box.get(), OSCMessage("/status/connection", [.float(1)]))
    }
}

private final class MessageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var m: OSCMessage?
    func set(_ v: OSCMessage) { lock.withLock { m = v } }
    func get() -> OSCMessage? { lock.withLock { m } }
}
