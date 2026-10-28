import SwiftUI

/// 视觉主题：圆润卡片 + 橙色强调（改这里即可换色，例如 Color.accentColor 跟随系统）
enum Theme {
    static let accent = Color.orange
    static let cardRadius: CGFloat = 14
    static let cardFill = Color.primary.opacity(0.05)
    static let cardStroke = Color.primary.opacity(0.08)
    static let subtleFill = Color.primary.opacity(0.07)
}

/// 圆角卡片，可带标题 / 副标题 / 右侧说明
struct Card<Content: View>: View {
    var title: String?
    var subtitle: String?
    var icon: String?
    var trailing: String?
    let content: Content

    init(_ title: String? = nil, subtitle: String? = nil, icon: String? = nil, trailing: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.icon = icon; self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(alignment: .center, spacing: 8) {
                    if let icon {
                        Image(systemName: icon).font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                            .frame(width: 18)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        if let subtitle {
                            Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    if let trailing {
                        Text(trailing).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.cardStroke, lineWidth: 1))
    }
}

/// 胶囊 / 圆角选择按钮。vertical = 图标在上、文字在下（场景按钮）
struct PillButton: View {
    let title: String
    var icon: String? = nil
    var selected = false
    var vertical = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if vertical {
                    VStack(spacing: 5) {
                        if let icon { Image(systemName: icon).font(.system(size: 15, weight: .medium)) }
                        Text(title).font(.system(size: 12, weight: .medium))
                    }
                    .padding(.vertical, 10)
                } else {
                    HStack(spacing: 4) {
                        if let icon { Image(systemName: icon).font(.system(size: 11, weight: .medium)) }
                        Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                    .padding(.vertical, 7)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .foregroundColor(selected ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: vertical ? 12 : 10, style: .continuous)
                    .fill(selected ? Theme.accent : Theme.subtleFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: vertical ? 12 : 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// 等宽网格排列的胶囊按钮
struct PillGrid<Item: Hashable, Cell: View>: View {
    let items: [Item]
    var columns = 4
    @ViewBuilder let cell: (Item) -> Cell
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(items, id: \.self) { cell($0) }
        }
    }
}

/// 小圆形图标按钮（− / + / 刷新 / 退出）
struct RoundIconButton: View {
    let systemName: String
    var size: CGFloat = 26
    var help: String = ""
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.subtleFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// 卡片内的滑杆：标题 + 说明 + 右侧大数值 + − 滑杆 +
struct ValueSlider: View {
    let title: String
    var caption: String? = nil
    var icon: String? = nil
    let valueText: String
    let value: Int
    var range: ClosedRange<Int> = 0...100
    var stepButton = 5
    var leftLabel: String? = nil
    var rightLabel: String? = nil
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundColor(.secondary).frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if let caption {
                        Text(caption).font(.system(size: 11)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                Text(valueText).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            HStack(spacing: 8) {
                RoundIconButton(systemName: "minus", size: 24) { onChange(max(range.lowerBound, value - stepButton)) }
                if let leftLabel { Text(leftLabel).font(.system(size: 11)).foregroundColor(.secondary) }
                Slider(value: Binding(get: { Double(value) }, set: { onChange(Int($0.rounded())) }),
                       in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                    .tint(Theme.accent)
                    .controlSize(.small)
                if let rightLabel { Text(rightLabel).font(.system(size: 11)).foregroundColor(.secondary) }
                RoundIconButton(systemName: "plus", size: 24) { onChange(min(range.upperBound, value + stepButton)) }
            }
        }
    }
}

/// 宽按钮（恢复软件调整等）
struct WideButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 小标签（清晰 / 普通）
struct TagLabel: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundColor(color)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

/// 测量内容高度，让标签页内容在不超过上限时自适应高度
struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct AutoHeightScroll<Content: View>: View {
    var maxHeight: CGFloat
    let content: Content
    @State private var height: CGFloat = 300
    init(maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight; self.content = content()
    }
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content.background(GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) })
        }
        .frame(height: min(max(height, 40), maxHeight))
        .onPreferenceChange(HeightKey.self) { h in height = h }
    }
}
