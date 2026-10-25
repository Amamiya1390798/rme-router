import XCTest
@testable import RMECore
@testable import RMEEngine
@testable import RMEAdapters
@testable import RMEApp

/// XTC 接入 App（文档第 6.3 节“App 接入”）。全部对 FakeXTC，不碰真实设备。
@MainActor
final class XTCAppTests: XCTestCase {
    var fake: FakeXTC!

    func makeModel() -> AppModel {
        let fake = FakeXTC()
        self.fake = fake
        let defaults = UserDefaults(suiteName: "xtc-\(UUID())")!
        return AppModel(defaults: defaults,
                        makeTwelveMic: { TwelveMicJSONAdapter(baseURL: $0, session: Self.offlineSession) },
                        makeXTC: { s in
                            XTCMIDIAdapter(client: XTCClient(transport: fake, midiDeviceID: s.midiDeviceID),
                                           endpointName: s.destinationName, controlEnabled: s.canWrite)
                        })
    }

    static let offlineSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [WriteTests.No12Mic.self]
        return URLSession(configuration: c)
    }()

    func enableRead(_ m: AppModel) {
        m.xtcSettings.sourceName = "XTC out"
        m.xtcSettings.destinationName = "XTC in"
        m.xtcSettings.readEnabled = true
    }

    func enableWrite(_ m: AppModel) {
        m.xtcSettings.auxDeviceOff = true
        m.xtcSettings.writeEnabled = true
    }

    func testDefaultSendsNothingToXTC() async {
        let m = makeModel()
        await m.refreshXTC()
        XCTAssertEqual(m.xtcStatus, .off)
        XCTAssertTrue(fake.received.isEmpty)
        XCTAssertTrue(m.isDemo("xtc"))
        XCTAssertEqual(m.snapshot.capabilities.first { $0.deviceID == "xtc" }?.access, .manual)
        // 没选端点不能打开读取：模型层也不发。
        m.xtcSettings.readEnabled = true
        await m.refreshXTC()
        if case .unreachable = m.xtcStatus {} else { XCTFail("\(m.xtcStatus)") }
        XCTAssertTrue(fake.received.isEmpty)
    }

    func testReadOnlyShowsRealDataButStaysManual() async throws {
        let m = makeModel()
        enableRead(m)
        await m.refreshXTC()
        XCTAssertEqual(m.xtcStatus, .live)
        XCTAssertFalse(m.isDemo("xtc"))
        XCTAssertEqual(fake.received, [try XTCSysEx.request(.requestAll, device: 0)])
        let xtc = try XCTUnwrap(m.snapshot.devices["xtc"])
        XCTAssertEqual(xtc.clock.configuredRate.knownValue, 48_000)
        XCTAssertEqual(xtc.preamps.count, 8)
        XCTAssertTrue(xtc.routes.contains { $0.source == ChannelRef("xtc.madi.in", 9) && $0.destination == ChannelRef("xtc.adat2.out", 1) })
        XCTAssertEqual(m.snapshot.capabilities.first { $0.deviceID == "xtc" }?.access, .manual)
        XCTAssertFalse(m.xtcWritable)

        XCTAssertEqual(m.stagePreamp(deviceID: "xtc", input: ChannelRef("xtc.mic.in", 1), field: .gain, value: .gain(20)),
                       .notConnected("XTC（未允许本 App 改动）"))
        XCTAssertNotNil(m.stageXTCRoute(destination: ChannelRef("xtc.madi.out", 25), source: ChannelRef("xtc.madi.in", 17)))
        XCTAssertFalse(m.hasPending)

        // 没确认 Aux Device：登记为可能在控制。
        XCTAssertEqual(xtc.controlPaths.first { $0.controller == "totalmix-aux" }?.active, true)
        XCTAssertEqual(xtc.controlPaths.first { $0.controller == "this-app" }?.active, false)
        let r9 = R9ControlPaths().evaluate(m.snapshot).first { $0.subject == "OctaMic XTC" }
        XCTAssertEqual(r9?.verdict, .pass)
    }

    func testWriteNeedsAuxConfirmation() async {
        let m = makeModel()
        enableRead(m)
        m.xtcSettings.writeEnabled = true          // 没勾 Aux Device 确认：打不开
        XCTAssertFalse(m.xtcSettings.writeEnabled)
        await m.refreshXTC()
        XCTAssertFalse(m.xtcWritable)
        enableWrite(m)
        await m.refreshXTC()
        XCTAssertTrue(m.xtcWritable)
        XCTAssertEqual(m.snapshot.capabilities.first { $0.deviceID == "xtc" }?.access, .readWrite)
    }

    func testSendAcrossBecomesAutomaticAndApplies() async throws {
        let m = makeModel()
        enableRead(m); enableWrite(m)
        await m.refreshXTC()

        guard case let .found(plans) = SendAcross.plan(m.snapshot, from: ChannelRef("xtc.madi.in", 19), to: ChannelRef("xtc.madi.out", 27))
        else { return XCTFail("没有路径") }
        XCTAssertTrue(plans[0].manualSteps.isEmpty)
        XCTAssertEqual(plans[0].autoCount, 1)
        XCTAssertEqual(m.stageSendPlan(plans), [])
        XCTAssertTrue(m.manualTasks.isEmpty)
        XCTAssertEqual(m.pendingXTCRoutes.count, 1)
        let r = m.pendingXTCRoutes[0]
        XCTAssertEqual(r.destination, ChannelRef("xtc.madi.out", 25))
        XCTAssertEqual(r.source, ChannelRef("xtc.madi.in", 17))
        XCTAssertEqual(r.changeText, "Mic 1–8 → MADI 17–24")
        XCTAssertEqual(r.wireText, "SysEx：F0 00 20 0D 69 00 20 11 00 05 02 F7")
        XCTAssertEqual(fake.received.count, 1)     // 暂存不发送

        let applied = await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
        let batch = try XCTUnwrap(applied)
        XCTAssertEqual(batch.outcomes[r.id], .verified)
        XCTAssertEqual(fake.value(17)?.msb, 5)
        XCTAssertFalse(m.hasPending)
        XCTAssertEqual(m.xtcSource(ofBlock: ChannelRef("xtc.madi.out", 25)), ChannelRef("xtc.madi.in", 17))

        // 撤销：旧来源回到待应用，仍需确认。
        m.stageUndo(batch)
        XCTAssertEqual(m.pendingXTCRoutes.first?.source, ChannelRef("xtc.mic.in", 1))
        _ = await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
        XCTAssertEqual(fake.value(17)?.msb, 0)
    }

    func testMismatchWhenXTCIgnoresWrite() async throws {
        let m = makeModel()
        enableRead(m); enableWrite(m)
        await m.refreshXTC()
        fake.ignoreSets = true
        m.stageXTCRoute(destination: ChannelRef("xtc.adat1.out", 3), source: ChannelRef("xtc.mic.in", 5))
        let id = try XCTUnwrap(m.pendingXTCRoutes.first?.id)
        let applied = await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
        let batch = try XCTUnwrap(applied)
        XCTAssertEqual(batch.outcomes[id], .mismatchValue(readBack: "MADI 1–8"))
    }

    func testPreampWrite() async throws {
        let m = makeModel()
        enableRead(m); enableWrite(m)
        await m.refreshXTC()
        let mic3 = ChannelRef("xtc.mic.in", 3)
        XCTAssertNil(m.stagePreamp(deviceID: "xtc", input: mic3, field: .gain, value: .gain(4)))
        XCTAssertEqual(m.pendingPreamps.first?.new, .gain(10))       // 1–9 dB 按 10 dB
        XCTAssertEqual(m.pendingPreamps.first?.wireText, "SysEx：F0 00 20 0D 69 00 20 02 01 00 01 F7")
        XCTAssertNil(m.stagePreamp(deviceID: "xtc", input: mic3, field: .phantom, value: .flag(true)))
        XCTAssertTrue(m.needsExplicitConfirmation)                     // 打开 48V
        XCTAssertNil(m.stagePreamp(deviceID: "xtc", input: mic3, field: .gain, value: .gain(80)))
        XCTAssertEqual(m.pendingPreamps.first { $0.field == .gain }?.new, .gain(60))   // 限 60 dB

        let applied = await m.applyPending(confirmation: ConfirmationGate.userConfirmed(m.allPendingOperations))
        let batch = try XCTUnwrap(applied)
        XCTAssertEqual(batch.verifiedCount, 2)
        XCTAssertEqual(fake.value(2)?.lsb, 51)          // 60 dB
        XCTAssertEqual(fake.value(2)?.msb, 0x04)        // 48V
        XCTAssertEqual(m.snapshot.devices["xtc"]?.preamps[2].gainDB.knownValue, 60)
    }

    func testTurningOffWriteDropsPendingAndCapability() async {
        let m = makeModel()
        enableRead(m); enableWrite(m)
        await m.refreshXTC()
        m.stageXTCRoute(destination: ChannelRef("xtc.madi.out", 25), source: ChannelRef("xtc.madi.in", 17))
        m.stagePreamp(deviceID: "xtc", input: ChannelRef("xtc.mic.in", 1), field: .phase, value: .flag(true))
        XCTAssertEqual(m.pendingCount, 2)
        m.xtcSettings.auxDeviceOff = false
        XCTAssertFalse(m.xtcSettings.writeEnabled)     // 前提没了，开关一并关掉
        XCTAssertFalse(m.xtcWritable)
        XCTAssertEqual(m.pendingCount, 0)
        XCTAssertEqual(m.snapshot.capabilities.first { $0.deviceID == "xtc" }?.access, .manual)

        // 关掉读取：回到演示数据。
        m.xtcSettings.readEnabled = false
        XCTAssertEqual(m.xtcStatus, .off)
        XCTAssertTrue(m.isDemo("xtc"))
    }

    func testCapabilitySurvivesXTRefresh() async {
        let m = makeModel()
        enableRead(m); enableWrite(m)
        await m.refreshXTC()
        m.apply(xt: StudioSetup.emptyXT(reason: "测试"))
        XCTAssertEqual(m.snapshot.capabilities.first { $0.deviceID == "xtc" }?.access, .readWrite)
    }

    func testBackupDoesNotRestoreWritePermission() async throws {
        let m = makeModel()
        enableRead(m); enableWrite(m)
        m.xtcSettings.midiDeviceID = 2
        let data = try m.exportBackup()
        let other = makeModel()
        try other.importBackup(data)
        XCTAssertEqual(other.xtcSettings.destinationName, "XTC in")
        XCTAssertEqual(other.xtcSettings.midiDeviceID, 2)
        XCTAssertTrue(other.xtcSettings.readEnabled)
        XCTAssertFalse(other.xtcSettings.auxDeviceOff)
        XCTAssertFalse(other.xtcSettings.writeEnabled)
    }
}
