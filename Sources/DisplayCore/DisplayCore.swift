import Foundation
import CoreGraphics
import AppKit

public struct DisplayInfo: Identifiable, Hashable {
    public let id: CGDirectDisplayID
    public let name: String
    public let isBuiltin: Bool
    public let isMain: Bool
    public let isInMirrorSet: Bool
    public let mirrorsDisplay: CGDirectDisplayID   // kCGNullDirectDisplay 表示未镜像
    public let width: Int, height: Int             // 逻辑分辨率（点）
    public let pixelWidth: Int, pixelHeight: Int
    public let refreshRate: Double
}

public struct ModeInfo: Identifiable, Hashable {
    public let id: Int32            // CGDisplayMode.ioDisplayModeID
    public let width: Int, height: Int
    public let pixelWidth: Int, pixelHeight: Int
    public let refreshRate: Double
    public let isUsable: Bool
    public var isHiDPI: Bool { pixelWidth > width }
    public var label: String {
        var s = "\(width)×\(height)"
        if isHiDPI { s += " (HiDPI \(pixelWidth)×\(pixelHeight))" }
        s += " @ " + ModeInfo.hzText(refreshRate)
        return s
    }
}

public enum DisplayError: Error, CustomStringConvertible {
    case cg(String, CGError), notFound(CGDirectDisplayID), noExternal, noBuiltin, privateAPIUnavailable
    case rateUnavailable(Double, [Double])
    public var description: String {
        switch self {
        case .cg(let op, let e): return "\(op) 失败（CGError \(e.rawValue)）"
        case .notFound(let id): return "找不到显示器 \(id)"
        case .noExternal: return "未检测到外接显示器，为安全起见拒绝关闭内建屏"
        case .noBuiltin: return "未检测到内建显示器（可能已被关闭或处于合盖模式）"
        case .privateAPIUnavailable: return "私有 API CGSConfigureDisplayEnabled 不可用"
        case .rateUnavailable(let hz, let avail):
            let a = Array(Set(avail.map { ModeInfo.hzText($0) })).sorted().joined(separator: ", ")
            return "该分辨率下没有 \(ModeInfo.hzText(hz)) 模式（可用：\(a.isEmpty ? "无" : a)）"
        }
    }
}

