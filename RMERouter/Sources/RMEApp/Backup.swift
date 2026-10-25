import Foundation
import SwiftUI
import UniformTypeIdentifiers
import RMECore

/// 设置备份（阶段 D3）：连接设置、确认方式、接线、场景，一个 JSON 文件。换电脑时导出再导入。
public struct SettingsBackup: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var exportedAt: Date
    public var osc: OSCSettings
    public var twelveMicURL: String
    public var confirmMode: String
    public var links: [RMECore.Link]
    public var scenes: [StudioScene]
    /// XTC 连接设置（旧备份没有这一项）。
    public var xtc: XTCSettings?
}

public struct ImportSummary: Equatable, Sendable {
    public var linksImported: Int
    public var linksDropped: [String]
    public var scenesAdded: Int
    public var scenesUpdated: Int

    public var text: String {
        var parts = ["已导入连接设置与确认方式", "接线 \(linksImported) 根"]
        if !linksDropped.isEmpty { parts.append("跳过 \(linksDropped.count) 根（端口不存在：\(linksDropped.joined(separator: "、"))）") }
        parts.append("场景新增 \(scenesAdded) 个、更新 \(scenesUpdated) 个")
        return parts.joined(separator: "；")
    }
}

public enum BackupError: Error, Equatable {
    case unreadable
    case newerVersion(Int)

    public var text: String {
        switch self {
        case .unreadable: return "这个文件不是 RME Router 的备份，或者已经损坏"
        case let .newerVersion(v): return "备份来自更新版本的 RME Router（格式 \(v)），请先升级 App"
        }
    }
}

extension AppModel {
    static let backupEncoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }()
    static let backupDecoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    public func makeBackup() -> SettingsBackup {
        SettingsBackup(version: SettingsBackup.currentVersion,
                       exportedAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
                       osc: settings, twelveMicURL: twelveMicURL, confirmMode: confirmMode.rawValue,
                       links: links, scenes: scenes, xtc: xtcSettings)
    }

    public func exportBackup() throws -> Data { try Self.backupEncoder.encode(makeBackup()) }

    /// 导入备份：设置与接线替换；端口不存在的线跳过；场景按 id 合并。
    @discardableResult
    public func importBackup(_ data: Data) throws -> ImportSummary {
        guard let backup = try? Self.backupDecoder.decode(SettingsBackup.self, from: data) else { throw BackupError.unreadable }
        guard backup.version <= SettingsBackup.currentVersion else { throw BackupError.newerVersion(backup.version) }

        settings = backup.osc
        twelveMicURL = backup.twelveMicURL
        confirmMode = ConfirmMode(rawValue: backup.confirmMode) ?? .always
        if var x = backup.xtc {
            // 端点与读取开关照搬；“允许改动”和 Aux Device 确认不从文件恢复，要在这台电脑上重新确认。
            x.auxDeviceOff = false
            x.writeEnabled = false
            xtcSettings = x
        }

        let topo = snapshot.topology
        let valid = backup.links.filter { topo.port($0.from) != nil && topo.port($0.to) != nil }
        let dropped = backup.links.filter { topo.port($0.from) == nil || topo.port($0.to) == nil }.map { "\($0.from) ⇒ \($0.to)" }
        setLinks(valid)

        var added = 0, updated = 0
        for scene in backup.scenes {
            if let i = scenes.firstIndex(where: { $0.id == scene.id }) { scenes[i] = scene; updated += 1 }
            else { scenes.append(scene); added += 1 }
            sceneStore.save(scene)
        }
        scenes.sort { $0.date > $1.date }
        return ImportSummary(linksImported: valid.count, linksDropped: dropped, scenesAdded: added, scenesUpdated: updated)
    }
}

/// 给 SwiftUI 的 fileExporter / fileImporter 用的文档类型。
public struct BackupDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.json] }
    public var data: Data

    public init(data: Data) { self.data = data }

    public init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents else { throw BackupError.unreadable }
        data = d
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
