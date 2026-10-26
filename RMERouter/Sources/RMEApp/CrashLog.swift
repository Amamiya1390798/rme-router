import Foundation
import AppKit

/// 闪退诊断（2026-10-26）：崩溃时把信号与调用栈写进 ~/Library/Logs/RME Router/crash-<时间>.log；
/// 启动、退出、窗口关闭各记一行到 session.log。只写本机文件，不上传。
public enum CrashLog {
    static let directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/RME Router", isDirectory: true)

    public static func install() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        note("启动 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?")（\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?")）")
        NSSetUncaughtExceptionHandler { e in
            CrashLog.writeCrash("未捕获的异常 \(e.name.rawValue)：\(e.reason ?? "")", stack: e.callStackSymbols)
        }
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGTRAP, SIGILL, SIGFPE] {
            signal(sig) { s in
                CrashLog.writeCrash("信号 \(s)（\(String(cString: strsignal(s)))）", stack: Thread.callStackSymbols)
                signal(s, SIG_DFL)   // 交回系统，照常生成崩溃报告
                raise(s)
            }
        }
        // 被别的进程结束（例如打包脚本 pkill）：记一行，好和真闪退区分
        signal(SIGTERM) { _ in
            CrashLog.note("被结束（SIGTERM）")
            exit(0)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { n in
            let w = n.object as? NSWindow
            let others = NSApp.windows.filter { $0 !== w && $0.isVisible }.map { String(describing: type(of: $0)) }
            CrashLog.note("窗口关闭：\(String(describing: w.map { type(of: $0) })) 「\(w?.title ?? "")」 id=\(w?.identifier?.rawValue ?? "-")；还开着 \(others)")
        }
    }

    public static func note(_ line: String) {
        let url = directory.appendingPathComponent("session.log")
        let text = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }

    static func writeCrash(_ reason: String, stack: [String]) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let text = ([reason, ""] + stack).joined(separator: "\n")
        try? Data(text.utf8).write(to: directory.appendingPathComponent("crash-\(stamp).log"))
        note("崩溃：\(reason)")
    }
}
