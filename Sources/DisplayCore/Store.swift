import Foundation
import CoreGraphics

/// App 与 CLI 共享的偏好设置域
public enum Store {
    public static let suite = "com.holmes.displayfocus"
    nonisolated(unsafe) public static let defaults: UserDefaults = Bundle.main.bundleIdentifier == suite ? .standard : (UserDefaults(suiteName: suite) ?? .standard)

    public static var autoEnabled: Bool {
        get { defaults.bool(forKey: "DisplayFocus.autoMode") }
        set { defaults.set(newValue, forKey: "DisplayFocus.autoMode") }
    }
}

/// 按 厂商/型号/序列号 记住每台外接屏最后选择的模式
public struct ModeSpec: Codable, Hashable, Sendable {
    public var width: Int, height: Int, hiDPI: Bool, hz: Double
    public var label: String { "\(width)×\(height)\(hiDPI ? " (HiDPI)" : "") @ \(ModeInfo.hzText(hz))" }
}

public enum ModeMemory {
    private static let key = "DisplayFocus.savedModes"

    public static func displayKey(_ id: CGDirectDisplayID) -> String {
        "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }
    private static func all() -> [String: ModeSpec] {
        guard let d = Store.defaults.data(forKey: key),
              let v = try? JSONDecoder().decode([String: ModeSpec].self, from: d) else { return [:] }
        return v
    }
    private static func write(_ v: [String: ModeSpec]) {
        if let d = try? JSONEncoder().encode(v) { Store.defaults.set(d, forKey: key) }
    }
    public static func save(display id: CGDirectDisplayID, mode m: ModeInfo) {
        var v = all(); v[displayKey(id)] = ModeSpec(width: m.width, height: m.height, hiDPI: m.isHiDPI, hz: m.refreshRate); write(v)
    }
    public static func saved(for id: CGDirectDisplayID) -> ModeSpec? { all()[displayKey(id)] }
    public static func forget(_ id: CGDirectDisplayID) { var v = all(); v[displayKey(id)] = nil; write(v) }

    /// 恢复记住的模式；返回是否实际切换。按宽/高/HiDPI/刷新率匹配，不依赖 modeID
    @discardableResult
    public static func restore(_ id: CGDirectDisplayID) throws -> ModeSpec? {
        guard let spec = saved(for: id) else { return nil }
        if let cur = DisplayManager.currentMode(id), cur.width == spec.width, cur.height == spec.height,
           cur.isHiDPI == spec.hiDPI, abs(cur.refreshRate - spec.hz) < 1.0 { return nil }
        let cands = DisplayManager.modes(id).filter { $0.width == spec.width && $0.height == spec.height && $0.isHiDPI == spec.hiDPI }
        guard let best = cands.min(by: { abs($0.refreshRate - spec.hz) < abs($1.refreshRate - spec.hz) }),
              abs(best.refreshRate - spec.hz) < 1.0 else { throw DisplayError.rateUnavailable(spec.hz, cands.map(\.refreshRate)) }
        try DisplayManager.setMode(display: id, modeID: best.id, remember: false)
        return spec
    }
}
