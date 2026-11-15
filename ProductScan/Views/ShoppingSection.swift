import SwiftUI
import SwiftData

/// 结果页的「联网购物助手」区块：
/// 线上链接且低分 → 推荐更好的同类商品；线下拍照 → 查询网上价格
struct ShoppingSection: View {
    let record: ScanRecord

    @Environment(\.modelContext) private var context
    @State private var task: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var shop = ShoppingSettings.current()

    static let disclaimer = "⚠️ 以上内容由 AI 联网搜索整理，不是广告：本 App 与任何商家没有合作，不收取推广费用。价格、库存和店铺信息随时会变，请以商家页面为准，自行斟酌后再购买。AI 的评价可能有误，请理性看待，不要据此对商家恶意差评、骚扰或攻击。"

    private var kind: ShoppingKind? { record.shopping?.kind ?? shop.task(for: record) }
    private var isRunning: Bool { task != nil }

    var body: some View {
        if let kind {
            Section {
                content(kind)
            } header: {
                Text(kind == .alternatives ? "更好的同类选择" : "网上价格参考")
            } footer: {
                Text(Self.disclaimer)
            }
            .task(id: record.id) { autoStart(kind) }
        }
    }

    @ViewBuilder
    private func content(_ kind: ShoppingKind) -> some View {
        if isRunning {
            HStack(spacing: 10) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind == .alternatives ? "得分偏低，正在联网找更好的同类商品…" : "正在查询各网站的价格…")
                        .font(.callout)
                    Text("通常需要 20~60 秒").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("停止") { task?.cancel() }.buttonStyle(.borderless)
            }
        } else if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
            Button("重试") { start(kind) }
        } else if let result = record.shopping {
            if !result.searched {
                Label("当前模型（\(AISettings.current().provider.shortTitle)）不能联网，以下来自 AI 已有知识，价格可能已过时。换成 Claude、GPT 或千问可以实时搜索。",
                      systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !result.summary.isEmpty {
                Text(result.summary).font(.callout)
            }
            ForEach(Array(result.items.enumerated()), id: \.offset) { _, item in
                ShoppingItemRow(item: item, kind: result.kind, linkSite: shop.linkSite)
            }
            HStack {
                Text("查询于 \(result.date.formatted(date: .abbreviated, time: .shortened))"
                     + (result.usageText.map { " · \($0)" } ?? ""))
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("重新查询") { start(kind) }.font(.caption).buttonStyle(.borderless)
            }
        } else {
            Button {
                start(kind)
            } label: {
                Label(kind == .alternatives ? "联网查找更好的同类商品" : "联网查询网上价格", systemImage: "magnifyingglass")
            }
        }
    }

    /// 刚分析完的记录自动查询；旧记录需要手动点（避免翻历史时意外产生费用）
    private func autoStart(_ kind: ShoppingKind) {
        shop = ShoppingSettings.current()
        guard record.shopping == nil, task == nil, errorMessage == nil,
              record.createdAt.timeIntervalSinceNow > -600 else { return }
        start(kind)
    }

    private func start(_ kind: ShoppingKind) {
        guard task == nil else { return }
        errorMessage = nil
        shop = ShoppingSettings.current()
        let settings = AISettings.current()
        let background = AnalysisService.shoppingContext(record: record)
        let shop = self.shop
        task = Task {
            defer { task = nil }
            do {
                let result = try await AnalysisService(settings: settings)
                    .shoppingSearch(kind: kind, context: background, shop: shop)
                record.shopping = result
                try? context.save()
            } catch is CancellationError {
                errorMessage = "已停止"
            } catch let e as URLError where e.code == .cancelled {
                errorMessage = "已停止"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ShoppingItemRow: View {
    let item: ShoppingItem
    let kind: ShoppingKind
    let linkSite: ShopSite?          // nil = 设置里选了「不提供链接」

    /// 价格查询用条目自己的平台；推荐替代品用设置里选的网站
    private var searchSite: ShopSite? {
        guard let linkSite else { return nil }
        return kind == .prices ? (ShopSite(loose: item.platform) ?? linkSite) : linkSite
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name).font(.body.weight(.medium))
            HStack(spacing: 8) {
                if let p = item.platform {
                    Text(p)
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                if let price = item.price {
                    Text(price).font(.callout.monospacedDigit()).foregroundStyle(.orange)
                }
            }
            if let reason = item.reason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            if linkSite != nil {
                HStack(spacing: 16) {
                    if let site = searchSite, let url = site.searchURL(item.name) {
                        Link(destination: url) { Label("在\(site.shortTitle)搜索", systemImage: "cart") }
                    }
                    if let url = item.webURL {
                        Link(destination: url) { Label("AI 找到的页面", systemImage: "safari") }
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 设置 → 联网购物助手
struct ShoppingSettingsView: View {
    @AppStorage(ShoppingSettings.recommendKey) private var recommend = false
    @AppStorage(ShoppingSettings.priceCheckKey) private var priceCheck = false
    @AppStorage(ShoppingSettings.linkSiteKey) private var linkSite = ShopSite.taobao.rawValue
    @AppStorage(ShoppingSettings.priceSitesKey) private var priceSitesRaw = ShoppingSettings.defaultPriceSites
    @AppStorage(AISettings.providerKey) private var providerRaw = AIProvider.claude.rawValue

    private var priceSites: Set<String> { Set(priceSitesRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        Form {
            Section {
                Text(ShoppingSection.disclaimer).font(.footnote)
            }

            if let p = AIProvider(rawValue: providerRaw), !AnalysisService.supportsWebSearch(p) {
                Section {
                    Label("当前服务商 \(p.shortTitle) 不支持联网搜索，只能凭 AI 已有知识回答，价格可能过时。建议换成 Claude、GPT 或千问。",
                          systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Toggle("低分时推荐更好的同类商品", isOn: $recommend)
            } header: {
                Text("网购链接")
            } footer: {
                Text("只对「链接 / 文字」里抓取的网购商品生效：健康/品质或性价比低于 \(Int(ShoppingSettings.threshold)) 分时，AI 自动联网搜索 3~5 个更好的同类商品。每次会额外产生一次 AI 调用费用。")
            }

            Section {
                Toggle("线下拍照时查询网上价格", isOn: $priceCheck)
                if priceCheck {
                    ForEach(ShopSite.allCases) { site in
                        Toggle(site.title, isOn: Binding(
                            get: { priceSites.contains(site.rawValue) },
                            set: { on in
                                var s = priceSites
                                if on { s.insert(site.rawValue) } else if s.count > 1 { s.remove(site.rawValue) }
                                priceSitesRaw = ShopSite.allCases.map(\.rawValue).filter(s.contains).joined(separator: ",")
                            }))
                    }
                }
            } header: {
                Text("实体店购物")
            } footer: {
                Text("拍照分析的商品，AI 会联网查询它在所选网站（含 1688 批发价）的价格，并和你填写的线下价格对比。至少保留一个网站。")
            }

            Section {
                Picker("商品链接", selection: $linkSite) {
                    Text("不提供链接").tag("none")
                    ForEach(ShopSite.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: {
                Text("链接")
            } footer: {
                Text("推荐商品下方显示到所选网站的搜索链接（链接由 App 生成，不是 AI 编的，也不含任何推广参数）；查价格时按各条目的网站生成。选「不提供链接」则只显示文字。")
            }
        }
        .navigationTitle("联网购物助手")
        .navigationBarTitleDisplayMode(.inline)
    }
}
