import SwiftUI

/// 结果页的「营养成分」区块：本机解析营养成分表，显示占每日参考量的比例
struct NutritionSection: View {
    let facts: NutritionFacts
    let profile: UserProfile

    @State private var showPackage = false

    private var factor: Double { showPackage ? (facts.packageFactor ?? 1) : 1 }

    var body: some View {
        Section {
            if facts.packageFactor != nil {
                Picker("计量", selection: $showPackage) {
                    Text(facts.basisTitle).tag(false)
                    Text("整包（\(Int(facts.netContent ?? 0))\(facts.isLiquid ? "ml" : "g")）").tag(true)
                }
                .pickerStyle(.segmented)
            }
            ForEach(facts.items, id: \.self) { item in
                NutrientRow(item: item, factor: factor, isLiquid: facts.isLiquid,
                            reference: item.nutrient.dailyReference(for: profile),
                            per100Level: facts.basis == .perServing ? nil
                                : item.nutrient.level(per100: item.value, isLiquid: facts.isLiquid))
            }
        } header: {
            Text("营养成分（本机解析）")
        } footer: {
            Text(footerText)
        }
    }

    private var footerText: String {
        var s = "百分比 = 占每日参考量（中国营养素参考值 NRV，糖按膳食指南）。高/中/低按每100g（饮料每100ml）的通用标准。"
        if profile.isActive {
            if Nutrient.energyTargetKJ(profile) != nil {
                s += "能量参考量已按你的身高体重、年龄和目标估算。"
            }
            if !profile.goals.isEmpty { s += "糖、钠等上限已按你的健康目标调整。" }
        }
        s += "解析自识别文字，请以包装为准。"
        return s
    }
}

private struct NutrientRow: View {
    let item: NutrientValue
    let factor: Double
    let isLiquid: Bool
    let reference: Double
    let per100Level: NutrientLevel?

    private var value: Double { item.value * factor }
    private var percent: Double { reference > 0 ? value / reference : 0 }

    private var barColor: Color {
        if !item.nutrient.isLimit { return .green }
        switch per100Level {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        case nil: return percent > 0.3 ? .orange : .teal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.nutrient.title)
                if let level = per100Level {
                    Text(level.title)
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(barColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(barColor)
                }
                Spacer()
                Text(NutrientValue(nutrient: item.nutrient, value: value).displayValue)
                    .font(.callout.monospacedDigit())
                Text("\(Int((percent * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(barColor)
                        .frame(width: geo.size.width * min(1, percent))
                }
            }
            .frame(height: 6)
            .accessibilityLabel("\(item.nutrient.title)占每日参考量 \(Int((percent * 100).rounded()))%")
        }
        .padding(.vertical, 2)
    }
}
