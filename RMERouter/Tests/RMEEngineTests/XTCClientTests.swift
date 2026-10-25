import XCTest
import CoreMIDI
@testable import RMECore
@testable import RMEAdapters

/// XTC 发送闸门、UMP 封包、客户端与适配器（文档第 6.3 节）。用 FakeXTC 与系统虚拟 MIDI 端口，不碰真实设备。
final class XTCClientTests: XCTestCase {

    // MARK: 闸门

    func testGateAllowsRequestsAndWhitelistedSets() throws {
        try XTCSendGate.check(XTCSysEx.request(.requestAll, device: 0))
        try XTCSendGate.check(XTCSysEx.set([XTCMicSettings.setParam(mic: 1, gainDB: 40, phantom: true)], device: 0))
        try XTCSendGate.check(XTCSysEx.set([XTCRoutingOutput.madi(block: 5).setParam(.madi(block: 2))], device: 0))
    }

    func testGateBlocksDangerousParams() throws {
        let cases: [(XTCSysEx.Param, XTCSendGate.Rejection)] = [
            (.init(index: 25, lsb: 1, msb: 0, flags: 0x7F), .index(25)),        // 加载预设
            (.init(index: 26, lsb: 0, msb: 1, flags: 0x7F), .index(26)),        // 编组增益
            (.init(index: 23, lsb: 0, msb: 0, flags: 0x01), .index(23)),        // MIDI 来源
            (.init(index: 21, lsb: 0, msb: 2, flags: 0x01), .index(21)),        // 时钟只读
            (.init(index: 0, lsb: 0, msb: 0, flags: 0x7F), .flags(index: 0, flags: 0x7F)),   // 含静音/AutoSet/Pad/编组
            (.init(index: 0, lsb: 0, msb: 0, flags: 0x00), .flags(index: 0, flags: 0x00)),
            (.init(index: 0, lsb: 55, msb: 0, flags: 0x01), .value(index: 0)),  // 64 dB > 60
            (.init(index: 16, lsb: 0, msb: 0, flags: 0x04), .flags(index: 16, flags: 0x04)),
            (.init(index: 16, lsb: 16, msb: 0, flags: 0x01), .value(index: 16)),
        ]
        for (p, expected) in cases {
            XCTAssertThrowsError(try XTCSendGate.check(XTCSysEx.set([p], device: 0)), "\(p)") {
                XCTAssertEqual($0 as? XTCSendGate.Rejection, expected)
            }
        }
        // 一条报文里只要有一个危险参数就整条拦截。
        XCTAssertThrowsError(try XTCSendGate.check(XTCSysEx.set([XTCMicSettings.setParam(mic: 1, gainDB: 10),
                                                                  .init(index: 25, lsb: 1, msb: 0, flags: 0x01)], device: 0)))
        XCTAssertThrowsError(try XTCSendGate.check(XTCSysEx.header + [0x00, 0x30, 0xF7]))           // 命令 30 不由本 App 发
        XCTAssertThrowsError(try XTCSendGate.check([0xF0, 0x00, 0x20, 0x0D, 0x68, 0x00, 0x10, 0xF7]))  // 别的设备
        XCTAssertThrowsError(try XTCSendGate.check(XTCSysEx.header + [0x00, 0x20, 0x00, 0x01, 0xF7]))  // 长度不对
    }

    // MARK: UMP

    func testUMPRoundTrip() {
        for n in [0, 1, 5, 6, 7, 12, 13, 40] {
            let data: [UInt8] = (0 ..< n).map { UInt8($0 % 0x7F) }
            let msg: [UInt8] = XTCSysEx.header + [0x00, 0x30] + data + [XTCSysEx.end]
            let words = UMPSysEx7.pack(msg)
            XCTAssertEqual(words.count, 2 * ((msg.count - 2 + 5) / 6))
            for i in stride(from: 0, to: words.count, by: 2) { XCTAssertEqual(words[i] >> 28, 0x3) }
            var a = UMPSysEx7.Assembler()
            XCTAssertEqual(a.feed(words), [msg], "n=\(n)")
        }
        // 分两次送进来也能拼好，中间夹一个 MIDI 1.0 通道消息（类型 2，1 个字）。
        let msg = XTCSysEx.header + [0x00, 0x30, 1, 2, 3, 4, 5, 6, 7, 8, 9] + [XTCSysEx.end]
        let w = UMPSysEx7.pack(msg)
        var a = UMPSysEx7.Assembler()
        XCTAssertEqual(a.feed(Array(w.prefix(2)) + [0x2090_3C64]), [])
        XCTAssertEqual(a.feed(Array(w.dropFirst(2))), [msg])
    }

