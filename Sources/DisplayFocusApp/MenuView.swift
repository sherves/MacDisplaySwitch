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
    @State var tab: MenuTab = .overview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            tabBar
            AutoHeightScroll(maxHeight: 440) {
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
            if m.trialPending { trialBanner }
            if !m.message.isEmpty && !m.trialPending {
                Text(m.message)
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardFill))
            }
            footer
        }
        .padding(18)
        .frame(width: 408)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Theme.accent)
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: 12) {
            BrandIcon().frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("DisplayFocus").font(.system(size: 18, weight: .bold, design: .rounded))
                Text("让目光，专注一屏").font(.system(size: 11)).foregroundColor(.secondary)
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
                    HStack(spacing: 5) {
                        Image(systemName: t.icon).font(.system(size: 14, weight: .medium))
                        Text(t.title).font(.system(size: 11, weight: sel ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
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
            RoundIconButton(systemName: "arrow.clockwise.circle", size: 28, help: "重新启动 DisplayFocus") { NSApp.terminate(nil) }
        }
    }

    // MARK: - 概览

    @ViewBuilder private var overviewTab: some View {
        previewCard
        Card("内建屏", icon: "laptopcomputer", trailing: m.builtinState.zh) {
            HStack(spacing: 8) {
                PillButton(title: "立即仅外屏", icon: "moon.zzz", selected: true,
                           enabled: m.canUseExternalOnly && !m.trialPending) { m.useExternalOnly() }
                PillButton(title: "临时恢复内屏", icon: "sun.max") { m.recoverDisplay() }
            }
            Text("登录后自动仅外屏，驱动更新无需重新确认。拔掉外屏时恢复内屏，接回后自动关闭。")
                .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Card("自动仅外屏", icon: "bolt.shield") {
            Text(AutomaticDisplayPolicy.status)
                .font(.system(size: 12)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TagLabel(text: m.autoOn ? "自动模式已开启" : "本次临时恢复", color: m.autoOn ? Theme.accent : .secondary)
                Spacer()
                Button("管理设置") { tab = .settings }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundColor(Theme.accent)
            }
        }
        brightnessCard(compact: true)
    }

    private var trialBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "clock.arrow.circlepath").foregroundColor(.orange)
                Text("外屏显示正常吗？").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(m.trialSeconds) 秒").font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
            }
            Text("确认画面、鼠标和远控可用。超时将尝试恢复内屏。")
                .font(.system(size: 11)).foregroundColor(.secondary)
            HStack {
                PillButton(title: "外屏正常，保留", icon: "checkmark", selected: true) { m.confirmDisable() }
                PillButton(title: "立即恢复", icon: "arrow.uturn.backward") { m.recoverDisplay() }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.3)))
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: m.selectedIsBuiltin ? "laptopcomputer" : "display")
                Text(m.selectedDisplay?.name ?? "未连接显示器").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                if m.selectedDisplay?.isMain == true { TagLabel(text: "主显示器", color: .white) }
            }
            if let c = m.current {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(c.width)).font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text("×").font(.system(size: 20, weight: .light)).opacity(0.55)
                    Text(String(c.height)).font(.system(size: 34, weight: .semibold, design: .rounded))
                }.monospacedDigit().minimumScaleFactor(0.8).lineLimit(1)
                HStack {
                    Label(ModeInfo.hzText(c.refreshRate), systemImage: "waveform.path").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(c.isHiDPI ? "HiDPI · 清晰显示" : "标准像素显示").font(.system(size: 11)).opacity(0.75)
                }
            } else {
                Text("等待显示器连接").font(.system(size: 22, weight: .semibold))
                Text("连接后即可查看画面与显示设置").font(.system(size: 12)).opacity(0.75)
            }
        }
        .foregroundColor(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [Color(red: 0.20, green: 0.24, blue: 0.55), Color(red: 0.12, green: 0.15, blue: 0.30)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Theme.aqua.opacity(0.13)).frame(width: 160, height: 160).offset(x: 65, y: -65)
                Circle().strokeBorder(Color.white.opacity(0.07), lineWidth: 1).frame(width: 220, height: 220).offset(x: 70, y: -80)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
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
                        icon: "sun.min", valueText: "\(m.light.brightness)%", value: m.light.brightness) { m.setBrightness($0) }
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
        Card("自动仅外屏", icon: "bolt.fill", trailing: "持续开启") {
            Text("登录后自动运行，外屏连接稳定后关闭内屏。驱动更新、重新登录和外屏重连均无需点击确认。")
                .font(.system(size: 12)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider().opacity(0.5)
            infoRow("登录时启动", m.loginOn ? "已开启" : "正在设置")
            infoRow("自动切换", m.autoOn ? "已开启" : "本次临时恢复内屏")
            if !m.autoOn {
                WideButton(title: "恢复自动仅外屏", icon: "display") { m.setAuto(true) }
            }
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
