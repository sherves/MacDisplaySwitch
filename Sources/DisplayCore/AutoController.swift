import Foundation
import CoreGraphics

/// Login and hotplug automation never restores a stored mode or uses mirroring.
@MainActor
public final class AutoController {
    public static let shared = AutoController()
    public static let changedNotification = Notification.Name("DisplayFocus.stateChanged")
    public private(set) var lastMessage = ""
    private var registered = false
    private var pending: Task<Void, Never>?
    private var poll: Timer?
    private var stability = DisplayStabilityGate()
    private var notBefore: TimeInterval = 0
    private var actionsInWindow: [TimeInterval] = []
    private init() {}
    public var enabled: Bool {
        get { Store.autoEnabled }
        set {
            Store.autoEnabled = newValue
            if newValue { Store.defaults.removeObject(forKey: "DisplayFocus.autoPauseReason") }
            _ = stability.observe(nil, now: ProcessInfo.processInfo.systemUptime)
            schedule(delay: 0.3)
        }
    }
    public func start() {
        guard !registered else { return }
        registered = true
        notBefore = ProcessInfo.processInfo.systemUptime + 8
        lastMessage = Store.defaults.string(forKey: "DisplayFocus.autoPauseReason") ?? ""
        let err = CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            if flags.contains(.beginConfigurationFlag) { return }
            Task { @MainActor in
                SoftwareLight.reapplyAll()
                AutoController.shared.schedule()
            }
        }, nil)
        if err != .success { lastMessage = "显示器回调不可用，使用定时检查（\(err.rawValue)）" }
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in AutoController.shared.evaluate() }
        }
        schedule(delay: 0.5)
    }
    public func schedule(delay: Double = 1.5) {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }
    private func allowAction() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        actionsInWindow = actionsInWindow.filter { now - $0 < 60 }
        guard actionsInWindow.count < 6 else {
            AutomaticDisplayPolicy.pause("自动操作过于频繁，已暂停；请检查显示器后重新开启")
            lastMessage = "自动操作过于频繁，已暂停"
            return false
        }
        actionsInWindow.append(now)
        return true
    }
    public func evaluate() {
        let now = ProcessInfo.processInfo.systemUptime
        let records = DisplaySafety.records()
        let usableExternal = records.contains { !$0.builtin && $0.usable && $0.mirror == 0 }
        let panelOff = records.contains { $0.builtin && !$0.active }
        defer { NotificationCenter.default.post(name: Self.changedNotification, object: nil) }
        if panelOff && DisplayTrial.hasManagedTicket && !DisplayTrial.guardianAlive {
            AutomaticDisplayPolicy.pause("独立恢复监控已退出，自动模式暂停并恢复内屏")
            do { try DisplayManager.restoreBuiltin(); lastMessage = "监控退出，已恢复内屏并暂停自动模式" }
            catch { lastMessage = "监控退出，恢复内屏未确认：\(error)" }
            return
        }
        if !usableExternal && panelOff && !DisplayTrial.isPending {
            _ = stability.observe(nil, now: now)
            if let reason = Store.defaults.string(forKey: "DisplayFocus.autoPauseReason"), !reason.isEmpty {
                lastMessage = reason
                return
            }
            if allowAction() {
                do {
                    try DisplayManager.restoreBuiltin()
                    lastMessage = "外屏不可用，已恢复内屏；重新接入稳定后再自动关闭"
                } catch {
                    AutomaticDisplayPolicy.pause("恢复内屏未通过：\(error)")
                    lastMessage = "恢复内屏未通过，自动模式已暂停：\(error)"
                }
            }
            return
        }
        guard enabled, !DisplayTrial.isPending, records.contains(where: { $0.builtin && $0.usable }) else {
            _ = stability.observe(nil, now: now)
            return
        }
        guard DisplayTrial.automaticAllowed else {
            _ = stability.observe(nil, now: now)
            lastMessage = usableExternal ? "请先为当前外屏/模式测试关闭内屏并确认一次；以后登录和重连自动执行" : "等待可用外屏，保留内屏"
            return
        }
        let signature = records.sorted { $0.identity < $1.identity }.map {
            "\($0.identity):\($0.active):\($0.online):\($0.asleep):\($0.main):\($0.mirror):\($0.width)x\($0.height):\($0.pixelWidth)x\($0.pixelHeight):\($0.hz):\($0.x),\($0.y)"
        }.joined(separator: "|")
        guard stability.observe(signature, now: now), now >= notBefore else {
            lastMessage = "等待外屏连接与桌面配置稳定，保持当前刷新率"
            return
        }
        guard allowAction() else { return }
        do {
            _ = try DisplayTrial.begin(automatic: true)
            try DisplayTrial.confirmAutomatically()
            lastMessage = "已自动停用内屏；外屏原模式与刷新率通过读回，独立恢复监控运行中"
        } catch {
            AutomaticDisplayPolicy.pause("自动关闭失败：\(error)")
            try? DisplayTrial.revert()
            lastMessage = "自动关闭失败，已暂停重试并请求恢复：\(error)"
        }
        _ = stability.observe(nil, now: now)
    }
}
