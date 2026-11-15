import SwiftUI

/// 5 星评分（支持半星）
struct StarRating: View {
    let score: Double
    var size: CGFloat = 16

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: symbol(for: Double(i)))
                    .font(.system(size: size))
                    .foregroundStyle(.yellow)
            }
        }
        .accessibilityLabel(Text(String(format: "%.1f 分，满分 5 分", score)))
    }

    private func symbol(for i: Double) -> String {
        if score >= i { return "star.fill" }
        if score >= i - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

struct ScoreCard: View {
    let title: String
    let score: Double?
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let score {
                    Text(String(format: "%.1f", score))
                        .font(.title2.bold())
                        .foregroundStyle(Self.color(for: score))
                    Text("/ 5").foregroundStyle(.secondary)
                } else {
                    Text("未评分").foregroundStyle(.secondary)
                }
            }
            if let score { StarRating(score: score) }
            if !reason.isEmpty {
                Text(reason).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    static func color(for score: Double) -> Color {
        switch score {
        case 4...: return .green
        case 3..<4: return .teal
        case 2..<3: return .orange
        default: return .red
        }
    }
}