    // MARK: 客户端与适配器

    func testReadAllFromFake() async throws {
        let fake = FakeXTC()
        let client = XTCClient(transport: fake)
        let s = try await client.readAll()
        XCTAssertEqual(s.routing[.adat1], .madi(block: 0))
        XCTAssertEqual(s.routing[.adat2], .madi(block: 1))
        XCTAssertEqual(s.routing[.madi(block: 0)], .mic)
        XCTAssertEqual(s.sampleRate, 48_000)
        XCTAssertEqual(s.mics.count, 8)
        XCTAssertEqual(fake.received, [try XTCSysEx.request(.requestAll, device: 0)])
    }

    func testSilentDeviceTimesOut() async {
        let fake = FakeXTC(); fake.silent = true
        let client = XTCClient(transport: fake)
        do { _ = try await client.readAll(timeout: .milliseconds(200)); XCTFail() }
        catch { XCTAssertEqual(error as? XTCClient.ReadError, .noReply) }
    }

    func testOtherDeviceIDIgnored() async {
        let fake = FakeXTC(midiDeviceID: 3)
        let client = XTCClient(transport: fake, midiDeviceID: 0)
        let r = try? await client.readAll(timeout: .milliseconds(200))
        XCTAssertNil(r)
    }

    func testSnapshot() async throws {
        let adapter = XTCMIDIAdapter(client: XTCClient(transport: FakeXTC()), endpointName: "fake", controlEnabled: false)
        let snap = try await adapter.snapshot()
        XCTAssertEqual(snap.clock.configuredRate.knownValue, 48_000)
        XCTAssertEqual(snap.clock.source.knownValue, .port("xtc.madi.in"))
        XCTAssertEqual(snap.clock.lock["xtc.madi.in"]?.knownValue, true)
        XCTAssertEqual(snap.portFormats["xtc.madi.out"]?.knownValue, StreamFormat(sampleRate: 48_000, madiFrame: .frame48k, channelMode: .ch64))
        XCTAssertEqual(snap.routes.count, 8 * 10)    // 10 个输出块，来源都有登记端口
        XCTAssertTrue(snap.routes.contains { $0.source == ChannelRef("xtc.madi.in", 12) && $0.destination == ChannelRef("xtc.adat2.out", 4) })
        XCTAssertEqual(snap.preamps.map(\.input.channel), Array(1 ... 8))
        XCTAssertEqual(snap.preamps[0].gainDB.knownValue, 0)
        XCTAssertNil(snap.preamps[0].label.knownValue)
        XCTAssertEqual(snap.settings["xtc.adat1.out.1-8.source"]?.knownValue, "MADI 1–8")
        XCTAssertTrue(adapter.capabilities.filter { $0.name.hasPrefix("digital routing") }.allSatisfy { $0.access == .readOnly })
    }

    func testPlanIsManualUnlessControlEnabled() async throws {
        let fake = FakeXTC()
        let change = RouteChange(domain: .xtc, source: ChannelRef("xtc.madi.in", 17), destination: ChannelRef("xtc.madi.out", 25),
                                 kind: .blockAssign(size: 8))
        let off = XTCMIDIAdapter(client: XTCClient(transport: fake), endpointName: "fake", controlEnabled: false)
        let snap = try await off.snapshot()
        let ops = off.plan(change, current: snap)
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops[0].access, .manual)
        XCTAssertEqual(ops[0].parameter, "sysex/17/msb")
        XCTAssertEqual(ops[0].oldValue, "Mic 1–8")
        XCTAssertEqual(ops[0].newValue, "MADI 17–24")
        // 块内偏移变了的不计划。
        XCTAssertTrue(off.plan(RouteChange(domain: .xtc, source: ChannelRef("xtc.madi.in", 18), destination: ChannelRef("xtc.madi.out", 25),
                                           kind: .blockAssign(size: 8)), current: snap).isEmpty)

