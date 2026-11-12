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
            if newValue { AutomaticDisplayPolicy.resume() }
            _ = stability.observe(nil, now: ProcessInfo.processInfo.systemUptime)
            schedule(delay: 0.3)
        }
    }
    public func start() {
        guard !registered else { return }
        registered = true
        AutomaticDisplayPolicy.resume()
        notBefore = ProcessInfo.processInfo.systemUptime + 8
        lastMessage = "自动仅外屏已开启，等待显示器连接稳定"
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
            AutomaticDisplayPolicy.pause("显示器频繁变化，稍后自动重试")
            lastMessage = "显示器频繁变化，稍后自动重试"
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
        guard AutomaticDisplayPolicy.retryAllowed else {
            lastMessage = (AutomaticDisplayPolicy.retry?.reason ?? "显示器配置暂不可用") + "；稍后自动重试"
            _ = stability.observe(nil, now: now)
            return
        }
        if panelOff && DisplayTrial.hasManagedTicket && !DisplayTrial.guardianAlive {
            AutomaticDisplayPolicy.pause("连接监控已退出，恢复内屏后自动重试")
            do { try DisplayManager.restoreBuiltin(); lastMessage = "已恢复内屏，稍后自动重新连接" }
            catch { lastMessage = "监控退出，恢复内屏未确认：\(error)" }
            return
        }
        if !usableExternal && panelOff && !DisplayTrial.transactionPending {
            _ = stability.observe(nil, now: now)
            if allowAction() {
                do {
                    try DisplayManager.restoreBuiltin()
                    lastMessage = "外屏不可用，已恢复内屏；重新接入稳定后再自动关闭"
                } catch {
                    AutomaticDisplayPolicy.pause("恢复内屏未通过：\(error)")
                    lastMessage = "恢复内屏暂未完成，稍后自动重试：\(error)"
                }
            }
            return
        }
        if panelOff && usableExternal && DisplayTrial.isMonitoring {
            lastMessage = "已自动仅外屏，保持原分辨率与刷新率"
            return
        }
        guard enabled, !DisplayTrial.transactionPending, records.contains(where: { $0.builtin && $0.usable }) else {
            _ = stability.observe(nil, now: now)
            return
        }
        guard DisplayTrial.automaticAllowed else {
            _ = stability.observe(nil, now: now)
            lastMessage = usableExternal ? "等待可用的扩展桌面配置，随后自动关闭内屏" : "等待可用外屏，保留内屏"
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
            lastMessage = "已自动仅外屏，保持原分辨率与刷新率"
        } catch {
            AutomaticDisplayPolicy.pause("自动关闭失败：\(error)")
            try? DisplayTrial.revert()
            lastMessage = "自动关闭暂未完成，恢复后稍后自动重试：\(error)"
        }
        _ = stability.observe(nil, now: now)
    }
}
