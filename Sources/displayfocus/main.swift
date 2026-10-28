import Foundation
import CoreGraphics
import DisplayCore

func usage() {
    print("""
    用法: displayfocus <命令>
      list                       列出所有显示器
      modes <displayID> [--all]  列出指定显示器可用模式
      modes <displayID> --flat   按 modeID 平铺列出（不分组）
      set <displayID> <modeID> [--session]  按 modeID 设置模式（默认永久）
      res <displayID> <宽x高[@Hz]> [--hidpi|--no-hidpi] [--session]
                                 按分辨率(+刷新率)设置，如 res 2 2560x1440@144
      hz <displayID> <Hz> [--session]  保持当前分辨率，只切换刷新率，如 hz 2 120
      mirror-off-builtin         已停用（本机曾造成外屏黑屏）
      unmirror                   取消所有镜像
      disable-builtin            [受保护测试] 停用内屏，25 秒未确认自动尝试恢复
      confirm-disable            确认外屏可操作后保留此次关闭
      revert-disable             立即恢复此次关闭前的配置
      diagnose                   只读枚举在线/活动/镜像/身份/模式状态
      enable-builtin             重新开启内建屏（自动处理“关闭”或“镜像”两种状态）
      status                     显示内建屏状态、自动模式、记住的模式
      auto on|off|status         开关自动模式（需菜单栏 App 运行才会生效）
      forget <displayID>         忘记该外接屏记住的模式
      restore <displayID>        立即恢复该外接屏记住的模式
      scale <displayID>          列出缩放选项（看起来像 W×H、百分比、是否 HiDPI）
      scale <displayID> <宽x高> [--hidpi|--no-hidpi]
                                 切换缩放（默认优先 HiDPI，保持当前刷新率）
      hidpi <displayID> on|off|status  写入/移除 HiDPI 覆盖文件（需管理员密码）
      login on|off|status        登录时启动（LaunchAgent）
      light <displayID> [0-100] [--hold]       软件调光（gamma，在硬件亮度基础上再压暗）
      temp <displayID> [cool|standard|warm|0-100] [--hold]  色温（0 冷，50 标准，100 暖）
      scene <displayID> <day|read|movie|night|日间|阅读|观影|夜间> [--hold]
      light-reset <displayID>    恢复软件调整（还原原始 gamma）
        注：gamma 修改在设置它的进程退出时会被系统还原。菜单栏 App 运行时由 App 负责应用；
            否则可加 --hold 让 CLI 保持运行（Ctrl-C 结束后还原）。
    """)
}
/// 设置已保存后：App 在运行则通知 App 应用；否则本进程应用（退出即还原，可 --hold）
func deliverLight(_ id: CGDirectDisplayID, _ s: LightSetting, hold: Bool) {
    print("[\(id)] \(s.summary)")
    if SoftwareLight.appIsRunning {
        SoftwareLight.postChanged()
        print("已通知菜单栏 App 应用 ✅")
        return
    }
    do { try SoftwareLight.apply(id, s) } catch { fputs("错误: \(error)\n", stderr); exit(1) }
    if hold {
        print("已应用，保持中…按 Ctrl-C 结束（结束后系统会还原 gamma）")
        RunLoop.main.run()
    } else {
        print("提示：菜单栏 App 未运行，CLI 退出后系统会自动还原 gamma。请启动 DisplayFocus.app（会自动套用已保存的设置），或加 --hold。")
    }
}
func run(_ f: () throws -> Void) { do { try f(); print("完成 ✅") } catch { fputs("错误: \(error)\n", stderr); exit(1) } }

