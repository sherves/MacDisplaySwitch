import Foundation

struct DisplayStabilityGate {
    private var signature: String?
    private var since: TimeInterval = 0
    mutating func observe(_ candidate: String?, now: TimeInterval, interval: TimeInterval = 4) -> Bool {
        guard let candidate else { signature = nil; return false }
        if signature != candidate { signature = candidate; since = now; return false }
        return now - since >= interval
    }
}

struct AutomaticRetryState: Codable {
    let boot: String
    let until: TimeInterval
    let reason: String
    func ready(boot currentBoot: String, uptime: TimeInterval) -> Bool {
        boot != currentBoot || uptime >= until
    }
}

/// Automatic use depends on live displays, never a driver hash or a saved confirmation.
public enum AutomaticDisplayPolicy {
    private static let retryKey = "DisplayFocus.automaticRetry.v2"
    static func allows(_ records: [DisplayRecord]) -> Bool {
        (try? DisplaySafety.targets(records)) != nil
    }
    public static var status: String {
        Store.autoEnabled ? "持续自动仅外屏；登录后自动执行，驱动更新无需确认" : "本次临时恢复内屏；重新启动应用或登录后自动仅外屏"
    }
    static var retry: AutomaticRetryState? {
        guard let data = Store.defaults.data(forKey: retryKey) else { return nil }
        return try? JSONDecoder().decode(AutomaticRetryState.self, from: data)
    }
    static var retryAllowed: Bool {
        retry?.ready(boot: DisplayTrial.bootIdentity, uptime: ProcessInfo.processInfo.systemUptime) ?? true
    }
    public static func resume() {
        Store.autoEnabled = true
        for key in [retryKey, "DisplayFocus.autoPauseReason", "DisplayFocus.automaticProfile.v1"] {
            Store.defaults.removeObject(forKey: key)
        }
    }
    /// Brief backoff for a failed transaction. The user's automatic preference stays enabled.
    static func pause(_ reason: String) {
        let state = AutomaticRetryState(boot: DisplayTrial.bootIdentity,
            until: ProcessInfo.processInfo.systemUptime + 60, reason: reason)
        if let data = try? JSONEncoder().encode(state) { Store.defaults.set(data, forKey: retryKey) }
    }
}
