import Foundation
import CoreGraphics
import AppKit

// MARK: - 场景

public enum LightScene: String, CaseIterable, Codable, Sendable {
    case day, read, movie, night

    public var zh: String {
        switch self { case .day: return "日间"; case .read: return "阅读"; case .movie: return "观影"; case .night: return "夜间" }
    }
    /// 软件调光 0–100
    public var brightness: Int {
        switch self { case .day: return 100; case .read: return 85; case .movie: return 70; case .night: return 50 }
    }
    /// 色温 0（冷）– 50（标准）– 100（暖）
    public var temperature: Int {
        switch self { case .day: return 50; case .read: return 75; case .movie: return 62; case .night: return 90 }
    }
    /// 接受 day/read/movie/night 或 日间/阅读/观影/夜间
    public init?(arg: String) {
        let s = arg.lowercased()
        if let v = LightScene(rawValue: s) { self = v; return }
        guard let v = LightScene.allCases.first(where: { $0.zh == arg }) else { return nil }
        self = v
    }
}

public struct LightSetting: Codable, Equatable, Sendable {
    public var brightness: Int = 100
    public var temperature: Int = 50
    public var scene: LightScene? = nil
    public init(brightness: Int = 100, temperature: Int = 50, scene: LightScene? = nil) {
        self.brightness = brightness; self.temperature = temperature; self.scene = scene
    }
    public var isNeutral: Bool { brightness >= 100 && temperature == 50 }
    public var temperatureLabel: String {
        temperature < 40 ? "偏冷(\(temperature))" : (temperature > 60 ? "偏暖(\(temperature))" : "标准(\(temperature))")
    }
    public var summary: String { "软件调光 \(brightness)% · 色温 \(temperatureLabel) · 场景 \(scene?.zh ?? "自定义")" }
}

public enum LightError: Error, CustomStringConvertible {
    case cg(String, CGError), noGammaTable(CGDirectDisplayID)
    public var description: String {
        switch self {
        case .cg(let op, let e): return "\(op) 失败（CGError \(e.rawValue)）"
        case .noGammaTable(let id): return "显示器 \(id) 不支持 gamma 表"
        }
    }
}

// MARK: - 软件调光 / 色温（公开 CoreGraphics gamma API）

public enum SoftwareLight {
    /// 低于该值按该值处理，避免整屏全黑无法操作
    public static let minEffective = 10
    public struct TempPreset: Hashable, Sendable { public let name: String; public let value: Int }
    public static let temperaturePresets: [TempPreset] = [
        TempPreset(name: "冷", value: 20), TempPreset(name: "标准", value: 50), TempPreset(name: "暖", value: 80),
    ]
    /// CLI → 菜单栏 App 的跨进程通知
    public static let changedDistributed = Notification.Name("com.holmes.displayfocus.lightChanged")
    public static let appBundleID = "com.holmes.displayfocus"

