import Foundation
import CoreGraphics
import ColorSync
import Darwin

/// Snapshot and verification use actual WindowServer state, never the saved UI flag.
public struct DisplayRecord: Codable, Equatable {
    public let identity: String
    public let id: UInt32
    public let builtin: Bool
    public let active: Bool
    public let online: Bool
    public let asleep: Bool
    public let main: Bool
    public let mirror: UInt32
    public let x: Int32, y: Int32
    public let width: Int, height: Int, pixelWidth: Int, pixelHeight: Int
    public let hz: Double
    public var synthetic: Bool? = nil // older tickets/profiles omit this field

    public var usable: Bool { synthetic != true && online && active && !asleep && width > 1 && height > 1 && pixelWidth > 1 && pixelHeight > 1 }
    public func sameMode(as other: DisplayRecord) -> Bool {
        width == other.width && height == other.height && pixelWidth == other.pixelWidth &&
        pixelHeight == other.pixelHeight && abs(hz - other.hz) < 0.5
    }
}

public enum SafetyError: Error, CustomStringConvertible {
    case refused(String)
    public var description: String { switch self { case .refused(let text): return text } }
}

public enum DisplaySafety {
    typealias ListFn = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> CGError
    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    private static let listFn: ListFn? = handle.flatMap { dlsym($0, "CGSGetDisplayList") }.map { unsafeBitCast($0, to: ListFn.self) }

    public static func allIDs() -> [UInt32] {
        var ids = [UInt32](repeating: 0, count: 64), count: UInt32 = 0
        if let fn = listFn, fn(64, &ids, &count) == .success { return Array(ids.prefix(Int(count))) }
        return DisplayManager.onlineDisplayIDs()
    }
    public static func identity(_ id: UInt32) -> String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            let text = CFUUIDCreateString(nil, uuid) as String
            if text != "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF" { return text }
        }
        return "\(CGDisplayIsBuiltin(id) != 0)-\(ModeMemory.displayKey(id))"
    }
    public static func records() -> [DisplayRecord] {
        var result: [DisplayRecord] = []
        let expectedBuiltin = DisplayTrial.recoveryBuiltinIdentity
        for id in allIDs() {
            let vendor = CGDisplayVendorNumber(id), model = CGDisplayModelNumber(id)
            // CGS also exposes inactive 1x1 placeholders with all-ones IDs/UUIDs; these are not physical outputs.
            if (vendor == 0 && model == 0) || vendor == UInt32.max || model == UInt32.max { continue }
            let mode = CGDisplayCopyDisplayMode(id)
            let bounds = CGDisplayBounds(id)
            let stableIdentity = identity(id)
            // Headless fallback temporarily labels every output builtin. Do not reclassify the
            // saved external as the panel or accept anonymous virtual 1x1 placeholders.
            if stableIdentity.hasPrefix("true-1970170734-") || stableIdentity.hasPrefix("false-1970170734-") { continue }
            let record = DisplayRecord(identity: stableIdentity, id: id,
                builtin: expectedBuiltin.map { stableIdentity == $0 } ?? (CGDisplayIsBuiltin(id) != 0), active: CGDisplayIsActive(id) != 0,
                online: CGDisplayIsOnline(id) != 0, asleep: CGDisplayIsAsleep(id) != 0,
                main: CGDisplayIsMain(id) != 0, mirror: CGDisplayMirrorsDisplay(id),
                x: Int32(bounds.origin.x), y: Int32(bounds.origin.y),
                width: mode?.width ?? 0, height: mode?.height ?? 0,
                pixelWidth: mode?.pixelWidth ?? 0, pixelHeight: mode?.pixelHeight ?? 0,
                hz: mode?.refreshRate ?? 0, synthetic: vendor == 1970170734 && model == 1986622068)
            result.append(record)
        }
        return result
    }
    static func recoveryPanel(_ records: [DisplayRecord], expectedIdentity: String?) throws -> DisplayRecord {
        let candidates: [DisplayRecord]
        if let identity = expectedIdentity { candidates = records.filter { $0.identity == identity } }
        else { candidates = records.filter { $0.builtin } }
        guard candidates.count == 1 else { throw SafetyError.refused("内屏身份缺失或不唯一，不使用主屏/第一项作为恢复目标") }
        return candidates[0]
    }
    /// Refuse mirrored/ambiguous/offline outputs rather than treating an online ghost as a recovery screen.
    static func targets(_ records: [DisplayRecord]) throws -> (DisplayRecord, DisplayRecord) {
        guard let builtin = records.first(where: { $0.builtin && $0.usable }) else {
            throw SafetyError.refused("未找到正在工作的内屏，请先恢复内屏后再试")
        }
        let external = records.filter { !$0.builtin && $0.usable && $0.mirror == 0 }
        guard let keep = external.first(where: { $0.main }) ?? external.first else {
            throw SafetyError.refused("没有已识别且正在工作的外屏；已接线但未识别也不能关闭内屏")
        }
        guard records.allSatisfy({ $0.mirror == 0 }) else {
            throw SafetyError.refused("当前存在镜像关系；请先恢复扩展桌面，不自动切换镜像")
        }
        guard Set(records.map(\.identity)).count == records.count else {
            throw SafetyError.refused("显示器身份重复，无法安全选择关闭及恢复对象")
        }
        return (builtin, keep)
    }
    static func validateExternal(_ before: [DisplayRecord], external: String, now: [DisplayRecord]) throws {
        guard let original = before.first(where: { $0.identity == external }),
              let current = now.first(where: { $0.identity == external }), current.usable, current.main,
              current.mirror == 0, current.sameMode(as: original) else {
            throw SafetyError.refused("外屏不再是可用主屏，或分辨率/刷新率发生变化，正在恢复原配置")
        }
        for old in before where old.usable && !old.builtin {
            guard let cur = now.first(where: { $0.identity == old.identity }), cur.usable,
                  cur.mirror == 0, cur.sameMode(as: old) else {
                throw SafetyError.refused("外接输出状态变化，正在恢复原配置")
            }
        }
    }
    static func validateDisabled(_ before: [DisplayRecord], builtin: String, external: String, now: [DisplayRecord]) throws {
        try validateExternal(before, external: external, now: now)
        if let panel = now.first(where: { $0.identity == builtin }), panel.active {
            throw SafetyError.refused("驱动未停用内屏：请求已返回，但内屏仍在活动；不会改用镜像")
        }
    }
}

