import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScanRecord.createdAt, order: .reverse) private var records: [ScanRecord]

    @State private var searchText = ""
    @State private var categoryFilter: ProductCategory?
    @State private var favoritesOnly = false
    @State private var isSelecting = false
    @State private var selection = Set<PersistentIdentifier>()
    @State private var comparePair: ComparePair?

    private var filtered: [ScanRecord] {
        let q = searchText.trimmed.lowercased()
        return records.filter { r in
            (categoryFilter == nil || r.category == categoryFilter) &&
            (!favoritesOnly || r.isFavorite) &&
            (q.isEmpty || r.productName.lowercased().contains(q) || r.ocrText.lowercased().contains(q) ||
             (r.result?.verdict.lowercased().contains(q) ?? false))
        }
    }

    private var selectedRecords: [ScanRecord] {
        records.filter { selection.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView("还没有记录",
                                           systemImage: "tray",
                                           description: Text("在「扫描」页分析过的商品会保存在这里"))
                } else {
                    list
                }
            }
            .navigationTitle("历史记录")
            .navigationDestination(for: ScanRecord.self) { ResultView(record: $0) }
            .sheet(item: $comparePair) { pair in
                NavigationStack { CompareView(a: pair.a, b: pair.b) }
            }
        }
    }

    private var list: some View {
        List(selection: isSelecting ? $selection : nil) {
            Section {
                filterBar
            }
            if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
            ForEach(filtered) { record in
                if isSelecting {
                    HistoryRow(record: record).tag(record.persistentModelID)
                } else {
                    NavigationLink(value: record) {
                        HistoryRow(record: record)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            record.isFavorite.toggle()
                            try? context.save()
                        } label: {
                            Label(record.isFavorite ? "取消收藏" : "收藏", systemImage: record.isFavorite ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            context.delete(record)
                            try? context.save()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
        .searchable(text: $searchText, prompt: "搜索商品名、成分或结论")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "取消" : "对比") {
                    isSelecting.toggle()
                    selection = []
                }
            }
            if isSelecting {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        let pick = selectedRecords
                        if pick.count == 2 {
                            comparePair = ComparePair(a: pick[0], b: pick[1])
                            isSelecting = false
                            selection = []
                        }
                    } label: {
                        Text(selection.count == 2 ? "对比这 2 个商品" : "选择 2 个商品进行对比（已选 \(selection.count)）")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.count != 2)
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部", selected: categoryFilter == nil && !favoritesOnly) {
                    categoryFilter = nil; favoritesOnly = false
                }
                chip("收藏", systemImage: "star.fill", selected: favoritesOnly) { favoritesOnly.toggle() }
                ForEach(ProductCategory.allCases) { c in
                    chip(c.shortTitle, systemImage: c.icon, selected: categoryFilter == c) {
                        categoryFilter = categoryFilter == c ? nil : c
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
    }

    private func chip(_ title: String, systemImage: String? = nil, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(selected ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
            .foregroundStyle(selected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct ComparePair: Identifiable {
    let a: ScanRecord
    let b: ScanRecord
    var id: String { "\(a.id)-\(b.id)" }
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
                HStack(spacing: 4) {
                    if record.isFavorite {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                    }
                    Text(record.productName.isEmpty ? "未命名商品" : record.productName)
                        .font(.headline)
                        .lineLimit(1)
                }
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
