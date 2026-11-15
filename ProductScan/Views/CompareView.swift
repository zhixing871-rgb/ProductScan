import SwiftUI

/// 两个商品并排对比
struct CompareView: View {
    let a: ScanRecord
    let b: ScanRecord

    @Environment(\.dismiss) private var dismiss
    private let profile = UserProfile.load()

    private var ra: AnalysisResult? { a.result }
    private var rb: AnalysisResult? { b.result }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    productHeader(a, ra)
                    Divider()
                    productHeader(b, rb)
                }
            }

            Section("评分") {
                row("综合评分", ra?.primaryScore, rb?.primaryScore, higherIsBetter: true) { String(format: "%.1f", $0) }
                row("性价比", ra?.valueScore, rb?.valueScore, higherIsBetter: true) { String(format: "%.1f", $0) }
                row("价格", a.price, b.price, higherIsBetter: false) { String(format: "%.2f", $0) }
                if ra?.personalVerdict != nil || rb?.personalVerdict != nil {
                    textRow("是否适合你", ra?.personalVerdict ?? "—", rb?.personalVerdict ?? "—")
                }
            }

            Section("成分风险") {
                row("高风险成分", count(ra, .high), count(rb, .high), higherIsBetter: false) { "\(Int($0)) 个" }
                row("需注意成分", count(ra, .medium), count(rb, .medium), higherIsBetter: false) { "\(Int($0)) 个" }
                row("成分总数", ra.map { Double($0.ingredients.count) }, rb.map { Double($0.ingredients.count) },
                    higherIsBetter: nil) { "\(Int($0)) 个" }
                textRow("过敏原提醒", allergenText(a), allergenText(b))
            }

            let na = NutritionParser.parse(a.ocrText, spec: a.specText ?? "")
            let nb = NutritionParser.parse(b.ocrText, spec: b.specText ?? "")
            if na != nil || nb != nil {
                Section {
                    ForEach([Nutrient.energy, .protein, .fat, .saturatedFat, .sugar, .sodium, .fiber], id: \.self) { n in
                        if na?.value(n) != nil || nb?.value(n) != nil {
                            row(n.title, na?.value(n), nb?.value(n), higherIsBetter: n.isLimit ? false : true) {
                                NutrientValue(nutrient: n, value: $0).displayValue
                            }
                        }
                    }
                } header: {
                    Text("营养成分（\(na?.basisTitle ?? nb?.basisTitle ?? "每100g")）")
                } footer: {
                    if let na, let nb, na.basis != nb.basis {
                        Text("两个商品的营养表计量单位不同（\(na.basisTitle) / \(nb.basisTitle)），数值不能直接比较。")
                    }
                }
            }

            Section("需要留意的成分") {
                HStack(alignment: .top) {
                    riskList(ra)
                    Divider()
                    riskList(rb)
                }
            }

            Section {
                Text("绿色表示这一项更好。评分由 AI 给出，不同模型、不同时间的结果可能有差异。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("商品对比")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
        }
    }

    // MARK: 组件

    private func productHeader(_ record: ScanRecord, _ r: AnalysisResult?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let data = record.imageData, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(height: 80).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text(record.productName.isEmpty ? (r?.productName ?? "未命名") : record.productName)
                .font(.subheadline.bold()).lineLimit(2)
            if let r {
                Text(r.verdict).font(.caption).foregroundStyle(ScoreCard.color(for: r.primaryScore)).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// higherIsBetter: true/false 决定谁标绿；nil 表示不比较
    private func row(_ title: String, _ x: Double?, _ y: Double?, higherIsBetter: Bool?,
                     format: @escaping (Double) -> String) -> some View {
        let better: Int? = {
            guard let x, let y, x != y, let h = higherIsBetter else { return nil }
            return (x > y) == h ? 0 : 1
        }()
        return HStack {
            Text(title).font(.callout).frame(width: 92, alignment: .leading)
            cell(x.map(format) ?? "—", highlighted: better == 0)
            cell(y.map(format) ?? "—", highlighted: better == 1)
        }
    }

    private func textRow(_ title: String, _ x: String, _ y: String) -> some View {
        HStack {
            Text(title).font(.callout).frame(width: 92, alignment: .leading)
            cell(x, highlighted: false)
            cell(y, highlighted: false)
        }
    }

    private func cell(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.callout.monospacedDigit())
            .fontWeight(highlighted ? .semibold : .regular)
            .foregroundStyle(highlighted ? .green : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func count(_ r: AnalysisResult?, _ level: RiskLevel) -> Double? {
        r.map { Double($0.ingredients.filter { $0.risk == level }.count) }
    }

    private func allergenText(_ record: ScanRecord) -> String {
        let hits = AllergenChecker.check(record.ocrText + " " + record.productName, profile: profile)
        return hits.isEmpty ? "无" : hits.map(\.name).joined(separator: "、")
    }

    private func riskList(_ r: AnalysisResult?) -> some View {
        let items = r?.ingredients.filter { $0.risk == .high || $0.risk == .medium } ?? []
        return VStack(alignment: .leading, spacing: 4) {
            if items.isEmpty {
                Text("无").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { _, item in
                Text("• \(item.name)（\(item.risk.title)）")
                    .font(.caption)
                    .foregroundStyle(item.risk.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
