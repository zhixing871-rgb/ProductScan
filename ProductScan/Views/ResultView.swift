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
    @State private var followUp: FollowUpStart?

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
                hero(r)
                allergenBanner

                Section {
                    Text(r.summary).font(.callout).lineSpacing(3)
                } header: {
                    SectionLabel(title: "总体分析", icon: "text.quote")
                }

                personalSection(r)


                if let facts = NutritionParser.parse(record.ocrText, spec: record.specText ?? "") {
                    NutritionSection(facts: facts, profile: profile)
                }

                followUpSection
                ShoppingSection(record: record)

                if !r.ingredients.isEmpty {
                    Section {
                        ForEach(Array(r.ingredients.enumerated()), id: \.offset) { _, item in
                            IngredientRow(item: item)
                        }
                    } header: {
                        SectionLabel(title: "\(record.category.ingredientsLabel)（\(r.ingredients.count)）",
                                     icon: "list.bullet.rectangle.portrait", tint: .indigo)
                    }
                }

                bulletSection("短期影响", r.shortTermEffects, icon: "clock", tint: .orange)
                bulletSection("长期影响", r.longTermEffects, icon: "calendar", tint: .purple)
                bulletSection("适合人群", r.suitableFor, icon: "checkmark.circle", tint: .green)
                bulletSection("慎用 / 不适合", r.avoidFor, icon: "exclamationmark.circle", tint: .red)

                if let company = r.company {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(company.name).font(.headline)
                            Text(company.background).font(.callout)
                            Text(company.reputation).font(.callout).foregroundStyle(.secondary)
                        }
                    } header: {
                        SectionLabel(title: "品牌 / 公司", icon: "building.2", tint: .gray)
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
            .listSectionSpacing(14)
            .scrollContentBackground(.hidden)
            .background(Theme.pageBackground)
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
            .navigationDestination(item: $followUp) { FollowUpView(record: record, initialQuestion: $0.question) }
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

    /// 继续追问入口：点主按钮进入对话，点推荐问题直接发送
    private var followUpSection: some View {
        Section {
            Button {
                followUp = FollowUpStart(question: nil)
            } label: {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("继续追问").foregroundStyle(.primary)
                            let count = record.followUps.filter { $0.role == .user }.count
                            Text(count > 0 ? "已追问 \(count) 次，点开查看" : "例如：和同类产品有什么区别？值不值得买？")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
            }
            if record.followUps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(record.category.suggestedQuestions, id: \.self) { q in
                            Button(q) { followUp = FollowUpStart(question: q) }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    /// 顶部大卡片：商品 + 结论 + 两个评分环（深蓝底，呼应 App 图标）
    private func hero(_ r: AnalysisResult) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    if let data = record.imageData, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 68, height: 68)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.15)))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Pill(text: r.productType.map { "\(record.category.shortTitle) · \($0)" } ?? record.category.title,
                             icon: record.category.icon, tint: Theme.cyan)
                        Text(r.productName).font(.headline).foregroundStyle(.white).lineLimit(2)
                        if let price = record.price {
                            Text("\(price, specifier: "%.2f") \(record.currency)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.gold)
                        }
                    }
                }

                Text(r.verdict)
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                HStack(spacing: 0) {
                    scoreColumn(record.category.primaryScoreLabel, r.primaryScore)
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 90)
                    scoreColumn("性价比", record.price != nil ? r.valueScore : nil,
                                placeholder: "未填价格")
                }

                VStack(alignment: .leading, spacing: 8) {
                    reasonLine(record.category.primaryScoreLabel, r.primaryScoreReason)
                    if record.price != nil, let reason = r.valueScoreReason, !reason.isEmpty {
                        reasonLine("性价比", reason)
                    }
                }

                if let s = record.sourceURL, let url = URL(string: s) {
                    Link(destination: url) {
                        Label("查看商品页面", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(Theme.cyan)
                }
            }
            .padding(.vertical, 8)
            .environment(\.colorScheme, .dark)
        }
        .listRowBackground(
            ZStack {
                Theme.heroGradient
                RadialGradient(colors: [Theme.cyan.opacity(0.25), .clear], center: .topTrailing,
                               startRadius: 10, endRadius: 260)
            }
        )
    }

    private func scoreColumn(_ title: String, _ score: Double?, placeholder: String = "未评分") -> some View {
        VStack(spacing: 8) {
            ScoreRing(score: score, size: 80, lineWidth: 8)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            Text(score.map(Theme.scoreWord) ?? placeholder)
                .font(.caption2)
                .foregroundStyle(score.map(Theme.scoreColor) ?? .white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private func reasonLine(_ title: String, _ text: String) -> some View {
        (Text(title + "：").bold() + Text(text))
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
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
            Section {
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
            } header: {
                SectionLabel(title: "针对你", icon: "person.crop.circle.badge.checkmark", tint: Theme.green)
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
            Section {
                ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                    Label {
                        Text(text).font(.callout)
                    } icon: {
                        Image(systemName: icon).foregroundStyle(tint)
                    }
                }
            } header: {
                SectionLabel(title: title, icon: icon, tint: tint)
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
