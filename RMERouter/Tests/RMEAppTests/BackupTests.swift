import XCTest
@testable import RMECore
@testable import RMEApp

/// 设置备份（阶段 D3）：导出 → 导入到另一个 App → 一致；坏文件、新版本、端口不存在的线。
@MainActor
final class BackupTests: XCTestCase {
    var dirs: [URL] = []

    override func tearDown() { dirs.forEach { try? FileManager.default.removeItem(at: $0) } }

    func makeModel() -> AppModel {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("rme-backup-\(UUID())")
        dirs.append(d)
        return AppModel(defaults: UserDefaults(suiteName: "rme.backup.\(UUID())")!,
                        linkStore: LinkStore(url: d.appendingPathComponent("links.json")),
                        sceneStore: SceneStore(directory: d.appendingPathComponent("scenes")))
    }

    func sampleScene() -> StudioScene {
        StudioScene(id: UUID(), name: "排练", date: Date(timeIntervalSince1970: 1_800_000_000), devices: ["xt"],
                    sends: [.init(source: ChannelRef("xt.mic.in", 1), destination: ChannelRef("xt.phones.out", 1), dB: -6)],
                    preamps: [], routes: [])
    }

    func testRoundTrip() throws {
        let a = makeModel()
        a.settings.port = 7001
        a.twelveMicURL = "http://172.20.0.1"
        a.confirmMode = .quick
        a.addLink(from: "xtc.adat2.out", to: "p16i.adat_b.in")
        a.scenes = [sampleScene()]
        let data = try a.exportBackup()

        let b = makeModel()
        let summary = try b.importBackup(data)
        XCTAssertEqual(b.settings.port, 7001)
        XCTAssertEqual(b.twelveMicURL, "http://172.20.0.1")
        XCTAssertEqual(b.confirmMode, .quick)
        XCTAssertEqual(Set(b.links), Set(a.links))
        XCTAssertEqual(b.scenes, a.scenes)
        XCTAssertEqual(summary.scenesAdded, 1)
        XCTAssertEqual(summary.linksDropped, [])
        // 存盘了：重新打开 b 的存储也能读到
        XCTAssertEqual(b.sceneStore.load(), a.scenes)

        // 再导入一次：场景按 id 更新，不重复
        XCTAssertEqual(try b.importBackup(data).scenesUpdated, 1)
        XCTAssertEqual(b.scenes.count, 1)
    }

    func testDropsLinksToUnknownPorts() throws {
        let a = makeModel()
        var backup = a.makeBackup()
        backup.links.append(Link(id: "X", from: "nope.out", to: "xt.madi3.in"))
        let data = try AppModel.backupEncoder.encode(backup)
        let summary = try makeModel().importBackup(data)
        XCTAssertEqual(summary.linksDropped, ["nope.out ⇒ xt.madi3.in"])
        XCTAssertEqual(summary.linksImported, a.links.count)
    }

    func testRejectsGarbageAndNewerVersion() throws {
        let m = makeModel()
        XCTAssertThrowsError(try m.importBackup(Data("不是 JSON".utf8))) { XCTAssertEqual($0 as? BackupError, .unreadable) }
        var backup = m.makeBackup()
        backup.version = 99
        XCTAssertThrowsError(try m.importBackup(try AppModel.backupEncoder.encode(backup))) {
            XCTAssertEqual($0 as? BackupError, .newerVersion(99))
        }
    }
}
