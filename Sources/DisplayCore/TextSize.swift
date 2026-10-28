import Foundation
import AppKit

/// 系统“文字大小”（系统设置 → 辅助功能 → 显示 → 文字大小）。
/// 没有公开 API：设置存放在 com.apple.universalaccess 的 FontSizeCategory 字典里（global 为全局值）。
public struct TextSizeOption: Identifiable, Hashable, Sendable {
    public let rawValue: String      // FontSizeCategory.global 的值
    public let title: String         // 中文名
    public let pointLabel: String    // 约等于的字号
    public var id: String { rawValue }

    /// 菜单栏使用的精简列表
    public static let curated: [TextSizeOption] = [
        TextSizeOption(rawValue: "S", title: "更小", pointLabel: "10pt"),
        TextSizeOption(rawValue: "DEFAULT", title: "默认", pointLabel: "11pt"),
        TextSizeOption(rawValue: "M", title: "稍大", pointLabel: "13pt"),
        TextSizeOption(rawValue: "L", title: "更大", pointLabel: "14pt"),
        TextSizeOption(rawValue: "XL", title: "很大", pointLabel: "15pt"),
    ]
    /// 已知的全部取值（用于校验 / 显示）
    public static let allKnown: [String] = ["XXXS", "XXS", "XS", "S", "DEFAULT", "M", "L", "XL", "XXL", "XXXL",
                                            "AX1", "AX2", "AX3", "AX4", "AX5"]
}

public enum TextSize {
    public static let domain = "com.apple.universalaccess"
    public static let key = "FontSizeCategory"

    private static var suite: UserDefaults? { UserDefaults(suiteName: domain) }

    /// 当前全局值；未设置时返回 DEFAULT
    public static func currentGlobal() -> String {
        guard let d = suite?.dictionary(forKey: key), let g = d["global"] as? String, !g.isEmpty else { return "DEFAULT" }
        return g
    }

    /// 写入全局值，保留字典中的其他键（version、各 App 单独设置等）。写回后再读一次确认
    @discardableResult
    public static func setGlobal(_ value: String) -> Bool {
        guard let s = suite else { return false }
        var d = s.dictionary(forKey: key) ?? [:]
        d["global"] = value
        s.set(d, forKey: key)
        s.synchronize()
        return currentGlobal() == value
    }

    public static func option(for raw: String) -> TextSizeOption? {
        TextSizeOption.curated.first { $0.rawValue == raw }
    }

    /// 打开系统设置的“辅助功能 → 显示”
    public static func openSystemSettings() {
        let urls = ["x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display",
                    "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display"]
        for s in urls {
            if let u = URL(string: s), NSWorkspace.shared.open(u) { return }
        }
    }
}
