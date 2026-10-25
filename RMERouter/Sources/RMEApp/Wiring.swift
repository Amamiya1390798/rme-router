import Foundation
import RMECore

/// 接线表编辑（阶段 A4）。改动立即存盘，信号流、体检、时钟、跨设备送声都用同一张表。
extension AppModel {
    public var links: [Link] { snapshot.topology.links }

    /// 接线表校验结果（接口类型不符、MADI 缺回程、接头需转接等）。
    public var linkIssues: [String: [LinkIssue]] {
        Dictionary(grouping: snapshot.topology.validate(), by: \.link.id).mapValues { $0.map(\.issue) }
    }

    /// 可以作为线缆起点的端口（所有输出口）与终点（所有输入口），按拓扑顺序。
    public var wiringOutputs: [RMECore.Port] { snapshot.topology.devices.flatMap(\.ports).filter { $0.direction == .output } }
    public var wiringInputs: [RMECore.Port] { snapshot.topology.devices.flatMap(\.ports).filter { $0.direction == .input } }

    /// 加一根线。返回错误说明；nil 表示已加入并存盘。
    @discardableResult
    public func addLink(from: String, to: String) -> String? {
        let topo = snapshot.topology
        guard let a = topo.port(from), a.direction == .output else { return "起点必须是输出口" }
        guard let b = topo.port(to), b.direction == .input else { return "终点必须是输入口" }
        guard a.deviceID != b.deviceID else { return "不能把设备接回自己" }
        guard a.type.canConnect(to: b.type) else { return LinkIssue.mediumMismatch(a.type, b.type).description }
        if let existing = topo.links(into: to).first {
            return "\(b.name) 已经接了 \(topo.port(existing.from)?.name ?? existing.from)；一个输入口只能接一根线，先删掉原来的"
        }
        if topo.links(from: from).contains(where: { $0.to == to }) { return "这根线已经有了" }
        var links = topo.links
        links.append(Link(id: nextLinkID(links), from: from, to: to))
        setLinks(links)
        return nil
    }

    public func removeLink(_ id: String) {
        setLinks(snapshot.topology.links.filter { $0.id != id })
    }

    /// 恢复默认接线（删掉存盘文件）。
    public func resetLinks() {
        linkStore.save(nil)
        var t = snapshot.topology
        t.links = StudioSetup.topology().links
        replaceTopology(t)
    }

    /// 接线是否与默认不同。
    public var linksCustomized: Bool { Set(links) != Set(StudioSetup.topology().links) }

    func setLinks(_ links: [Link]) {
        var t = snapshot.topology
        t.links = links
        replaceTopology(t)
        linkStore.save(links)
    }

    func replaceTopology(_ t: Topology) {
        snapshot = SystemSnapshot(topology: t, devices: snapshot.devices, capabilities: snapshot.capabilities,
                                  terminals: snapshot.terminals, concurrency: snapshot.concurrency,
                                  expectations: snapshot.expectations, auxDeviceFirstChannel: snapshot.auxDeviceFirstChannel)
    }

    func nextLinkID(_ links: [Link]) -> String {
        let used = Set(links.map(\.id))
        var n = links.count + 1
        while used.contains("L\(n)") { n += 1 }
        return "L\(n)"
    }
}
