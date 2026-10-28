import Foundation
import CoreGraphics

// MARK: - 缩放选项

/// 一个“看起来像 W×H”的缩放选项（同一逻辑尺寸 + 是否 HiDPI），含该尺寸下所有刷新率
public struct ScaleOption: Identifiable, Hashable {
    public var id: String { "\(width)x\(height)-\(hiDPI ? "2x" : "1x")" }
    public let width: Int, height: Int
    public let hiDPI: Bool
    public let percent: Int          // 原生宽度 / 看起来像宽度
    public let modes: [ModeInfo]     // 刷新率从高到低
    public var label: String { "看起来像 \(width)×\(height)（\(percent)%）" }
    public var tag: String { hiDPI ? "清晰" : "可能模糊" }
    public var ratesLabel: String { modes.map { ModeInfo.hzText($0.refreshRate) }.joined(separator: ", ") }
}

public enum ScaleError: Error, CustomStringConvertible {
    case noSuchScale(Int, Int, Bool?)
    case privileged(String)
    case cancelled
    public var description: String {
        switch self {
        case .noSuchScale(let w, let h, let hd):
            let t = hd == true ? "（HiDPI）" : (hd == false ? "（非 HiDPI）" : "")
            return "没有“看起来像 \(w)×\(h)”\(t)的模式"
        case .privileged(let m): return "管理员操作失败：\(m)"
        case .cancelled: return "已取消管理员授权"
        }
    }
}

extension DisplayManager {
    /// 面板原生分辨率：取 1x 模式（像素 = 逻辑）中面积最大者
    public static func nativeSize(_ id: CGDirectDisplayID) -> (width: Int, height: Int) {
        let all = modes(id, includeUnusable: true)
        if let m = all.filter({ $0.pixelWidth == $0.width })
            .max(by: { $0.width * $0.height < $1.width * $1.height }) { return (m.width, m.height) }
        return (CGDisplayPixelsWide(id), CGDisplayPixelsHigh(id))
    }

    public static func scaleOptions(_ id: CGDirectDisplayID) -> [ScaleOption] {
        let native = nativeSize(id)
        var order: [String] = []
        var dict: [String: [ModeInfo]] = [:]
        for m in modes(id) {
            let k = "\(m.width)x\(m.height)-\(m.isHiDPI)"
            if dict[k] == nil { order.append(k) }
            dict[k, default: []].append(m)
        }
        return order.compactMap { k -> ScaleOption? in
            guard let ms = dict[k]?.sorted(by: { $0.refreshRate > $1.refreshRate }), let f = ms.first else { return nil }
            let pct = Int((Double(native.width) / Double(max(f.width, 1)) * 100).rounded())
            return ScaleOption(width: f.width, height: f.height, hiDPI: f.isHiDPI, percent: pct, modes: ms)
        }.sorted { a, b in
            if a.width != b.width { return a.width > b.width }
            if a.height != b.height { return a.height > b.height }
            return a.hiDPI && !b.hiDPI          // 同尺寸 HiDPI 排前
        }
    }

    /// 当前所在的缩放选项（宽/高/HiDPI）
    public static func currentScale(_ id: CGDirectDisplayID) -> (width: Int, height: Int, hiDPI: Bool)? {
        guard let c = currentMode(id) else { return nil }
        return (c.width, c.height, c.isHiDPI)
    }

    /// 切换到“看起来像 w×h”。hiDPI 为 nil 时优先 HiDPI；保持当前刷新率（±1Hz），否则取最高
    @discardableResult
    public static func setScale(display id: CGDirectDisplayID, width w: Int, height h: Int,
                                hiDPI: Bool? = nil, permanent: Bool = true) throws -> ModeInfo {
        var cands = modes(id).filter { $0.width == w && $0.height == h }
        if let hd = hiDPI {
            cands = cands.filter { $0.isHiDPI == hd }
        } else if cands.contains(where: { $0.isHiDPI }) {
            cands = cands.filter { $0.isHiDPI }
        }
        let curHz = currentMode(id)?.refreshRate ?? 0
        let sameHz = cands.filter { abs($0.refreshRate - curHz) < 1.0 }
            .min { abs($0.refreshRate - curHz) < abs($1.refreshRate - curHz) }
        guard let pick = sameHz ?? cands.max(by: { $0.refreshRate < $1.refreshRate }) else {
            throw ScaleError.noSuchScale(w, h, hiDPI)
        }
        try setMode(display: id, modeID: pick.id, permanent: permanent)
        return pick
    }
}