        let confirmation = await ConfirmationGate.userConfirmed(ops)
        do { try await off.apply(ops[0], confirmation: confirmation); XCTFail() }
        catch { XCTAssertEqual(error as? AdapterError, .notWritable("sysex/17/msb")) }
        XCTAssertEqual(fake.received.count, 1)     // 只有读取
    }

    func testApplyVerifyWhenEnabled() async throws {
        let fake = FakeXTC()
        let on = XTCMIDIAdapter(client: XTCClient(transport: fake), endpointName: "fake", controlEnabled: true)
        let change = RouteChange(domain: .xtc, source: ChannelRef("xtc.madi.in", 17), destination: ChannelRef("xtc.madi.out", 25),
                                 kind: .blockAssign(size: 8))
        let ops = on.plan(change, current: try await on.snapshot())
        XCTAssertEqual(ops[0].access, .readWrite)

        // 没有确认凭证覆盖：不发。
        let other = await ConfirmationGate.userConfirmed([])
        do { try await on.apply(ops[0], confirmation: other); XCTFail() } catch { XCTAssertEqual(error as? AdapterError, .notConfirmed) }
        XCTAssertEqual(fake.received.count, 1)

        let ok = await ConfirmationGate.userConfirmed(ops)
        try await on.apply(ops[0], confirmation: ok)
        XCTAssertEqual(fake.received.last, try XTCSysEx.set([.init(index: 17, lsb: 0, msb: 5, flags: 0x02)], device: 0))
        XCTAssertEqual(fake.value(17)?.msb, 5)
        XCTAssertEqual(fake.value(17)?.lsb, 0)     // 另一块不动
        let v = try await on.verify(ops[0])
        XCTAssertEqual(v, .matches)

        fake.ignoreSets = true
        let back = on.plan(RouteChange(domain: .xtc, source: ChannelRef("xtc.mic.in", 1), destination: ChannelRef("xtc.madi.out", 25),
                                       kind: .blockAssign(size: 8)), current: try await on.snapshot())
        try await on.apply(back[0], confirmation: await ConfirmationGate.userConfirmed(back))
        let v2 = try await on.verify(back[0])
        XCTAssertEqual(v2, .differs(readBack: "MADI 17–24"))
    }

    // MARK: CoreMIDI（系统虚拟端口当假 XTC）

    func testCoreMIDIWithVirtualEndpoints() async throws {
        let fake = FakeXTC()
        let tag = UUID().uuidString.prefix(6)
        let srcName = "RMETest XTC out \(tag)", dstName = "RMETest XTC in \(tag)"

        var client = MIDIClientRef()
        guard MIDIClientCreateWithBlock("RMETest fake XTC" as CFString, &client, nil) == noErr else {
            throw XCTSkip("CoreMIDI 不可用")
        }
        defer { MIDIClientDispose(client) }
        var srcRef = MIDIEndpointRef(), dst = MIDIEndpointRef()
        XCTAssertEqual(MIDISourceCreateWithProtocol(client, srcName as CFString, ._1_0, &srcRef), noErr)
        let src = srcRef
        // 假 XTC：从虚拟目的端收报文，交给 FakeXTC，回包从虚拟源端发出。
        let box = AssemblerBox()
        let reply: @Sendable ([UInt8]) -> Void = { bytes in
            _ = CoreMIDIXTCTransport.withEventList(UMPSysEx7.pack(bytes)) { MIDIReceivedEventList(src, $0) }
        }
        try await fake.start(onReceive: reply)
        XCTAssertEqual(MIDIDestinationCreateWithProtocol(client, dstName as CFString, ._1_0, &dst) { list, _ in
            for words in CoreMIDIXTCTransport.words(list) {
                for msg in box.feed(words) { Task { try? await fake.send(msg) } }
            }
        }, noErr)
        try await Task.sleep(for: .milliseconds(300))   // 等端点出现在系统列表里
        XCTAssertTrue(MIDIEndpoints.sources().contains(srcName))
        XCTAssertTrue(MIDIEndpoints.destinations().contains(dstName))

        let transport = CoreMIDIXTCTransport(sourceName: srcName, destinationName: dstName)
        let xtc = XTCClient(transport: transport)
        let s = try await xtc.readAll(timeout: .seconds(3))
        XCTAssertEqual(s.sampleRate, 48_000)
        XCTAssertEqual(s.routing[.adat2], .madi(block: 1))

        // 传输层自己也有闸门：危险报文发不出去。
        do { try await transport.send(XTCSysEx.set([.init(index: 25, lsb: 1, msb: 0, flags: 1)], device: 0)); XCTFail() }
        catch { XCTAssertEqual(error as? XTCSendGate.Rejection, .index(25)) }
        await xtc.stop()
    }

    func testMissingEndpoint() async {
        let t = CoreMIDIXTCTransport(sourceName: "不存在的端点", destinationName: "不存在的端点")
        do { try await t.start { _ in }; XCTFail() }
        catch { XCTAssertEqual(error as? XTCTransportError, .endpointNotFound("不存在的端点")) }
    }
}

final class AssemblerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var a = UMPSysEx7.Assembler()
    func feed(_ w: [UInt32]) -> [[UInt8]] { lock.withLock { a.feed(w) } }
}
