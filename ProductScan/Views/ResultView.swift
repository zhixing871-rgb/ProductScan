import SwiftUI

struct ResultView: View {
    let record: ScanRecord

    var body: some View {
        if let r = record.result {
            List {
                header(r)

                Section("评分") {
                    ScoreCard(title: record.category.primaryScoreLabel,
                              score: r.primaryScore,
                              reason: r.primaryScoreReason)
                    if record.price != nil {
                        ScoreCard(title: "性价比", score: r.valueScore, reason: r.valueScoreReason ?? "")
                    } else {
                        Text("未填写价格，未进行性价比评分").foregroundStyle(.secondary).font(.callout)
                    }
                }

                Section("总体分析") {
                    Text(r.summary).font(.callout)
                }

                if !r.ingredients.isEmpty {
                    Section("成分解读（\(r.ingredients.count)）") {
                        ForEach(Array(r.ingredients.enumerated()), id: \.offset) { _, item in
                            IngredientRow(item: item)
                        }
                    }
                }

                bulletSection("短期影响", r.shortTermEffects, icon: "clock", tint: .orange)
                bulletSection("长期影响", r.longTermEffects, icon: "calendar", tint: .purple)
                bulletSection("适合人群", r.suitableFor, icon: "checkmark.circle", tint: .green)
                bulletSection("慎用 / 不适合", r.avoidFor, icon: "exclamationmark.circle", tint: .red)

                if let company = r.company {
                    Section("品牌 / 公司") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(company.name).font(.headline)
                            Text(company.background).font(.callout)
                            Text(company.reputation).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }

                bulletSection("替代建议", r.alternatives, icon: "arrow.triangle.swap", tint: .blue)

                if !record.ocrText.isEmpty {
                    Section {
                        DisclosureGroup("识别原文") {
                            Text(record.ocrText).font(.footnote).textSelection(.enabled)
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        if let modelName = record.modelName {
                            Text("分析模型：\(modelName)")
                        }
                        Text("分析由 AI 根据标签文字生成，可信度：\(r.confidence)。仅供参考，不构成医疗或专业建议；公司信息可能不是最新的，请自行核实。")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(record.productName.isEmpty ? r.productName : record.productName)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("结果解析失败", systemImage: "exclamationmark.triangle")
        }
    }

    private func header(_ r: AnalysisResult) -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                if let data = record.imageData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label(record.category.title, systemImage: record.category.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(r.productName).font(.headline)
                    Text(r.verdict)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ScoreCard.color(for: r.primaryScore))
                    if let price = record.price {
                        Text("价格：\(price, specifier: "%.2f") \(record.currency)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let s = record.sourceURL, let url = URL(string: s) {
                        Link(destination: url) {
                            Label("查看商品页面", systemImage: "link")
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bulletSection(_ title: String, _ items: [String], icon: String, tint: Color) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                    Label {
                        Text(text).font(.callout)
                    } icon: {
                        Image(systemName: icon).foregroundStyle(tint)
                    }
                }
            }
        }
    }
}

struct IngredientRow: View {
    let item: IngredientItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.name).font(.body.weight(.medium))
                Spacer()
                Text(item.risk.title)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(item.risk.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(item.risk.color)
            }
            Text(item.function).font(.caption).foregroundStyle(.secondary)
            if !item.note.isEmpty {
                Text(item.note).font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}