/// A separate CLI process owns the recovery deadline, so closing/crashing the menu app cannot cancel it.
/// It cannot recover a hung kernel/WindowServer. A successful readback is not proof of physical scan-out.
public enum DisplayTrial {
    struct Ticket: Codable {
        let token: String
        let boot: String
        let before: [DisplayRecord]
        let builtin: String
        let external: String
        let deadline: TimeInterval // monotonic uptime, shared across processes
        var changed: Bool
        var state: String
        var detail: String
        var automatic: Bool? = nil // optional so older recovery tickets remain readable
    }
    #if DISPLAYFOCUS_FIXTURES
    static var recoveryFolderOverride: URL?
    #endif
    private static var folder: URL {
        #if DISPLAYFOCUS_FIXTURES
        if let override = recoveryFolderOverride { return override }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DisplayFocus/Recovery")
    }
    private static var ticketURL: URL { folder.appendingPathComponent("trial.json") }
    private static var lockURL: URL { folder.appendingPathComponent("trial.lock") }
    public static var isPending: Bool {
        guard let t = try? read() else { return false }
        return t.boot == bootIdentity && t.state == "armed"
    }
    public static var secondsLeft: Int {
        guard let t = try? read(), t.boot == bootIdentity, t.state == "armed" else { return 0 }
        return max(0, Int(ceil(t.deadline - ProcessInfo.processInfo.systemUptime)))
    }
    public static var isMonitoring: Bool {
        guard let t = try? read() else { return false }
        return t.boot == bootIdentity && t.state == "monitoring" && guardianAlive
    }
    static var hasManagedTicket: Bool {
        guard let t = try? read() else { return false }
        return t.boot == bootIdentity && ["armed", "monitoring"].contains(t.state)
    }
    static var guardianAlive: Bool {
        guard let t = try? read(), t.boot == bootIdentity,
              let text = try? String(contentsOf: folder.appendingPathComponent(t.token + ".ready"), encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else { return false }
        return kill(pid, 0) == 0
    }
    public static var lastDetail: String { (try? read())?.detail ?? "" }
    static var recoveryBuiltinIdentity: String? {
        guard let t = try? read(), t.boot == bootIdentity,
              t.before.contains(where: { $0.builtin && $0.identity == t.builtin }) else { return nil }
        return t.builtin
    }

    private static func prepareFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }
    private static func read() throws -> Ticket { try JSONDecoder().decode(Ticket.self, from: Data(contentsOf: ticketURL)) }
    private static func write(_ t: Ticket) throws {
        try JSONEncoder().encode(t).write(to: ticketURL, options: .atomic)
    }
    private static func locked<T>(_ body: () throws -> T) throws -> T {
        try prepareFolder()
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw SafetyError.refused("无法建立切屏恢复锁") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw SafetyError.refused("无法锁定切屏恢复记录") }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
    private static var helper: URL {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        if exe.lastPathComponent == "displayfocus" || exe.lastPathComponent == "DisplayFocusRecovery" { return exe }
        return exe.deletingLastPathComponent().appendingPathComponent("DisplayFocusRecovery")
    }
    @discardableResult
    public static func begin(automatic: Bool = false) throws -> String {
        let before = DisplaySafety.records()
        let (builtin, external) = try DisplaySafety.targets(before)
        if automatic && !AutomaticDisplayPolicy.allows(before) {
            throw SafetyError.refused("当前外屏、模式或驱动未经确认，未执行自动关闭")
        }
        guard DisplayManager.privateDisableAvailable else { throw DisplayError.privateAPIUnavailable }
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw SafetyError.refused("独立恢复程序缺失，拒绝关闭内屏；请使用完整安装包")
        }
        let token = UUID().uuidString
        try locked {
            if let old = try? read(), old.boot == bootIdentity, old.state == "armed" { throw SafetyError.refused("已有切屏测试正在进行，请先保留或恢复") }
            try write(Ticket(token: token, boot: bootIdentity, before: before, builtin: builtin.identity, external: external.identity,
                deadline: ProcessInfo.processInfo.systemUptime + 25, changed: false, state: "armed", detail: "等待确认：未确认将自动恢复", automatic: automatic))
        }
        let ready = folder.appendingPathComponent("\(token).ready")
        let process = Process()
        process.executableURL = helper
        process.arguments = ["recovery-watchdog", token]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            for _ in 0..<40 {
                if FileManager.default.fileExists(atPath: ready.path) { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            guard FileManager.default.fileExists(atPath: ready.path), process.isRunning else {
                throw SafetyError.refused("独立恢复程序未就绪，未执行关闭操作")
            }
            try locked {
                var t = try read()
                guard t.boot == bootIdentity, t.token == token, t.state == "armed", t.deadline > ProcessInfo.processInfo.systemUptime else {
                    throw SafetyError.refused("切屏保护已过期，请重试")
                }
                let fresh = DisplaySafety.records()
                let (freshBuiltin, freshExternal) = try DisplaySafety.targets(fresh)
                guard freshBuiltin.identity == builtin.identity, freshExternal.identity == external.identity,
                      freshExternal.sameMode(as: external) else { throw SafetyError.refused("显示器连接或模式已变化，已取消") }
                t.changed = true
                try write(t) // persisted BEFORE touching WindowServer
                // Establish the external as main without touching its mode or refresh rate, then verify it BEFORE disabling.
                try DisplayManager.makeMain(freshExternal.id)
                try DisplaySafety.validateExternal(before, external: external.identity, now: DisplaySafety.records())
                try DisplayManager.configureEnabled(freshBuiltin.id, false)
                for _ in 0..<15 {
                    if CGDisplayIsActive(freshBuiltin.id) == 0 { break }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                try DisplaySafety.validateDisabled(before, builtin: builtin.identity, external: external.identity, now: DisplaySafety.records())
            }
            return token
        } catch {
            // Even an API error may follow a partially applied change.
            try? revert(token: token)
            throw error
        }
    }
    public static func confirm() throws {
        try locked {
            var t = try read()
            // A delayed UI/chat response must not bypass the watchdog deadline. If it already
            // restored successfully, remember the physically confirmed profile WITHOUT changing
            // displays; automation will perform a fresh, independently protected transaction.
            if canRememberRestoredTest(t, boot: bootIdentity, uptime: ProcessInfo.processInfo.systemUptime) {
                let now = DisplaySafety.records()
                let targets = try DisplaySafety.targets(now)
                guard targets.0.identity == t.builtin, targets.1.identity == t.external,
                      let ext = t.before.first(where: { $0.identity == t.external }), targets.1.sameMode(as: ext) else {
                    throw SafetyError.refused("测试后的外屏配置已变化，请重新测试")
                }
                try AutomaticDisplayPolicy.remember(builtin: t.builtin, external: ext)
                t.detail = "已收到对此次测试的确认；配置已记住，超时恢复不撤销；自动模式将另做受保护切换"
                try write(t)
                return
            }
            guard t.boot == bootIdentity, t.state == "armed", ProcessInfo.processInfo.systemUptime < t.deadline else {
                throw SafetyError.refused("确认已超时或配置已恢复，请重新测试")
            }
            try DisplaySafety.validateDisabled(t.before, builtin: t.builtin, external: t.external, now: DisplaySafety.records())
            guard let external = t.before.first(where: { $0.identity == t.external }) else {
                throw SafetyError.refused("确认记录缺少外屏身份")
            }
            try AutomaticDisplayPolicy.remember(builtin: t.builtin, external: external)
            t.state = "monitoring"; t.detail = "用户已确认外屏可操作；已记住此模式，独立监控外屏失联；背光以目视为准"
            try write(t)
            DisplayManager.builtinState = .disabled
            Store.defaults.set(bootIdentity + ":" + t.external, forKey: "DisplayFocus.confirmedDisable")
        }
    }
    static func canRememberRestoredTest(_ t: Ticket, boot: String, uptime: TimeInterval) -> Bool {
        t.boot == boot && t.state == "restored" && t.changed && t.automatic != true &&
            t.detail == "已恢复切换前的显示配置" && uptime >= t.deadline && uptime - t.deadline <= 300
    }
    public static var automaticAllowed: Bool {
        AutomaticDisplayPolicy.allows(DisplaySafety.records())
    }
    /// Automatic readback is deliberately not recorded as a new human confirmation.
    public static func confirmAutomatically() throws {
        try locked {
            var t = try read()
            guard t.boot == bootIdentity, t.state == "armed", t.automatic == true,
                  Store.autoEnabled, AutomaticDisplayPolicy.allows(t.before),
                  ProcessInfo.processInfo.systemUptime < t.deadline else {
                throw SafetyError.refused("自动关闭授权不再匹配，恢复内屏")
            }
            try DisplaySafety.validateDisabled(t.before, builtin: t.builtin, external: t.external, now: DisplaySafety.records())
            t.state = "monitoring"; t.detail = "依据已确认的外屏配置自动关闭；状态读回通过，外屏失联监控中"
            try write(t)
            DisplayManager.builtinState = .disabled
        }
    }
    static let bootIdentity: String = {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1 else { return UUID().uuidString }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &value, &size, nil, 0) == 0 else { return UUID().uuidString }
        return String(cString: value)
    }()
    public static func revert(token: String? = nil) throws {
        try locked {
            guard var t = try? read(), t.boot == bootIdentity, token == nil || t.token == token else { return }
            guard t.state == "armed" || t.state == "monitoring" || (token == nil && t.state == "confirmed") else { return }
            let monitoring = t.state == "monitoring"
            if t.automatic == true && !monitoring {
                AutomaticDisplayPolicy.pause("自动关闭未完成确认或保护期限已到；已暂停自动重试")
            }
            // Clear any previous authorization before recovery, preventing automatic retry loops.
            if t.changed { Store.defaults.removeObject(forKey: "DisplayFocus.confirmedDisable") }
            do {
                if t.changed {
                    // After confirmation, users may have moved windows or changed modes. Restore only
                    // the builtin on external loss, without replaying the old external layout/mode.
                    if monitoring { try DisplayManager.enableBuiltin() }
                    else { try DisplayManager.restoreSnapshot(t.before) }
                }
                t.state = "restored"; t.detail = "已恢复切换前的显示配置"
            } catch {
                if t.changed { AutomaticDisplayPolicy.pause("恢复内屏未能确认，请检查实体显示后手动重新开启自动模式") }
                t.state = "recoveryFailed"; t.detail = "自动恢复未能确认：\(error)"
                try write(t)
                throw error
            }
            try write(t)
        }
    }
    static func shouldRecover(deadline: TimeInterval, uptime: TimeInterval,
                              before: [DisplayRecord], external: String, now: [DisplayRecord]) -> Bool {
        guard uptime < deadline, let old = before.first(where: { $0.identity == external }),
              let current = now.first(where: { $0.identity == external }), current.usable,
              current.mirror == 0, current.sameMode(as: old) else { return true }
        return false
    }
    static func monitoringShouldRecover(external: String, now: [DisplayRecord]) -> Bool {
        let matches = now.filter { $0.identity == external }
        return matches.count != 1 || !matches[0].usable || matches[0].mirror != 0
    }
    /// Only the bundled helper calls this. No display mutation occurs before the deadline or a detected failure.
    public static func watchdog(token: String) throws {
        try locked {
            let t = try read()
            guard t.boot == bootIdentity, t.token == token, ["armed", "monitoring"].contains(t.state) else { throw SafetyError.refused("恢复票据不匹配") }
        }
        let ready = folder.appendingPathComponent("\(token).ready")
        try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: ready)
        defer { try? FileManager.default.removeItem(at: ready) }
        while true {
            let t = try locked { try read() }
            guard t.boot == bootIdentity, t.token == token, ["armed", "monitoring"].contains(t.state) else { return }
            if t.state == "monitoring" {
                if monitoringShouldRecover(external: t.external, now: DisplaySafety.records()) {
                    try revert(token: token); return
                }
                Thread.sleep(forTimeInterval: 1)
                continue
            }
            if shouldRecover(deadline: t.deadline, uptime: ProcessInfo.processInfo.systemUptime,
                             before: t.before, external: t.external, now: DisplaySafety.records()) {
                try revert(token: token); return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }
}
