import Foundation
import CoreAudio

/// 一个正在用某音频设备的程序（文档第 6.6 节）。
public struct AudioClient: Equatable, Hashable, Sendable {
    public var pid: Int32
    public var bundleID: String?
    public var input: Bool
    public var output: Bool

    public init(pid: Int32, bundleID: String?, input: Bool, output: Bool) {
        self.pid = pid; self.bundleID = bundleID; self.input = input; self.output = output
    }
}

/// Core Audio 读到的一个设备。
public struct AudioDeviceInfo: Equatable, Sendable {
    public var id: UInt32
    public var name: String
    /// USB / PCI / Thunderbolt / 其他（四字码原文）。
    public var transport: String
    public var sampleRate: Double?
    public var availableRates: [Double]
    public var inputs: Int
    public var outputs: Int
    public var running: Bool
    public var clients: [AudioClient]

    public init(id: UInt32, name: String, transport: String, sampleRate: Double?, availableRates: [Double],
                inputs: Int, outputs: Int, running: Bool, clients: [AudioClient]) {
        self.id = id; self.name = name; self.transport = transport; self.sampleRate = sampleRate
        self.availableRates = availableRates; self.inputs = inputs; self.outputs = outputs
        self.running = running; self.clients = clients
    }
}

public enum AudioSystemError: Error, Equatable {
    case notAllowed(Double)
    case coreAudio(Int32)
}

/// 本机音频系统（测试时换成假的）。
public protocol AudioSystem: Sendable {
    func device(nameContains: String) -> AudioDeviceInfo?
    func setSampleRate(_ rate: Double, device: UInt32) throws
}

/// 真的 Core Audio：只用公开属性（第 6.6 节）。
public struct CoreAudioSystem: AudioSystem {
    public init() {}

    private static func addr(_ s: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: s, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func ids(_ obj: AudioObjectID, _ s: AudioObjectPropertySelector) -> [AudioObjectID] {
        var a = addr(s); var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var out = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &out) == noErr else { return [] }
        return out
    }

    private static func string(_ obj: AudioObjectID, _ s: AudioObjectPropertySelector) -> String? {
        var a = addr(s)
        guard AudioObjectHasProperty(obj, &a) else { return nil }
        var v: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr, let v else { return nil }
        return v.takeRetainedValue() as String
    }

    private static func u32(_ obj: AudioObjectID, _ s: AudioObjectPropertySelector) -> UInt32? {
        var a = addr(s)
        guard AudioObjectHasProperty(obj, &a) else { return nil }
        var v: UInt32 = 0, size = UInt32(4)
        return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    private static func channels(_ dev: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
        var a = addr(kAudioDevicePropertyStreamConfiguration, scope); var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, raw) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func rate(_ dev: AudioObjectID) -> Double? {
        var a = addr(kAudioDevicePropertyNominalSampleRate); var v: Float64 = 0, size = UInt32(8)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    private static func availableRates(_ dev: AudioObjectID) -> [Double] {
        var a = addr(kAudioDevicePropertyAvailableNominalSampleRates); var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &ranges) == noErr else { return [] }
        return Array(Set(ranges.filter { $0.mMinimum == $0.mMaximum }.map(\.mMinimum))).sorted()
    }

    static func fourCC(_ v: UInt32) -> String {
        switch v {
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypePCI: return "PCIe"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        default: return String(bytes: [24, 16, 8, 0].map { UInt8((v >> $0) & 0xFF) }, encoding: .ascii) ?? "\(v)"
        }
    }

    public func device(nameContains needle: String) -> AudioDeviceInfo? {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard let dev = Self.ids(sys, kAudioHardwarePropertyDevices)
            .first(where: { (Self.string($0, kAudioObjectPropertyName) ?? "").contains(needle) }) else { return nil }
        let clients: [AudioClient] = Self.ids(sys, kAudioHardwarePropertyProcessObjectList).compactMap { p in
            guard Self.ids(p, kAudioProcessPropertyDevices).contains(dev) else { return nil }
            let input = Self.u32(p, kAudioProcessPropertyIsRunningInput) == 1
            let output = Self.u32(p, kAudioProcessPropertyIsRunningOutput) == 1
            guard input || output else { return nil }
            return AudioClient(pid: Int32(bitPattern: Self.u32(p, kAudioProcessPropertyPID) ?? 0),
                               bundleID: Self.string(p, kAudioProcessPropertyBundleID), input: input, output: output)
        }
        return AudioDeviceInfo(id: dev, name: Self.string(dev, kAudioObjectPropertyName) ?? needle,
                               transport: Self.u32(dev, kAudioDevicePropertyTransportType).map(Self.fourCC) ?? "?",
                               sampleRate: Self.rate(dev), availableRates: Self.availableRates(dev),
                               inputs: Self.channels(dev, kAudioObjectPropertyScopeInput),
                               outputs: Self.channels(dev, kAudioObjectPropertyScopeOutput),
                               running: Self.u32(dev, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1,
                               clients: clients)
    }

    public func setSampleRate(_ rate: Double, device: UInt32) throws {
        guard Self.availableRates(device).contains(rate) else { throw AudioSystemError.notAllowed(rate) }
        var a = Self.addr(kAudioDevicePropertyNominalSampleRate)
        var v = Float64(rate)
        let status = AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float64>.size), &v)
        if status != noErr { throw AudioSystemError.coreAudio(status) }
    }
}

/// 假的音频系统（测试用）。
public final class FakeAudioSystem: AudioSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var info: AudioDeviceInfo?
    public init(_ info: AudioDeviceInfo?) { self.info = info }
    public var current: AudioDeviceInfo? { lock.withLock { info } }
    public func device(nameContains: String) -> AudioDeviceInfo? { lock.withLock { info } }
    public func setSampleRate(_ rate: Double, device: UInt32) throws {
        try lock.withLock {
            guard let i = info, i.availableRates.contains(rate) else { throw AudioSystemError.notAllowed(rate) }
            info?.sampleRate = rate
        }
    }
}
