import SwiftUI
import AppKit
import CoreGraphics
import DisplayCore

@MainActor
final class Model: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var selected: CGDirectDisplayID?
    @Published var groups: [ResolutionGroup] = []
    @Published var current: ModeInfo?
    @Published var message = ""
    @Published var builtinState: BuiltinState = .enabled
    @Published var autoOn = false
    @Published var loginOn = false
    @Published var scales: [ScaleOption] = []
    @Published var native: (width: Int, height: Int) = (0, 0)
    @Published var hidpiInstalled = false
    @Published var light = LightSetting(scene: .day)
    @Published var allScales: [ScaleOption] = []     // 全部缩放选项（无 HiDPI 时用于“普通分辨率”）
    @Published var lastAuto = ""
    @Published var textSizeGlobal = "DEFAULT"
    @Published var trialSeconds = 0
    @Published var trialPending = false
    private var recoveryTimer: Timer?
    private var tokens: [NSObjectProtocol] = []

    init() {
        refresh()
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let wasPending = self.trialPending
                self.trialPending = DisplayTrial.isPending
                self.trialSeconds = DisplayTrial.secondsLeft
                if wasPending && !self.trialPending {
                    self.message = DisplayTrial.lastDetail
                    self.refresh()
                }
            }
        }
        for name in [NSApplication.didChangeScreenParametersNotification, AutoController.changedNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        // CLI 修改了调光设置 → 由本进程应用（gamma 修改在进程退出时会被系统还原）
        tokens.append(DistributedNotificationCenter.default().addObserver(forName: SoftwareLight.changedDistributed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in SoftwareLight.reapplyAll(); self?.loadModes() }
        })
        // 唤醒后系统会重置 gamma
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            tokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    SoftwareLight.reapplyAll()
                }
            })
        }
        AutoController.shared.start()
        SoftwareLight.reapplyAll()
    }
    func refresh() {
        displays = DisplayManager.displays()
        builtinState = DisplayManager.builtinState
        autoOn = AutoController.shared.enabled
        loginOn = LoginAgent.isInstalled
        lastAuto = AutoController.shared.lastMessage
        textSizeGlobal = TextSize.currentGlobal()
        if !lastAuto.isEmpty && message.isEmpty { message = lastAuto }
        if selected == nil || !displays.contains(where: { $0.id == selected }) {
            selected = displays.first(where: { !$0.isBuiltin })?.id ?? displays.first?.id
        }
        loadModes()
    }
    func loadModes() {
        groups = selected.map { DisplayManager.resolutionGroups($0) } ?? []
        current = selected.flatMap(DisplayManager.currentMode)
        if let id = selected {
            let n = DisplayManager.nativeSize(id)
            native = n
            // 只显示 HiDPI 档位，外加原生分辨率（方便切回）
            allScales = DisplayManager.scaleOptions(id)
            scales = allScales.filter { $0.hiDPI || ($0.width == n.width && $0.height == n.height) }
            hidpiInstalled = HiDPIOverride.isInstalled(id)
            light = SoftwareLight.setting(for: id)
        } else { scales = []; allScales = []; hidpiInstalled = false }
    }

    // MARK: 系统文字大小
    func setTextSize(_ value: String) {
        if TextSize.setGlobal(value) {
            message = "已写入系统文字大小 · 部分 App 需重新打开才生效"
        } else {
            message = "写入系统文字大小失败，请在系统设置中手动调整"
        }
        textSizeGlobal = TextSize.currentGlobal()
    }
    func openTextSizeSettings() { TextSize.openSystemSettings() }

    // MARK: UI 辅助
    func select(_ id: CGDirectDisplayID) { selected = id; loadModes() }
    var selectedDisplay: DisplayInfo? { displays.first { $0.id == selected } }
    var hasHiDPI: Bool { scales.contains { $0.hiDPI } }
    /// 有 HiDPI 时：HiDPI + 原生；否则：全部普通分辨率
    var visibleScales: [ScaleOption] { hasHiDPI ? scales : allScales.filter { !$0.hiDPI } }
    var headerSubtitle: String {
        guard let d = selectedDisplay else { return "未检测到显示器" }
        var parts = [d.isBuiltin ? "内建显示器" : "外接显示器"]
        if let c = current {
            parts.append("\(c.width)×\(c.height)")
            parts.append(ModeInfo.hzText(c.refreshRate))
        }
        return parts.joined(separator: " · ")
    }
    var statusLine: String {
        let b: String
        switch builtinState { case .enabled: b = "内建屏开启"; case .disabled: b = "内建屏逻辑停用"; case .mirrored: b = "内建屏镜像中"; case .unknown: b = "内建屏状态未知" }
        return "\(b) · 自动模式\(autoOn ? "开" : "关")"
    }
    var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "开发版"
    }
    var selectedIsBuiltin: Bool { displays.first { $0.id == selected }?.isBuiltin ?? true }
    var selectedName: String { displays.first { $0.id == selected }?.name ?? "Display" }
    func isCurrentScale(_ o: ScaleOption) -> Bool {
        guard let c = current else { return false }
        return c.width == o.width && c.height == o.height && c.isHiDPI == o.hiDPI
    }
    func applyScale(_ o: ScaleOption) {
        guard let id = selected else { return }
        act("已切换到\(o.label)") { try DisplayManager.setScale(display: id, width: o.width, height: o.height, hiDPI: o.hiDPI) }
    }
    func installHiDPI() {
        guard let id = selected else { return }
        let name = selectedName
        act("已写入 HiDPI 设置：\(HiDPIOverride.filePath(id))。请重新插拔显示器或注销/重启后生效") {
            try HiDPIOverride.install(id, name: name, via: .appleScript)
        }
    }
    func removeHiDPI() {
        guard let id = selected else { return }
        act("已移除 HiDPI 设置。请重新插拔显示器或注销/重启后生效") { try HiDPIOverride.remove(id, via: .appleScript) }
    }
    var currentGroup: ResolutionGroup? {
        guard let c = current else { return nil }
        return groups.first { $0.modes.contains(c) }
    }
    func apply(_ mode: ModeInfo) {
        guard let id = selected else { return }
        act("已切换到 \(mode.label)") { try DisplayManager.setMode(display: id, modeID: mode.id) }
    }
    func setAuto(_ on: Bool) { AutoController.shared.enabled = on; autoOn = on; message = on ? "已开启登录/接屏自动模式；\(AutomaticDisplayPolicy.status)" : "自动模式已关闭" }
    func setLogin(_ on: Bool) {
        do {
            if on {
                let warn = try LoginAgent.enable()
                message = warn ?? "已设置登录时启动（\(LoginAgent.plistURL.path)）"
            } else {
                try LoginAgent.disable()
                message = "已取消登录时启动"
            }
        } catch { message = "登录启动设置失败：\(error.localizedDescription)" }
        loginOn = LoginAgent.isInstalled
    }
    // MARK: 软件调光 / 色温
    func applyScene(_ sc: LightScene) {
        guard let id = selected else { return }
        do { light = try SoftwareLight.applyScene(id, sc); message = "已应用场景：\(sc.zh)" }
        catch { message = "错误：\(error)" }
    }
    func setBrightness(_ v: Int) {
        guard let id = selected, v != light.brightness else { return }
        do { light = try SoftwareLight.update(id, brightness: v) } catch { message = "错误：\(error)" }
    }
    func setTemperature(_ v: Int) {
        guard let id = selected, v != light.temperature else { return }
        do { light = try SoftwareLight.update(id, temperature: v) } catch { message = "错误：\(error)" }
    }
    func resetLight() {
        guard let id = selected else { return }
        light = SoftwareLight.reset(id)
        message = "已恢复软件调整"
    }
    var canTestDisable: Bool {
        !trialPending && DisplayManager.privateDisableAvailable && DisplaySafety.records().contains { !$0.builtin && $0.usable && $0.mirror == 0 }
    }
    func testDisable() {
        do {
            try DisplayManager.disableBuiltin()
            trialPending = true; trialSeconds = DisplayTrial.secondsLeft
            message = "请确认外屏显示和鼠标操作正常；25 秒未确认将尝试恢复"
        } catch { message = "关闭测试失败：\(error)" }
        refresh()
    }
    func confirmDisable() {
        do { try DisplayTrial.confirm(); message = DisplayTrial.lastDetail }
        catch { try? DisplayTrial.revert(); message = "未保留：\(error)" }
        trialPending = DisplayTrial.isPending; refresh()
    }
    func recoverDisplay() {
        AutoController.shared.enabled = false // manual recovery must not immediately close it again
        do {
            try DisplayManager.restoreBuiltin()
            message = "内屏已逻辑启用，请确认实体画面可操作"
        } catch { message = "恢复失败：\(error)" }
        trialPending = DisplayTrial.isPending; refresh()
    }
    func act(_ ok: String, _ f: () throws -> Void) {
        do { try f(); message = ok } catch { message = "错误：\(error)" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }
}

