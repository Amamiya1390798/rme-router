import Foundation

public enum OSCWriteMode: Sendable { case readOnly, readWrite }

public enum OSCGateError: Error, Equatable {
    /// 安全规则 2：不带值的地址会被 TotalMix 当成写 1.0。
    case missingValue(String)
    /// 触发命令的值小于 0.5 会被忽略，说明调用方写错了。
    case triggerValueTooLow(String)
    /// 安全规则 3：只读模式下出现写入类地址。
    case writeInReadOnlyMode(String)
    /// 写入没有覆盖该操作的用户确认，或操作不可写。
    case writeNotConfirmed(String)
}

/// 发往 TotalMix 的每条消息都要经过这里（文档第 7 节安全规则 2、3）。
public struct OSCSendGate: Sendable {
    public var mode: OSCWriteMode

    public init(mode: OSCWriteMode = .readOnly) {
        self.mode = mode
    }

    static let requestAddresses: Set<String> = ["/sendall", "/sendsettings", "/sendmix", "/sendstate"]
    static let requestPrefixes = ["/sendchan/input/", "/sendchan/playback/", "/sendchan/output/", "/sendsubmix/"]

    /// 是否为只读请求地址（白名单）。前缀类地址后面必须正好是一个非负整数。
    public static func isRequest(_ address: String) -> Bool {
        if requestAddresses.contains(address) { return true }
        for prefix in requestPrefixes where address.hasPrefix(prefix) {
            let rest = address.dropFirst(prefix.count)
            return !rest.isEmpty && rest.allSatisfy(\.isASCII) && rest.allSatisfy(\.isNumber)
        }
        return false
    }

    /// 只读请求的检查。
    public func check(_ message: OSCMessage) throws {
        guard let value = message.arguments.first else { throw OSCGateError.missingValue(message.address) }
        guard Self.isRequest(message.address) else { throw OSCGateError.writeInReadOnlyMode(message.address) }
        guard let v = value.number, v >= 0.5 else { throw OSCGateError.triggerValueTooLow(message.address) }
    }

    /// 写入类消息的检查：读写模式 + 用户确认覆盖该操作 + 操作可写。
    public func checkWrite(_ message: OSCMessage, for operation: PlannedOperation,
                           confirmation: UserConfirmation) throws {
        guard !message.arguments.isEmpty else { throw OSCGateError.missingValue(message.address) }
        guard mode == .readWrite else { throw OSCGateError.writeInReadOnlyMode(message.address) }
        guard confirmation.covers(operation), operation.access == .readWrite else {
            throw OSCGateError.writeNotConfirmed(message.address)
        }
    }
}
