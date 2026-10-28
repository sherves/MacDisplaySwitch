import SwiftUI
import AppKit
import CoreGraphics
import DisplayCore

enum MenuTab: String, CaseIterable, Hashable {
    case overview, picture, resolution, settings
    var title: String {
        switch self { case .overview: return "概览"; case .picture: return "画面"; case .resolution: return "分辨率"; case .settings: return "设置" }
    }
    var icon: String {
        switch self {
        case .overview: return "display"
        case .picture: return "slider.horizontal.3"
        case .resolution: return "aspectratio"
        case .settings: return "gearshape"
        }
    }
}

extension LightScene {
    var symbol: String {
        switch self { case .day: return "sun.max"; case .read: return "book"; case .movie: return "film"; case .night: return "moon" }
    }
}

struct MenuView: View {
    @ObservedObject var m: Model
    @State private var tab: MenuTab = .overview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            tabBar
            AutoHeightScroll(maxHeight: 400) {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .overview: overviewTab
                    case .picture: pictureTab
                    case .resolution: resolutionTab
                    case .settings: settingsTab
                    }
                }
                .padding(.bottom, 2)
            }
            if !m.message.isEmpty {
                Text(m.message)
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardFill))
            }
            footer
        }
        .padding(16)
        .frame(width: 372)
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: m.selectedDisplay?.isBuiltin == true ? "laptopcomputer" : "display")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(m.selectedDisplay?.name ?? "DisplayFocus").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(m.headerSubtitle).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if m.displays.count > 1 {
                Menu {
                    ForEach(m.displays) { d in
                        Button((d.id == m.selected ? "✓ " : "") + d.name + (d.isBuiltin ? "（内建）" : "")) { m.select(d.id) }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("切换显示器")
            }
            RoundIconButton(systemName: "arrow.clockwise", size: 28, help: "刷新") { m.refresh() }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(MenuTab.allCases, id: \.self) { t in
                let sel = t == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { tab = t }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 14, weight: .medium))
                        Text(t.title).font(.system(size: 11, weight: sel ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundColor(sel ? Theme.accent : .secondary)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(sel ? Theme.accent.opacity(0.16) : Color.clear))
                    .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardStroke, lineWidth: 1))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(m.builtinState == .enabled ? Color.green : Theme.accent).frame(width: 6, height: 6)
            Text(m.statusLine).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
            Spacer()
            RoundIconButton(systemName: "power", size: 28, help: "退出 DisplayFocus") { NSApp.terminate(nil) }
        }
    }

    // MARK: - 概览

    @ViewBuilder private var overviewTab: some View {
        previewCard
        Card("内建屏", icon: "laptopcomputer", trailing: m.builtinState.zh) {
            if m.trialPending {
                Text("请确认外屏画面、鼠标及远控正常。\(m.trialSeconds) 秒后自动尝试恢复。")
                    .font(.system(size: 12)).foregroundColor(.orange)
                HStack {
                    PillButton(title: "外屏正常，保留", icon: "checkmark.circle") { m.confirmDisable() }
                    PillButton(title: "立即恢复", icon: "arrow.uturn.backward") { m.recoverDisplay() }
                }
            } else {
                HStack(spacing: 8) {
                    PillButton(title: "测试关闭内屏", icon: "moon.zzz", enabled: m.canTestDisable) { m.testDisable() }
                    PillButton(title: "恢复内屏", icon: "sun.max") { m.recoverDisplay() }
                }
            }
            Text("已移除镜像关闭。关闭指逻辑停用，不保证背光熄灭；驱动卡死时自动恢复也可能失败。")
                .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        brightnessCard(compact: true)
        scenesCard
    }

    private var previewCard: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.06)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 3)
                VStack(spacing: 6) {
                    if let c = m.current {
                        Text("\(c.width) × \(c.height)")
                            .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(previewDetail(c)).font(.system(size: 11)).foregroundColor(.secondary)
                    } else {
                        Text("未检测到显示器").font(.system(size: 14)).foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 118)
            // 支架
            RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.15)).frame(width: 64, height: 5)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }

    private func previewDetail(_ c: ModeInfo) -> String {
        let hz = ModeInfo.hzText(c.refreshRate).replacingOccurrences(of: "Hz", with: " Hz")
        return c.isHiDPI ? "HiDPI · 渲染 \(c.pixelWidth)×\(c.pixelHeight) · \(hz)" : "非 HiDPI · \(hz)"
    }

    // MARK: - 画面

    @ViewBuilder private var pictureTab: some View {
        scenesCard
        brightnessCard(compact: false)
        Card {
            ValueSlider(title: "色温", caption: "向右更暖，减少蓝光", icon: "thermometer.medium",
                        valueText: tempText, value: m.light.temperature,
                        leftLabel: "冷", rightLabel: "暖") { m.setTemperature($0) }
            PillGrid(items: SoftwareLight.temperaturePresets, columns: 3) { p in
                PillButton(title: p.name, selected: m.light.temperature == p.value) { m.setTemperature(p.value) }
            }
        }
        WideButton(title: "恢复软件调整", icon: "arrow.counterclockwise") { m.resetLight() }
        Text("软件调光通过 gamma 实现，不改变显示器背光；需保持本 App 运行。")
            .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var tempText: String {
        let t = m.light.temperature
        return t < 40 ? "偏冷" : (t > 60 ? "偏暖" : "标准")
    }

    private var scenesCard: some View {
        Card("场景", icon: "sparkles", trailing: m.light.scene.map { "当前：\($0.zh)" } ?? "自定义") {
            PillGrid(items: LightScene.allCases, columns: 4) { sc in
                PillButton(title: sc.zh, icon: sc.symbol, selected: m.light.scene == sc, vertical: true) { m.applyScene(sc) }
            }
        }
    }

    private func brightnessCard(compact: Bool) -> some View {
        Card {
            ValueSlider(title: "软件调光", caption: compact ? "Gamma 软件压暗" : "在硬件亮度基础上再压暗（低于 \(SoftwareLight.minEffective)% 按 \(SoftwareLight.minEffective)% 处理）",
                        icon: "sun.min", valueText: "\(m.light.brightness)", value: m.light.brightness) { m.setBrightness($0) }
        }
    }

    // MARK: - 分辨率

    @ViewBuilder private var resolutionTab: some View {
        if m.selectedIsBuiltin {
            Card("提示", icon: "info.circle") {
                Text("请在右上角切换到外接显示器。").font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
        refreshCard
        resolutionListCard
        hidpiCard
    }

    private var refreshCard: some View {
        Card("刷新率", icon: "speedometer", trailing: m.current.map { "\($0.width) × \($0.height)" }) {
            if let g = m.currentGroup, !g.modes.isEmpty {
                PillGrid(items: g.modes, columns: 4) { mode in
                    PillButton(title: ModeInfo.hzText(mode.refreshRate).replacingOccurrences(of: "Hz", with: " Hz"),
                               selected: mode.id == m.current?.id) {
                        if mode.id != m.current?.id { m.apply(mode) }
                    }
                }
                if g.modes.count == 1 {
                    Text("当前分辨率只有一个刷新率").font(.system(size: 11)).foregroundColor(.secondary)
                }
            } else {
                Text("无法读取刷新率").font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
    }

    private var resolutionListCard: some View {
        let rows = m.visibleScales
        return Card(m.hasHiDPI ? "HiDPI（清晰）" : "普通分辨率",
                    subtitle: m.hasHiDPI ? "看起来像（另含原生分辨率）" : "仅列出驱动上报模式，不保证切换生效；以读回结果为准",
                    icon: "plus.magnifyingglass", trailing: "\(rows.count) 种") {
            ScrollView(.vertical, showsIndicators: rows.count > 7) {
                VStack(spacing: 2) {
                    ForEach(rows) { o in resolutionRow(o) }
                }
            }
            .frame(height: min(CGFloat(rows.count) * 36, 260))
        }
    }

    private func resolutionRow(_ o: ScaleOption) -> some View {
        let isCur = m.isCurrentScale(o)
        let isNative = o.width == m.native.width && o.height == m.native.height && !o.hiDPI
        return Button {
            if !isCur { m.applyScale(o) }
        } label: {
            HStack(spacing: 8) {
                (Text("看起来像 ").foregroundColor(.secondary).font(.system(size: 11))
                 + Text("\(o.width) × \(o.height)").font(.system(size: 13, weight: isCur ? .semibold : .medium)))
                    .monospacedDigit()
                Spacer(minLength: 4)
                Text(isNative ? "原生" : "\(o.percent)%").font(.system(size: 11)).foregroundColor(.secondary).monospacedDigit()
                TagLabel(text: o.hiDPI ? "清晰" : "普通", color: o.hiDPI ? .green : .secondary)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.accent).opacity(isCur ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isCur ? Theme.accent.opacity(0.16) : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var hidpiCard: some View {
        Card("HiDPI 覆盖文件", subtitle: m.hidpiInstalled ? "已安装" : "未安装", icon: "wand.and.stars") {
            HStack(spacing: 8) {
                PillButton(title: m.hidpiInstalled ? "重新写入" : "启用 HiDPI", icon: "plus.circle",
                           enabled: !m.selectedIsBuiltin) { m.installHiDPI() }
                PillButton(title: "移除", icon: "trash", enabled: m.hidpiInstalled && !m.selectedIsBuiltin) { m.removeHiDPI() }
            }
            Text("需要管理员密码，重新插拔显示器或注销/重启后生效。NVIDIA 黑苹果驱动可能不识别此设置。")
                .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 设置

    @ViewBuilder private var settingsTab: some View {
        textSizeCard
        Card {
            Toggle(isOn: Binding(get: { m.autoOn }, set: { m.setAuto($0) })) {
                toggleLabel("自动仅外屏", "确认一次后，登录和接屏自动关闭内屏；拔屏恢复，失败暂停")
            }
            .toggleStyle(.switch).tint(Theme.accent)
            Divider().opacity(0.5)
            Toggle(isOn: Binding(get: { m.loginOn }, set: { m.setLogin($0) })) {
                toggleLabel("登录时启动", "通过 LaunchAgent 在登录后自动运行")
            }
            .toggleStyle(.switch).tint(Theme.accent)
        }
        Card("最近自动操作", icon: "clock.arrow.circlepath") {
            Text(m.lastAuto.isEmpty ? "暂无" : m.lastAuto)
                .font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Card("显示器", icon: "display.2", trailing: "\(m.displays.count) 台") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(m.displays) { d in
                    HStack(spacing: 6) {
                        Image(systemName: d.isBuiltin ? "laptopcomputer" : "display").foregroundColor(.secondary).frame(width: 16)
                        Text(d.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("ID \(String(d.id))").font(.system(size: 10)).foregroundColor(.secondary).monospacedDigit()
                        if d.isMain { TagLabel(text: "主屏", color: Theme.accent) }
                    }
                }
            }
        }
        Card("关于", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 4) {
                infoRow("版本", m.version)
                infoRow("系统", ProcessInfo.processInfo.operatingSystemVersionString)
                infoRow("关闭内建屏私有接口", DisplayManager.privateDisableAvailable ? "符号存在（效果待验收）" : "符号不存在")
            }
        }
    }

    private var textSizeCard: some View {
        Card("文字大小", subtitle: "对应 系统设置 → 辅助功能 → 显示 → 文字大小（全局）", icon: "textformat.size",
             trailing: TextSize.option(for: m.textSizeGlobal).map { $0.title } ?? m.textSizeGlobal) {
            PillGrid(items: TextSizeOption.curated, columns: 5) { o in
                PillButton(title: o.title, selected: m.textSizeGlobal == o.rawValue) {
                    if m.textSizeGlobal != o.rawValue { m.setTextSize(o.rawValue) }
                }
                .help("\(o.rawValue) · 约 \(o.pointLabel)")
            }
            WideButton(title: "在系统设置中打开", icon: "gearshape") { m.openTextSizeSettings() }
            Text("写入后访达/邮件等支持的 App 会跟进；部分软件要重新打开")
                .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggleLabel(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(sub).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
            Text(v).font(.system(size: 12)).lineLimit(1)
        }
    }
}
