import Foundation

/// 登录时启动：管理 ~/Library/LaunchAgents/com.holmes.displayfocus.plist
/// Runs the installed app itself, so launchd can observe crashes instead of only observing `open`.
public enum LoginAgent {
    public static let label = "com.holmes.displayfocus"

    public static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    public static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    /// 从 .app 运行时用当前路径，否则（如 CLI）默认 /Applications/DisplayFocus.app
    public static var appPath: String {
        let b = Bundle.main.bundlePath
        return b.hasSuffix(".app") ? b : "/Applications/DisplayFocus.app"
    }
    private static var domain: String { "gui/\(getuid())" }

    /// 写入 plist 并 bootstrap；返回非致命警告（文件已写入，下次登录仍会生效）
    @discardableResult
    public static func enable() throws -> String? {
        let dir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [appPath + "/Contents/MacOS/DisplayFocus"],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "KeepAlive": ["Crashed": true],
            "ThrottleInterval": 30,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
        Proc.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])          // 已加载则先卸载，忽略错误
        let r = Proc.run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
        return r.status == 0 ? nil : "launchctl bootstrap 返回 \(r.status)：\(r.output)（文件已写入，下次登录生效）"
    }

    public static func disable() throws {
        Proc.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
        if isInstalled { try FileManager.default.removeItem(at: plistURL) }
    }
}