public enum DisplayManager {
    // MARK: 列表
    public static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32); var n: UInt32 = 0
        guard CGGetOnlineDisplayList(32, &ids, &n) == .success else { return [] }
        return Array(ids.prefix(Int(n)))
    }

    public static func name(of id: CGDirectDisplayID) -> String {
        do {
            for s in NSScreen.screens {
                if let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                   n.uint32Value == id { return s.localizedName }
            }
        }
        return CGDisplayIsBuiltin(id) != 0 ? "内建显示器" : "显示器 \(id)"
    }

    public static func info(_ id: CGDirectDisplayID) -> DisplayInfo {
        let m = CGDisplayCopyDisplayMode(id)
        return DisplayInfo(id: id, name: name(of: id),
            isBuiltin: CGDisplayIsBuiltin(id) != 0, isMain: CGDisplayIsMain(id) != 0,
            isInMirrorSet: CGDisplayIsInMirrorSet(id) != 0, mirrorsDisplay: CGDisplayMirrorsDisplay(id),
            width: m?.width ?? CGDisplayPixelsWide(id), height: m?.height ?? CGDisplayPixelsHigh(id),
            pixelWidth: m?.pixelWidth ?? 0, pixelHeight: m?.pixelHeight ?? 0, refreshRate: m?.refreshRate ?? 0)
    }

    public static func displays() -> [DisplayInfo] { onlineDisplayIDs().map(info) }
    public static func builtin() -> DisplayInfo? { displays().first { $0.isBuiltin } }
    public static func externals() -> [DisplayInfo] { displays().filter { !$0.isBuiltin } }

    // MARK: 模式
    static func rawModes(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        return (CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode]) ?? []
    }
    static func toInfo(_ m: CGDisplayMode) -> ModeInfo {
        ModeInfo(id: m.ioDisplayModeID, width: m.width, height: m.height, pixelWidth: m.pixelWidth,
                 pixelHeight: m.pixelHeight, refreshRate: m.refreshRate, isUsable: m.isUsableForDesktopGUI())
    }
    public static func modes(_ id: CGDirectDisplayID, includeUnusable: Bool = false) -> [ModeInfo] {
        var seen = Set<String>()
        return rawModes(id).map(toInfo)
            .filter { includeUnusable || $0.isUsable }
            .filter { seen.insert("\($0.width)x\($0.height)x\($0.pixelWidth)x\(Int(($0.refreshRate * 100).rounded()))").inserted }
            .sorted { ($0.width, $0.height, $0.pixelWidth, $0.refreshRate) > ($1.width, $1.height, $1.pixelWidth, $1.refreshRate) }
    }
    public static func currentModeID(_ id: CGDirectDisplayID) -> Int32? { CGDisplayCopyDisplayMode(id)?.ioDisplayModeID }

    // MARK: 配置事务
    static func configure(_ op: String, permanent: Bool = true, _ body: (CGDisplayConfigRef?) throws -> CGError) throws {
        var cfg: CGDisplayConfigRef?
        var e = CGBeginDisplayConfiguration(&cfg)
        guard e == .success else { throw DisplayError.cg("CGBeginDisplayConfiguration", e) }
        do { e = try body(cfg) }
        catch { CGCancelDisplayConfiguration(cfg); throw error }
        guard e == .success else { CGCancelDisplayConfiguration(cfg); throw DisplayError.cg(op, e) }
        e = CGCompleteDisplayConfiguration(cfg, permanent ? .permanently : .forSession)
        guard e == .success else { throw DisplayError.cg("CGCompleteDisplayConfiguration", e) }
    }

    /// 设置分辨率模式（公开 API）
    public static func setMode(display id: CGDirectDisplayID, modeID: Int32, permanent: Bool = true, remember: Bool = true) throws {
        guard !DisplayTrial.isPending else { throw SafetyError.refused("请先确认或恢复内屏关闭测试，再调整模式") }
        guard let mode = rawModes(id).first(where: { $0.ioDisplayModeID == modeID }) else { throw DisplayError.notFound(id) }
        notifySelfChange()
        try configure("CGConfigureDisplayWithDisplayMode", permanent: permanent) { CGConfigureDisplayWithDisplayMode($0, id, mode, nil) }
        let expected = toInfo(mode)
        var actual = CGDisplayCopyDisplayMode(id).map(toInfo)
        for _ in 0..<15 {
            if let actual, actual.matches(expected) { break }
            Thread.sleep(forTimeInterval: 0.1)
            actual = CGDisplayCopyDisplayMode(id).map(toInfo)
        }
        guard let actual, actual.matches(expected) else {
            throw SafetyError.refused("驱动未应用请求的模式：请求 \(expected.label)，实际 \(actual?.label ?? "无法读取")；未保存此次请求")
        }
        if remember && CGDisplayIsBuiltin(id) == 0 { ModeMemory.save(display: id, mode: actual) }
    }

    // MARK: 已停用危险的镜像关闭入口，仅保留显式取消镜像用于恢复
    public static func mirrorBuiltinToExternal(external: CGDirectDisplayID? = nil) throws {
        throw SafetyError.refused("本机曾因镜像造成黑屏，已停用镜像关闭功能；请使用带自动恢复的关闭测试")
    }

    public static func stopMirroring() throws {
        notifySelfChange()
        try configure("CGConfigureDisplayMirrorOfDisplay(off)", permanent: false) { cfg in
            for d in displays() where d.mirrorsDisplay != kCGNullDirectDisplay {
                let e = CGConfigureDisplayMirrorOfDisplay(cfg, d.id, kCGNullDirectDisplay)
                if e != .success { return e }
            }
            return .success
        }
        if builtinState == .mirrored { builtinState = .enabled }
    }

    // MARK: 会话级逻辑停用（私有 API，需读回及实体确认）
    private typealias EnableFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    private static let enableFn: EnableFn? = {
        for path in ["/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                     "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"] {
            if let h = dlopen(path, RTLD_NOW), let s = dlsym(h, "CGSConfigureDisplayEnabled") {
                return unsafeBitCast(s, to: EnableFn.self)
            }
        }
        return nil
    }()
    public static var privateDisableAvailable: Bool { enableFn != nil }

    // MARK: 兼容旧偏好写入；状态读取以当前活动/镜像关系为准
    private static let idKey = "DisplayFocus.disabledBuiltinID"
    private static let stateKey = "DisplayFocus.builtinState"
    public static var builtinID: CGDirectDisplayID? {
        get { (Store.defaults.object(forKey: idKey) as? NSNumber)?.uint32Value }
        set { if let v = newValue { Store.defaults.set(NSNumber(value: v), forKey: idKey) } else { Store.defaults.removeObject(forKey: idKey) } }
    }
    @available(*, deprecated, renamed: "builtinID")
    public static var savedDisabledID: CGDirectDisplayID? { builtinState == .disabled ? builtinID : nil }
    public static var builtinState: BuiltinState {
        get {
            let panels = DisplaySafety.records().filter { $0.builtin }
            if panels.contains(where: { $0.mirror != 0 }) { return .mirrored }
            if panels.contains(where: { $0.active }) { return .enabled }
            if !panels.isEmpty { return .disabled }
            return .unknown
        }
        set { Store.defaults.set(newValue.rawValue, forKey: stateKey) }
    }

    /// Low-level operation is internal; all disabling goes through the independent recovery guard.
    static func configureEnabled(_ id: CGDirectDisplayID, _ on: Bool) throws {
        guard let fn = enableFn else { throw DisplayError.privateAPIUnavailable }
        notifySelfChange()
        try configure("CGSConfigureDisplayEnabled", permanent: false) { fn($0, id, on) }
    }
    public static func setEnabled(_ id: CGDirectDisplayID, _ on: Bool) throws {
        guard DisplaySafety.records().contains(where: { $0.id == id && $0.builtin }) else { throw DisplayError.noBuiltin }
        if on { try enableBuiltin() } else { try disableBuiltin() }
    }
    public static func disableBuiltin() throws {
        _ = try DisplayTrial.begin()
    }
    public static func enableBuiltin() throws {
        Store.defaults.removeObject(forKey: "DisplayFocus.confirmedDisable")
        let expected = DisplayTrial.recoveryBuiltinIdentity ??
            (try? DisplaySafety.recoveryPanel(DisplaySafety.records(), expectedIdentity: nil).identity)
        guard let identity = expected else { throw DisplayError.noBuiltin }
        let start = ProcessInfo.processInfo.systemUptime
        var nextRequest: TimeInterval = 0
        while ProcessInfo.processInfo.systemUptime - start < 20 {
            // Always resolve the current ID from the known panel UUID. During HDMI hotplug,
            // CGDisplayIsBuiltin can temporarily be true for a virtual copy of the external.
            if let panel = try? DisplaySafety.recoveryPanel(DisplaySafety.records(), expectedIdentity: identity) {
                if panel.usable && panel.mirror == 0 {
                    builtinID = panel.id; builtinState = .enabled; return
                }
                let now = ProcessInfo.processInfo.systemUptime
                if now >= nextRequest {
                    if panel.mirror != 0 { try stopMirroring() }
                    // Retry only this panel while WindowServer replaces temporary display IDs.
                    try? configureEnabled(panel.id, true)
                    nextRequest = ProcessInfo.processInfo.systemUptime + 3
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw SafetyError.refused("20秒内未确认指定内屏UUID恢复；没有使用主屏或临时外屏替代内屏")
    }
    public static func restoreBuiltin() throws {
        if DisplayTrial.hasManagedTicket { try DisplayTrial.revert(); return }
        try enableBuiltin()
    }
    /// No mirror fallback: failure must leave recoverable independent desktops.
    @discardableResult
    public static func turnOffBuiltinBestEffort() throws -> BuiltinState {
        try disableBuiltin()
        return builtinState
    }
    static func makeMain(_ id: UInt32) throws {
        let records = DisplaySafety.records()
        guard let target = records.first(where: { $0.id == id && !$0.builtin && $0.usable && $0.mirror == 0 }) else {
            throw DisplayError.noExternal
        }
        if target.main { return }
        notifySelfChange()
        try configure("设置外屏为主屏", permanent: false) { cfg in
            for d in records where d.active {
                let e = CGConfigureDisplayOrigin(cfg, d.id, d.x - target.x, d.y - target.y)
                if e != .success { return e }
            }
            return .success
        }
    }
    static func restoreSnapshot(_ before: [DisplayRecord]) throws {
        // Bring back the freshly identified builtin FIRST, even if the external was unplugged.
        try enableBuiltin()
        let now = DisplaySafety.records()
        notifySelfChange()
        try configure("恢复显示配置", permanent: false) { cfg in
            for old in before where old.active {
                guard let current = now.first(where: { $0.identity == old.identity }) else { continue }
                if CGDisplayIsInMirrorSet(current.id) != 0 {
                    let e = CGConfigureDisplayMirrorOfDisplay(cfg, current.id, kCGNullDirectDisplay)
                    if e != .success { return e }
                }
                if !old.sameMode(as: current) {
                    guard let mode = rawModes(current.id).first(where: { m in
                        m.width == old.width && m.height == old.height && m.pixelWidth == old.pixelWidth &&
                        m.pixelHeight == old.pixelHeight && abs(m.refreshRate - old.hz) < 0.5
                    }) else { throw SafetyError.refused("原模式已不可用，保留当前可用输出") }
                    let e = CGConfigureDisplayWithDisplayMode(cfg, current.id, mode, nil)
                    if e != .success { return e }
                }
                let e = CGConfigureDisplayOrigin(cfg, current.id, old.x, old.y)
                if e != .success { return e }
            }
            return .success
        }
        let restored = DisplaySafety.records()
        for old in before where old.active {
            // A physically unplugged external cannot be restored, but builtin must remain usable.
            guard let current = restored.first(where: { $0.identity == old.identity }) else {
                if old.builtin { throw DisplayError.noBuiltin }; continue
            }
            guard current.usable, old.sameMode(as: current), current.mirror == 0 else {
                throw SafetyError.refused("恢复请求后模式或活动状态不匹配，请检查实体画面")
            }
            let allPresent = before.filter(\.active).allSatisfy { old in restored.contains { $0.identity == old.identity } }
            if allPresent && (current.main != old.main || current.x != old.x || current.y != old.y) {
                throw SafetyError.refused("桌面布局未完全恢复，请检查主屏与排列")
            }
        }
        builtinState = .enabled
    }

    /// 通知自动模式：接下来的重新配置事件是我们自己触发的
    public static func notifySelfChange() {
        Store.defaults.set(Date().timeIntervalSince1970, forKey: "DisplayFocus.lastSelfChange")
    }
    public static var lastSelfChange: Date {
        Date(timeIntervalSince1970: Store.defaults.double(forKey: "DisplayFocus.lastSelfChange"))
    }
}

public enum BuiltinState: String, Sendable {
    case enabled, disabled, mirrored, unknown
    public var zh: String {
        switch self { case .enabled: return "开启"; case .disabled: return "逻辑停用"; case .mirrored: return "镜像中（屏幕仍点亮）"; case .unknown: return "状态未知" }
    }
}

extension ModeInfo {
    func matches(_ expected: ModeInfo) -> Bool {
        width == expected.width && height == expected.height && pixelWidth == expected.pixelWidth &&
        pixelHeight == expected.pixelHeight && abs(refreshRate - expected.refreshRate) < 0.5
    }
}
