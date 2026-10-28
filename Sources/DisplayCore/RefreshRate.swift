import Foundation
import CoreGraphics

/// 同一分辨率（逻辑尺寸 + 像素尺寸）下的一组刷新率
public struct ResolutionGroup: Identifiable, Hashable {
    public var id: String { "\(width)x\(height)/\(pixelWidth)x\(pixelHeight)" }
    public let width: Int, height: Int, pixelWidth: Int, pixelHeight: Int
    public let modes: [ModeInfo]                  // 按刷新率从高到低
    public var isHiDPI: Bool { pixelWidth > width }
    public var label: String { "\(width)×\(height)" + (isHiDPI ? " (HiDPI)" : "") }
    public var ratesLabel: String { modes.map { ModeInfo.hzText($0.refreshRate) }.joined(separator: ", ") }
}

extension ModeInfo {
    /// 59.94 → "59.94Hz"，60 → "60Hz"，0（内建屏常见）→ "默认Hz"
    public static func hzText(_ r: Double) -> String {
        if r <= 0 { return "默认Hz" }
        return abs(r - r.rounded()) < 0.01 ? "\(Int(r.rounded()))Hz" : String(format: "%.2fHz", r)
    }
}

extension DisplayManager {
    public static func resolutionGroups(_ id: CGDirectDisplayID, includeUnusable: Bool = false) -> [ResolutionGroup] {
        let all = modes(id, includeUnusable: includeUnusable)
        var order: [String] = []; var dict: [String: [ModeInfo]] = [:]
        for m in all {
            let k = "\(m.width)x\(m.height)/\(m.pixelWidth)x\(m.pixelHeight)"
            if dict[k] == nil { order.append(k) }
            dict[k, default: []].append(m)
        }
        return order.map { k in
            let ms = dict[k]!.sorted { $0.refreshRate > $1.refreshRate }
            let f = ms[0]
            return ResolutionGroup(width: f.width, height: f.height, pixelWidth: f.pixelWidth, pixelHeight: f.pixelHeight, modes: ms)
        }
    }

    public static func currentMode(_ id: CGDirectDisplayID) -> ModeInfo? {
        return CGDisplayCopyDisplayMode(id).map(toInfo)
    }

    /// 保持当前分辨率，仅切换刷新率（选最接近 hz 的模式）
    public static func setRefreshRate(display id: CGDirectDisplayID, hz: Double, permanent: Bool = true) throws {
        guard let cur = currentMode(id) else { throw DisplayError.notFound(id) }
        let cands = modes(id).filter { $0.width == cur.width && $0.height == cur.height && $0.pixelWidth == cur.pixelWidth }
        guard let best = cands.min(by: { abs($0.refreshRate - hz) < abs($1.refreshRate - hz) }),
              abs(best.refreshRate - hz) < 1.0 else { throw DisplayError.rateUnavailable(hz, cands.map(\.refreshRate)) }
        try setMode(display: id, modeID: best.id, permanent: permanent)
    }

    /// 按 "宽x高[@Hz]" 选择模式，可选 hidpi 偏好；未给 Hz 时取最高刷新率
    public static func setMode(display id: CGDirectDisplayID, width: Int, height: Int, hz: Double?, hiDPI: Bool?, permanent: Bool = true) throws {
        var cands = modes(id).filter { $0.width == width && $0.height == height }
        if let h = hiDPI { cands = cands.filter { $0.isHiDPI == h } }
        let pick: ModeInfo?
        if let hz { pick = cands.filter { abs($0.refreshRate - hz) < 1.0 }.min { abs($0.refreshRate - hz) < abs($1.refreshRate - hz) } }
        else { pick = cands.max { $0.refreshRate < $1.refreshRate } }
        guard let m = pick else { throw DisplayError.rateUnavailable(hz ?? 0, cands.map(\.refreshRate)) }
        try setMode(display: id, modeID: m.id, permanent: permanent)
    }
}
