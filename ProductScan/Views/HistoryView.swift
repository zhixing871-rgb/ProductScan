import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScanRecord.createdAt, order: .reverse) private var records: [ScanRecord]

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView("还没有记录",
                                           systemImage: "tray",
                                           description: Text("在「扫描」页分析过的商品会保存在这里"))
                } else {
                    List {
                        ForEach(records) { record in
                            NavigationLink(value: record) {
                                HistoryRow(record: record)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets { context.delete(records[i]) }
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("历史记录")
            .navigationDestination(for: ScanRecord.self) { ResultView(record: $0) }
        }
    }
}

private struct HistoryRow: View {
    let record: ScanRecord

    var body: some View {
        HStack(spacing: 12) {
            if let data = record.imageData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: record.category.icon)
                    .frame(width: 48, height: 48)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(record.productName.isEmpty ? "未命名商品" : record.productName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(record.category.primaryScoreLabel).font(.caption).foregroundStyle(.secondary)
                    StarRating(score: record.primaryScore, size: 11)
                }
                if let v = record.valueScore {
                    HStack(spacing: 6) {
                        Text("性价比").font(.caption).foregroundStyle(.secondary)
                        StarRating(score: v, size: 11)
                    }
                }
            }
            Spacer()
            Text(record.createdAt, format: .dateTime.month().day())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
