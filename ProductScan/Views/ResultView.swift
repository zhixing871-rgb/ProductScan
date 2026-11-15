import SwiftUI

import SwiftData

struct ResultView: View {
    let record: ScanRecord

    @Environment(\.modelContext) private var context
    @State private var reanalyzeStage: AnalysisStage?
    @State private var reanalyzeStarted: Date?
    @State private var reanalyzeTask: Task<Void, Never>?
    @State private var reanalyzeError: String?
    @State private var newRecord: ScanRecord?
    @State private var shareImage: UIImage?
    @State private var profile = UserProfile.load()

    var body: some View {
        if let r = record.result {
            List {
                if reanalyzeTask != nil {
                    Section {
                        AnalysisProgressView(stage: reanalyzeStage, startedAt: reanalyzeStarted) {
                            reanalyzeTask?.cancel()
                        }
                    } header: {
                        Text("正在用 \(AISettings.current().model) 重新分析")
                    }
                }
                if let reanalyzeError {
                    Section {
                        Label(reanalyzeError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
                header(r)
                allergenBanner
                personalSection(r)

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

                if let facts = NutritionParser.parse(record.ocrText, spec: record.specText ?? "") {
                    NutritionSection(facts: facts, profile: profile)
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
                        if let usage = record.usage {
                            Text("本次用量：输入 \(usage.inputTokens) + 输出 \(usage.outputTokens) tokens"
                                 + (record.costText.map { "，\($0)（按公开价估算）" } ?? ""))
                        }
                        Text("分析由 AI 根据标签文字生成，可信度：\(r.confidence)。仅供参考，不构成医疗或专业建议；公司信息可能不是最新的，请自行核实。")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(record.productName.isEmpty ? r.productName : record.productName)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { profile = UserProfile.load() }
            .task { shareImage = ShareCardView.render(record: record, result: r) }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        record.isFavorite.toggle()
                        try? context.save()
                    } label: {
                        Image(systemName: record.isFavorite ? "star.fill" : "star")
                    }
                    .accessibilityLabel(record.isFavorite ? "取消收藏" : "收藏")

                    if let shareImage {
                        ShareLink(item: Image(uiImage: shareImage),
                                  preview: SharePreview(record.productName.isEmpty ? r.productName : record.productName,
                                                        image: Image(uiImage: shareImage))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }

                    Menu {
                        Button {
                            reanalyze()
                        } label: {
                            Label("用当前模型重新分析", systemImage: "arrow.clockwise")
                        }
                        .disabled(reanalyzeTask != nil)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(item: $newRecord) { ResultView(record: $0) }
        } else {
            ContentUnavailableView("结果解析失败", systemImage: "exclamationmark.triangle")
        }
    }

    private func reanalyze() {
        reanalyzeError = nil
        reanalyzeStarted = .now
        reanalyzeStage = .preparing
        reanalyzeTask = Task {
            defer { reanalyzeTask = nil; reanalyzeStage = nil }
            do {
                newRecord = try await AnalysisRunner.reanalyze(record, context: context) { reanalyzeStage = $0 }
            } catch is CancellationError {
                reanalyzeError = "已取消"
            } catch let e as URLError where e.code == .cancelled {
                reanalyzeError = "已取消"
            } catch {
                reanalyzeError = error.localizedDescription
            }
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

    /// 本地检查：配料里命中用户设置的过敏原（不依赖 AI，实时按当前个人信息计算）
    @ViewBuilder
    private var allergenBanner: some View {
        let hits = AllergenChecker.check(record.ocrText + " " + record.productName, profile: profile)
        if !hits.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("可能含有你的过敏原", systemImage: "exclamationmark.octagon.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    ForEach(hits, id: \.self) { hit in
                        Text("\(hit.name)：\(hit.words.joined(separator: "、"))")
                            .font(.callout)
                    }
                    Text("由本机按关键词检查，可能有误判，请以包装上的过敏原信息为准。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.red.opacity(0.08))
        }
    }

    @ViewBuilder
    private func personalSection(_ r: AnalysisResult) -> some View {
        if r.personalVerdict != nil || !r.personalWarnings.isEmpty || r.personalAdvice != nil {
            Section("针对你") {
                if let verdict = r.personalVerdict {
                    HStack {
                        Text("是否适合你")
                        Spacer()
                        Text(verdict)
                            .font(.subheadline.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Self.verdictColor(verdict).opacity(0.15), in: Capsule())
                            .foregroundStyle(Self.verdictColor(verdict))
                    }
                }
                ForEach(Array(r.personalWarnings.enumerated()), id: \.offset) { _, text in
                    Label {
                        Text(text).font(.callout)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                if let advice = r.personalAdvice, !advice.isEmpty {
                    Text(advice).font(.callout)
                }
            }
        }
    }

    static func verdictColor(_ v: String) -> Color {
        if v.contains("避免") { return .red }
        if v.contains("慎用") { return .orange }
        if v.contains("适量") { return .teal }
        if v.contains("适合") { return .green }
        return .gray
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
