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
                    ContentUnavailableView {
                    Label("还没有记录", systemImage: "tray")
                } description: {
                    Text("在「扫描」页分析过的商品会保存在这里")
                }
                .background(Theme.pageBackground)
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
        .listSectionSpacing(12)
        .scrollContentBackground(.hidden)
        .background(Theme.pageBackground)
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
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
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
            .background {
                Capsule().fill(selected ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            }
            .foregroundStyle(selected ? .white : .primary)
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
            Group {
                if let data = record.imageData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: record.category.icon)
                        .font(.title3)
                        .foregroundStyle(Theme.blue)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.blue.opacity(0.1))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if record.isFavorite {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.gold)
                    }
                    Text(record.productName.isEmpty ? (record.result?.productName ?? "未命名商品") : record.productName)
                        .font(.headline)
                        .lineLimit(1)
                }
                if let verdict = record.result?.verdict {
                    Text(verdict)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(record.category.shortTitle)
                    if let v = record.valueScore {
                        Text("性价比 \(String(format: "%.1f", v))")
                            .foregroundStyle(Theme.scoreColor(v))
                    }
                    Text(record.createdAt, format: .dateTime.month().day())
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            ScoreBadge(score: record.primaryScore)
        }
        .padding(.vertical, 4)
    }
}