let a = Array(CommandLine.arguments.dropFirst())
switch a.first {
case "recovery-watchdog":
    guard a.count == 2 else { exit(2) }
    do { try DisplayTrial.watchdog(token: a[1]) } catch { fputs("恢复保护错误: \(error)\n", stderr); exit(1) }
case "confirm-disable":
    run { try DisplayTrial.confirm() }
case "revert-disable":
    run { try DisplayTrial.revert() }
case "diagnose":
    for d in DisplaySafety.records() {
        print("id=\(d.id) identity=\(d.identity) builtin=\(d.builtin) online=\(d.online) active=\(d.active) asleep=\(d.asleep) main=\(d.main) mirror=\(d.mirror) origin=\(d.x),\(d.y) mode=\(d.width)x\(d.height) pixels=\(d.pixelWidth)x\(d.pixelHeight) hz=\(d.hz)")
    }
    print("待确认=\(DisplayTrial.isPending) 剩余秒数=\(DisplayTrial.secondsLeft)")
case "list":
    for d in DisplayManager.displays() {
        var t = [d.isBuiltin ? "内建" : "外接"]
        if d.isMain { t.append("主屏") }
        if d.mirrorsDisplay != kCGNullDirectDisplay { t.append("镜像→\(d.mirrorsDisplay)") }
        print("[\(d.id)] \(d.name)  \(d.width)×\(d.height) (像素 \(d.pixelWidth)×\(d.pixelHeight)) @ \(ModeInfo.hzText(d.refreshRate))  \(t.joined(separator: ","))")
    }
    print("内建屏：\(DisplayManager.builtinState.zh)")
case "modes":
    guard a.count >= 2, let id = UInt32(a[1]) else { usage(); exit(2) }
    let cur = DisplayManager.currentModeID(id)
    let all = a.contains("--all")
    if a.contains("--flat") {
        for m in DisplayManager.modes(id, includeUnusable: all) {
            print("\(m.id == cur ? "*" : " ") modeID=\(m.id)\t\(m.label)\(m.isUsable ? "" : " [不可用于桌面]")")
        }
    } else {
        for g in DisplayManager.resolutionGroups(id, includeUnusable: all) {
            let hidpi = g.isHiDPI ? " (HiDPI 像素 \(g.pixelWidth)×\(g.pixelHeight))" : ""
            print("\(g.width)x\(g.height)\(hidpi)  可选: \(g.ratesLabel)")
            for m in g.modes {
                print("   \(m.id == cur ? "*" : " ") \(ModeInfo.hzText(m.refreshRate))\tmodeID=\(m.id)\(m.isUsable ? "" : " [不可用于桌面]")")
            }
        }
        print("（* 为当前模式；用 set <ID> <modeID>、res 或 hz 切换）")
    }
case "set":
    guard a.count >= 3, let id = UInt32(a[1]), let mid = Int32(a[2]) else { usage(); exit(2) }
    run { try DisplayManager.setMode(display: id, modeID: mid, permanent: !a.contains("--session")) }
case "res":
    guard a.count >= 3, let id = UInt32(a[1]) else { usage(); exit(2) }
    let parts = a[2].lowercased().replacingOccurrences(of: "hz", with: "").split(separator: "@")
    let wh = parts[0].split(whereSeparator: { $0 == "x" || $0 == "×" })
    guard wh.count == 2, let w = Int(wh[0]), let h = Int(wh[1]) else { usage(); exit(2) }
    let hz = parts.count > 1 ? Double(parts[1]) : nil
    let hidpi: Bool? = a.contains("--hidpi") ? true : (a.contains("--no-hidpi") ? false : nil)
    run { try DisplayManager.setMode(display: id, width: w, height: h, hz: hz, hiDPI: hidpi, permanent: !a.contains("--session")) }
case "hz":
    guard a.count >= 3, let id = UInt32(a[1]), let hz = Double(a[2].lowercased().replacingOccurrences(of: "hz", with: "")) else { usage(); exit(2) }
    run { try DisplayManager.setRefreshRate(display: id, hz: hz, permanent: !a.contains("--session")) }
case "mirror-off-builtin": run { try DisplayManager.mirrorBuiltinToExternal() }
case "unmirror": run { try DisplayManager.stopMirroring() }
case "disable-builtin":
    do {
        try DisplayManager.disableBuiltin()
        print("关闭测试已启动，25 秒未确认将尝试恢复。确认实体外屏与鼠标正常后运行 confirm-disable；立即恢复用 revert-disable。")
    } catch { fputs("关闭测试失败: \(error)\n", stderr); exit(1) }
case "enable-builtin": run { Store.autoEnabled = false; try DisplayManager.restoreBuiltin() }
case "status":
    print("内建屏：\(DisplayManager.builtinState.zh)\(DisplayManager.builtinID.map { "（ID \($0)）" } ?? "")")
    print("自动模式：\(Store.autoEnabled ? "开" : "关")")
    print("自动配置：\(AutomaticDisplayPolicy.status)；独立失联监控：\(DisplayTrial.isMonitoring)")
    print("私有 API 符号：\(DisplayManager.privateDisableAvailable ? "存在（不代表驱动支持停用）" : "不存在")")
    for e in DisplayManager.externals() {
        print("[\(e.id)] \(e.name) 记住的模式：\(ModeMemory.saved(for: e.id)?.label ?? "无")")
        print("    \(SoftwareLight.setting(for: e.id).summary)")
    }
case "auto":
    switch a.count > 1 ? a[1] : "status" {
    case "on": Store.autoEnabled = true; Store.defaults.removeObject(forKey: "DisplayFocus.autoPauseReason"); print("自动模式：开；\(AutomaticDisplayPolicy.status)（需菜单栏 App 运行）")
    case "off": Store.autoEnabled = false; print("自动模式：关")
    default: print("自动模式：\(Store.autoEnabled ? "开" : "关")")
    }
case "forget":
    guard a.count >= 2, let id = UInt32(a[1]) else { usage(); exit(2) }
    ModeMemory.forget(id); print("已忘记")
case "restore":
    guard a.count >= 2, let id = UInt32(a[1]) else { usage(); exit(2) }
    run { if try ModeMemory.restore(id) == nil { print("无需恢复（无记录或已是该模式）") } }
case "scale":
    guard a.count >= 2, let id = UInt32(a[1]) else { usage(); exit(2) }
    if a.count >= 3, !a[2].hasPrefix("--") {
        let wh = a[2].lowercased().split(whereSeparator: { $0 == "x" || $0 == "×" })
        guard wh.count == 2, let w = Int(wh[0]), let h = Int(wh[1]) else { usage(); exit(2) }
        let hd: Bool? = a.contains("--hidpi") ? true : (a.contains("--no-hidpi") ? false : nil)
        run {
            let m = try DisplayManager.setScale(display: id, width: w, height: h, hiDPI: hd, permanent: !a.contains("--session"))
            print("已切换：\(m.label)")
        }
    } else {
        let n = DisplayManager.nativeSize(id)
        let cur = DisplayManager.currentScale(id)
        print("原生分辨率：\(n.width)×\(n.height)")
        let opts = DisplayManager.scaleOptions(id)
        for o in opts {
            let isCur = cur.map { $0.width == o.width && $0.height == o.height && $0.hiDPI == o.hiDPI } ?? false
            print("\(isCur ? "*" : " ") \(o.width)x\(o.height)\t\(o.label)  [\(o.tag)]  \(o.ratesLabel)")
        }
        if !opts.contains(where: { $0.hiDPI }) { print("提示：没有 HiDPI 模式，可运行 displayfocus hidpi \(id) on") }
    }
case "hidpi":
    guard a.count >= 2, let id = UInt32(a[1]) else { usage(); exit(2) }
    let path = HiDPIOverride.filePath(id)
    switch a.count > 2 ? a[2] : "status" {
    case "on":
        print("覆盖文件：\(path)")
        run { try HiDPIOverride.install(id, name: DisplayManager.name(of: id), via: .osascript) }
        print("请重新插拔显示器或注销/重启后生效，然后运行 displayfocus scale \(id) 查看 HiDPI 选项")
    case "off":
        run { try HiDPIOverride.remove(id, via: .osascript) }
        print("已移除 \(path)，重新插拔显示器或注销/重启后生效")
    default:
        print("覆盖文件：\(path)（\(HiDPIOverride.isInstalled(id) ? "已安装" : "未安装")）")
    }
case "login":
    switch a.count > 1 ? a[1] : "status" {
    case "on": run { if let w = try LoginAgent.enable() { print(w) } }
    case "off": run { try LoginAgent.disable() }
    default: print("登录时启动：\(LoginAgent.isInstalled ? "开" : "关")（\(LoginAgent.plistURL.path)）")
    }
case "light":
    guard a.count >= 2, let id = UInt32(a[1]) else { usage(); exit(2) }
    if a.count >= 3, let v = Int(a[2].replacingOccurrences(of: "%", with: "")) {
        let st = (try? SoftwareLight.update(id, brightness: v, applyNow: false)) ?? SoftwareLight.setting(for: id)
        deliverLight(id, st, hold: a.contains("--hold"))
    } else {
        print("[\(id)] \(SoftwareLight.setting(for: id).summary)")
    }
case "temp":
    guard a.count >= 2, let id = UInt32(a[1]) else { usage(); exit(2) }
    if a.count >= 3, !a[2].hasPrefix("--") {
        let v: Int?
        switch a[2].lowercased() {
        case "cool", "cold", "冷": v = 20
        case "standard", "neutral", "标准": v = 50
        case "warm", "暖": v = 80
        default: v = Int(a[2])
        }
        guard let t = v else { usage(); exit(2) }
        let st = (try? SoftwareLight.update(id, temperature: t, applyNow: false)) ?? SoftwareLight.setting(for: id)
        deliverLight(id, st, hold: a.contains("--hold"))
    } else {
        print("[\(id)] \(SoftwareLight.setting(for: id).summary)")
    }
case "scene":
    guard a.count >= 3, let id = UInt32(a[1]), let sc = LightScene(arg: a[2]) else { usage(); exit(2) }
    let st = (try? SoftwareLight.applyScene(id, sc, applyNow: false)) ?? SoftwareLight.setting(for: id)
    deliverLight(id, st, hold: a.contains("--hold"))
case "light-reset":
    guard a.count >= 2, let id = UInt32(a[1]) else { usage(); exit(2) }
    if SoftwareLight.appIsRunning {
        _ = SoftwareLight.reset(id, applyNow: false)
        SoftwareLight.postChanged()
        print("已通知菜单栏 App 恢复 ✅")
    } else {
        _ = SoftwareLight.reset(id)
        print("已恢复软件调整 ✅")
    }
default: usage()
}