// MARK: - HiDPI 覆盖文件（one-key-hidpi 同款做法）

public enum HiDPIOverride {
    public static let baseDir = "/Library/Displays/Contents/Resources/Overrides"

    /// 要提供的“看起来像”分辨率；HiDPI 条目写入 2 倍像素尺寸
    public static let looksLike: [(Int, Int)] = [
        (1920, 1080), (1680, 945), (1600, 900), (1440, 810),
        (1280, 720), (2048, 1152), (2304, 1296), (2560, 1440),
    ]

    public static func vendorProduct(_ id: CGDirectDisplayID) -> (vendor: UInt32, product: UInt32) {
        (CGDisplayVendorNumber(id), CGDisplayModelNumber(id))
    }
    /// Apple 惯例：小写十六进制、无 0x，如 DisplayVendorID-10ac
    public static func dirPath(_ id: CGDirectDisplayID) -> String {
        "\(baseDir)/DisplayVendorID-\(String(vendorProduct(id).vendor, radix: 16))"
    }
    public static func filePath(_ id: CGDirectDisplayID) -> String {
        "\(dirPath(id))/DisplayProductID-\(String(vendorProduct(id).product, radix: 16))"
    }
    public static func isInstalled(_ id: CGDirectDisplayID) -> Bool {
        FileManager.default.fileExists(atPath: filePath(id))
    }

    /// 每个条目：大端 UInt32 宽、高；HiDPI 条目追加标志 0x00000001 0x00200000
    static func entry(_ w: Int, _ h: Int, hiDPIFlags: Bool) -> Data {
        var words: [UInt32] = [UInt32(w), UInt32(h)]
        if hiDPIFlags { words += [0x0000_0001, 0x0020_0000] }
        var d = Data()
        for v in words { var be = v.bigEndian; withUnsafeBytes(of: &be) { d.append(contentsOf: $0) } }
        return d
    }

    public static func plistData(_ id: CGDirectDisplayID, name: String) throws -> Data {
        let vp = vendorProduct(id)
        let res: [Data] = looksLike.map { entry($0.0 * 2, $0.1 * 2, hiDPIFlags: true) }   // 2x：如 3840×2160 → 看起来像 1920×1080
        // 只制作 HiDPI：不再写入 1x 低分辨率条目（原生 1x 由系统自带）
        let dict: [String: Any] = [
            "DisplayProductName": name,
            "DisplayVendorID": Int(vp.vendor),
            "DisplayProductID": Int(vp.product),
            "scale-resolutions": res,
        ]
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    /// 写到临时文件，返回路径
    public static func writeTemp(_ id: CGDirectDisplayID, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DisplayFocus-DisplayProductID-\(String(vendorProduct(id).product, radix: 16)).plist")
        try plistData(id, name: name).write(to: url, options: .atomic)
        return url
    }

    public enum Runner { case appleScript, osascript }

    public static func install(_ id: CGDirectDisplayID, name: String, via r: Runner) throws {
        let tmp = try writeTemp(id, name: name)
        let dir = dirPath(id), file = filePath(id)
        let sh = "mkdir -p \(Proc.q(dir)) && cp \(Proc.q(tmp.path)) \(Proc.q(file)) && chown root:wheel \(Proc.q(file)) && chmod 644 \(Proc.q(file))"
        try runPrivileged(sh, via: r)
    }

    public static func remove(_ id: CGDirectDisplayID, via r: Runner) throws {
        let sh = "rm -f \(Proc.q(filePath(id))); rmdir \(Proc.q(dirPath(id))) 2>/dev/null; exit 0"
        try runPrivileged(sh, via: r)
    }

    /// do shell script "..." with administrator privileges
    public static func runPrivileged(_ shell: String, via r: Runner) throws {
        let esc = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let src = "do shell script \"\(esc)\" with administrator privileges"
        switch r {
        case .appleScript:
            guard let script = NSAppleScript(source: src) else { throw ScaleError.privileged("无法创建 AppleScript") }
            var err: NSDictionary?
            _ = script.executeAndReturnError(&err)
            if let err {
                if (err[NSAppleScript.errorNumber] as? Int) == -128 { throw ScaleError.cancelled }
                throw ScaleError.privileged(err[NSAppleScript.errorMessage] as? String ?? "\(err)")
            }
        case .osascript:
            let res = Proc.run("/usr/bin/osascript", ["-e", src])
            if res.status != 0 {
                if res.output.contains("-128") { throw ScaleError.cancelled }
                throw ScaleError.privileged(res.output)
            }
        }
    }
}
