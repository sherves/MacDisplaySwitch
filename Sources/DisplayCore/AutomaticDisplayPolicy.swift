import Foundation
import CryptoKit

/// Physical confirmation is tied to this panel, external mode and driver environment, not transient IDs.
struct AutomaticDisplayProfile: Codable {
    let builtin: String
    let external: DisplayRecord
    let environment: String
    func allows(_ records: [DisplayRecord], environment current: String) -> Bool {
        guard environment == current, let targets = try? DisplaySafety.targets(records) else { return false }
        return targets.0.identity == builtin && targets.1.identity == external.identity && targets.1.sameMode(as: external)
    }
}

struct DisplayStabilityGate {
    private var signature: String?
    private var since: TimeInterval = 0
    mutating func observe(_ candidate: String?, now: TimeInterval, interval: TimeInterval = 4) -> Bool {
        guard let candidate else { signature = nil; return false }
        if signature != candidate { signature = candidate; since = now; return false }
        return now - since >= interval
    }
}

public enum AutomaticDisplayPolicy {
    private static let key = "DisplayFocus.automaticProfile.v1"
    // A new login/helper after a driver or OS update requires new physical confirmation.
    static let environment: String = {
        let paths = ["/System/Library/CoreServices/SystemVersion.plist", "/Library/NullMoth/driver-version",
            "/Library/Extensions/NVRM.kext/Contents/MacOS/NVRM", "/Library/Extensions/NVAccel.kext/Contents/MacOS/NVAccel",
            "/Library/Extensions/NVRMFB.kext/Contents/MacOS/NVRMFB", "/Library/Extensions/NVRMAGDC.kext/Contents/MacOS/NVRMAGDC",
            "/Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver"]
        var hash = SHA256()
        for path in paths {
            hash.update(data: Data(path.utf8))
            hash.update(data: (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data("missing".utf8))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }()
    static func remember(builtin: String, external: DisplayRecord) throws {
        let profile = AutomaticDisplayProfile(builtin: builtin, external: external, environment: environment)
        Store.defaults.set(try JSONEncoder().encode(profile), forKey: key)
    }
    static func allows(_ records: [DisplayRecord]) -> Bool {
        guard let data = Store.defaults.data(forKey: key),
              let profile = try? JSONDecoder().decode(AutomaticDisplayProfile.self, from: data) else { return false }
        return profile.allows(records, environment: environment)
    }
    public static var status: String {
        guard let data = Store.defaults.data(forKey: key),
              let p = try? JSONDecoder().decode(AutomaticDisplayProfile.self, from: data) else {
            return "尚无确认记录；请先测试关闭内屏并确认一次"
        }
        guard p.environment == environment else { return "系统或驱动已变化；需重新测试并确认一次" }
        return "已记住确认过的外屏：\(p.external.width)×\(p.external.height) @ \(ModeInfo.hzText(p.external.hz))"
    }
    static func pause(_ reason: String) {
        Store.autoEnabled = false
        Store.defaults.set(reason, forKey: "DisplayFocus.autoPauseReason")
    }
}
