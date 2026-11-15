import SwiftUI

/// 分享用的结果卡片（渲染成图片）。不包含个人身份信息。
struct ShareCardView: View {
    let record: ScanRecord
    let result: AnalysisResult

    private var riskyIngredients: [IngredientItem] {
        result.ingredients.filter { $0.risk == .high || $0.risk == .medium }.prefix(6).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                if let data = record.imageData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label(record.category.title, systemImage: record.category.icon)
                        .font(.caption).foregroundStyle(.secondary)
                    Text(record.productName.isEmpty ? result.productName : record.productName)
                        .font(.title3.bold()).lineLimit(2)
                    Text(result.verdict)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ScoreCard.color(for: result.primaryScore))
                }
            }

            HStack(spacing: 24) {
                scoreBlock(record.category.primaryScoreLabel, result.primaryScore)
                if let v = result.valueScore { scoreBlock("性价比", v) }
            }

            if !riskyIngredients.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("需要留意的成分").font(.subheadline.bold())
                    FlowChips(items: riskyIngredients)
                }
            }

            Text(result.summary)
                .font(.callout)
                .lineLimit(6)

            Divider()
            HStack {
                Image(systemName: "text.viewfinder")
                Text("是否值得 · AI 分析仅供参考")
                Spacer()
                Text(record.createdAt, format: .dateTime.year().month().day())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 380)
        .background(Color(.systemBackground))
    }

    private func scoreBlock(_ title: String, _ score: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", score))
                    .font(.title.bold())
                    .foregroundStyle(ScoreCard.color(for: score))
                Text("/ 5").foregroundStyle(.secondary)
            }
            StarRating(score: score, size: 12)
        }
    }

    /// 把卡片渲染成图片
    @MainActor
    static func render(record: ScanRecord, result: AnalysisResult) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(record: record, result: result))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// 简单的换行标签
private struct FlowChips: View {
    let items: [IngredientItem]

    var body: some View {
        // 卡片宽度固定，按每行 3 个排列即可
        let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                        Text("\(item.name) · \(item.risk.title)")
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(item.risk.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(item.risk.color)
                    }
                }
            }
        }
    }
}