    struct Ramp { var r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue] }

    private static let lock = NSLock()
    /// 本进程首次修改前捕获的原始 gamma 表（按显示器 ID）
    nonisolated(unsafe) private static var originals: [CGDirectDisplayID: Ramp] = [:]

    // MARK: 原始表
    static func readRamp(_ id: CGDirectDisplayID) -> Ramp? {
        let cap = CGDisplayGammaTableCapacity(id)
        guard cap > 0 else { return nil }
        var r = [CGGammaValue](repeating: 0, count: Int(cap))
        var g = r, b = r
        var n: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, cap, &r, &g, &b, &n) == .success, n > 1 else { return nil }
        let k = Int(n)
        return Ramp(r: Array(r.prefix(k)), g: Array(g.prefix(k)), b: Array(b.prefix(k)))
    }
    static func identity(_ n: Int = 256) -> Ramp {
        let v = (0..<n).map { CGGammaValue(Double($0) / Double(n - 1)) }
        return Ramp(r: v, g: v, b: v)
    }
    static func original(_ id: CGDirectDisplayID) -> Ramp {
        lock.lock(); defer { lock.unlock() }
        if let o = originals[id] { return o }
        let o = readRamp(id) ?? identity()
        originals[id] = o
        return o
    }
    public static func hasCapturedOriginal(_ id: CGDirectDisplayID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return originals[id] != nil
    }

    // MARK: 色温增益
    /// 0=冷 50=标准 100=暖。暖：压低 G/B；冷：压低 R（及少量 G）
    public static func gains(temperature t: Int) -> (r: Float, g: Float, b: Float) {
        let v = Float(min(max(t, 0), 100))
        if v >= 50 {
            let w = (v - 50) / 50
            return (1.0, 1.0 - 0.18 * w, 1.0 - 0.50 * w)
        } else {
            let c = (50 - v) / 50
            return (1.0 - 0.25 * c, 1.0 - 0.10 * c, 1.0)
        }
    }

    // MARK: 应用
    /// 按设置写入 gamma 表（不保存）。中性设置 = 还原原始表
    public static func apply(_ id: CGDirectDisplayID, _ s: LightSetting) throws {
        let o = original(id)
        let f = Float(min(max(s.brightness, minEffective), 100)) / 100
        let k = gains(temperature: s.temperature)
        let r = o.r.map { $0 * f * k.r }
        let g = o.g.map { $0 * f * k.g }
        let b = o.b.map { $0 * f * k.b }
        DisplayManager.notifySelfChange()
        let e = CGSetDisplayTransferByTable(id, UInt32(r.count), r, g, b)
        guard e == .success else { throw LightError.cg("CGSetDisplayTransferByTable", e) }
    }

    // MARK: 持久化（按 厂商-型号-序列号）
    private static let key = "DisplayFocus.lightSettings"
    private static func all() -> [String: LightSetting] {
        guard let d = Store.defaults.data(forKey: key),
              let v = try? JSONDecoder().decode([String: LightSetting].self, from: d) else { return [:] }
        return v
    }
    private static func save(_ id: CGDirectDisplayID, _ s: LightSetting) {
        var v = all(); v[ModeMemory.displayKey(id)] = s
        if let d = try? JSONEncoder().encode(v) { Store.defaults.set(d, forKey: key) }
    }
    public static func setting(for id: CGDirectDisplayID) -> LightSetting {
        all()[ModeMemory.displayKey(id)] ?? LightSetting(scene: .day)
    }

    // MARK: 高层操作（保存 + 应用）
    /// 调整亮度和/或色温；手动调整会清除场景（显示为“自定义”）
    @discardableResult
    public static func update(_ id: CGDirectDisplayID, brightness: Int? = nil, temperature: Int? = nil,
                              applyNow: Bool = true) throws -> LightSetting {
        var s = setting(for: id)
        if let b = brightness { s.brightness = min(max(b, 0), 100) }
        if let t = temperature { s.temperature = min(max(t, 0), 100) }
        s.scene = LightScene.allCases.first { $0.brightness == s.brightness && $0.temperature == s.temperature }
        save(id, s)
        if applyNow { try apply(id, s) }
        return s
    }

    @discardableResult
    public static func applyScene(_ id: CGDirectDisplayID, _ sc: LightScene, applyNow: Bool = true) throws -> LightSetting {
        let s = LightSetting(brightness: sc.brightness, temperature: sc.temperature, scene: sc)
        save(id, s)
        if applyNow { try apply(id, s) }
        return s
    }

    /// 恢复软件调整：写回本进程捕获的原始表；若本进程未修改过，则调用 CGDisplayRestoreColorSyncSettings
    @discardableResult
    public static func reset(_ id: CGDirectDisplayID, applyNow: Bool = true) -> LightSetting {
        let s = LightSetting(scene: .day)
        save(id, s)
        guard applyNow else { return s }
        DisplayManager.notifySelfChange()
        lock.lock(); let o = originals[id]; originals[id] = nil; lock.unlock()
        if let o {
            if CGSetDisplayTransferByTable(id, UInt32(o.r.count), o.r, o.g, o.b) != .success { CGDisplayRestoreColorSyncSettings() }
        } else {
            CGDisplayRestoreColorSyncSettings()
        }
        return s
    }

    /// 对所有在线显示器重新套用已保存的设置（App 启动、唤醒、显示器重配置、CLI 通知时调用）
    public static func reapplyAll() {
        for id in DisplayManager.onlineDisplayIDs() {
            let s = setting(for: id)
            if s.isNeutral && !hasCapturedOriginal(id) { continue }   // 从未修改过的显示器不碰
            try? apply(id, s)
        }
    }

    // MARK: 跨进程
    public static var appIsRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID)
            .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }
    public static func postChanged() {
        DistributedNotificationCenter.default().postNotificationName(changedDistributed, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
