import SwiftUI

/// 「是否值得」的视觉风格：取自 App 图标的深海蓝 + 青蓝渐变，配绿色（安全）和金色（性价比）
enum Theme {
    static let blue = Color(red: 0.153, green: 0.471, blue: 0.957)      // #2778F4
    static let cyan = Color(red: 0.133, green: 0.765, blue: 0.933)      // #22C3EE
    static let navy = Color(red: 0.035, green: 0.071, blue: 0.157)      // #091228
    static let green = Color(red: 0.180, green: 0.780, blue: 0.420)
    static let gold = Color(red: 0.980, green: 0.737, blue: 0.180)

    static let brandGradient = LinearGradient(colors: [blue, cyan], startPoint: .leading, endPoint: .trailing)
    static let heroGradient = LinearGradient(colors: [navy, Color(red: 0.07, green: 0.18, blue: 0.40)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    static let cornerRadius: CGFloat = 20

    /// 页面背景：系统分组背景，顶部带一点品牌蓝
    static var pageBackground: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
            LinearGradient(colors: [blue.opacity(0.14), cyan.opacity(0.05), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 360)
        }
        .ignoresSafeArea()
    }

    /// 分数颜色（与评分含义一致）
    static func scoreColor(_ score: Double) -> Color {
        switch score {
        case 4...: return green
        case 3..<4: return Color(red: 0.10, green: 0.66, blue: 0.80)
        case 2..<3: return .orange
        default: return .red
        }
    }

    /// 分数对应的一句话
    static func scoreWord(_ score: Double) -> String {
        switch score {
        case 4.5...: return "很值得"
        case 4..<4.5: return "值得"
        case 3..<4: return "还可以"
        case 2..<3: return "一般"
        default: return "不推荐"
        }
    }
}

// MARK: - 卡片

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

/// 卡片标题：彩色小图标 + 文字
struct CardTitle: View {
    let title: String
    let icon: String
    var tint: Color = Theme.blue
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).font(.headline)
            Spacer()
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// List 分区标题的样式（结果页等仍用 List 的页面）
struct SectionLabel: View {
    let title: String
    let icon: String
    var tint: Color = Theme.blue

    var body: some View {
        Label {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
        } icon: {
            Image(systemName: icon).foregroundStyle(tint)
        }
        .textCase(nil)
    }
}

// MARK: - 按钮

/// 主按钮：品牌渐变胶囊
struct GradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background {
                Capsule().fill(isEnabled ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.gray.opacity(0.35)))
            }
            .shadow(color: Theme.blue.opacity(isEnabled ? 0.35 : 0), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// 次按钮：浅色底
struct SoftButtonStyle: ButtonStyle {
    var tint: Color = Theme.blue
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? tint : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tint.opacity(isEnabled ? 0.12 : 0.05),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - 评分环

struct ScoreRing: View {
    let score: Double?
    var size: CGFloat = 86
    var lineWidth: CGFloat = 9

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)
            if let score {
                Circle()
                    .trim(from: 0, to: score / 5)
                    .stroke(Theme.scoreColor(score).gradient,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", score))
                        .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.scoreColor(score))
                    Text("/ 5").font(.system(size: size * 0.12)).foregroundStyle(.secondary)
                }
            } else {
                Text("—").font(.system(size: size * 0.28, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(score.map { String(format: "%.1f 分，满分 5 分", $0) } ?? "未评分")
    }
}

/// 小分数徽章（历史列表用）
struct ScoreBadge: View {
    let score: Double

    var body: some View {
        Text(String(format: "%.1f", score))
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(Theme.scoreColor(score))
            .frame(width: 44, height: 44)
            .background(Theme.scoreColor(score).opacity(0.12), in: Circle())
            .overlay(Circle().strokeBorder(Theme.scoreColor(score).opacity(0.35), lineWidth: 2))
    }
}

/// 彩色胶囊标签
struct Pill: View {
    let text: String
    var icon: String? = nil
    var tint: Color = Theme.blue

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
        .foregroundStyle(tint)
    }
}

/// 输入框外观：圆角浅底
struct FieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    func fieldStyle() -> some View { modifier(FieldBackground()) }
}
