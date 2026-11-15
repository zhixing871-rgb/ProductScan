import Foundation

/// 联网购物助手：低分商品推荐替代品、线下商品查网上价格
extension AnalysisService {
    /// 当前服务商是否能联网搜索
    static func supportsWebSearch(_ provider: AIProvider) -> Bool {
        provider != .deepseek
    }

    func shoppingSearch(kind: ShoppingKind, context: String, shop: ShoppingSettings) async throws -> ShoppingResult {
        guard !settings.apiKey.isEmpty else { throw AnalysisError.missingAPIKey(settings.provider) }
        let canSearch = Self.supportsWebSearch(settings.provider)
        let prompt = Self.shoppingPrompt(kind: kind, context: context, shop: shop, canSearch: canSearch)

        let text: String
        let usage: TokenUsage?
        switch settings.provider {
        case .claude: (text, usage) = try await claudeSearch(prompt)
        case .openai: (text, usage) = try await openAISearch(prompt)
        case .qwen, .deepseek: (text, usage) = try await chatSearch(prompt, enableSearch: settings.provider == .qwen)
        }

        guard let obj = Self.extractJSONObject(from: text) as? [String: Any] else {
            throw AnalysisError.badResponse("没有找到 JSON：\(String(text.prefix(120)))")
        }
        let summary = (obj["summary"] as? String) ?? ""
        let rawItems = (obj["items"] as? [Any]) ?? []
        let items: [ShoppingItem] = rawItems.prefix(10).compactMap { item in
            guard let d = item as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: d),
                  var it = try? JSONDecoder().decode(ShoppingItem.self, from: data) else { return nil }
            if it.webURL == nil || !canSearch { it.url = nil }   // 没联网时的链接一定是编的
            return it
        }
        if summary.isEmpty && items.isEmpty { throw AnalysisError.badResponse("没有查到结果") }
        return ShoppingResult(kind: kind, summary: summary, items: items, searched: canSearch,
                              usageText: usage.map { Pricing.usageText(model: settings.model, usage: $0) })
    }

    // MARK: 各服务商的联网方式

    /// Claude：服务端 web_search 工具；pause_turn 时续跑
    private func claudeSearch(_ prompt: String) async throws -> (String, TokenUsage?) {
        let m = settings.model.lowercased()
        let toolType = (m.contains("haiku") || m.contains("-4-5") || m.contains("-4-1")) ? "web_search_20250305" : "web_search_20260209"
        var messages: [[String: Any]] = [["role": "user", "content": prompt]]
        var text = ""
        var total = TokenUsage(inputTokens: 0, outputTokens: 0)
        for _ in 0..<4 {
            let body: [String: Any] = [
                "model": settings.model,
                "max_tokens": 8000,
                "system": Self.shoppingSystem,
                "tools": [["type": toolType, "name": "web_search", "max_uses": 6]],
                "messages": messages
            ]
            let json = try await post(path: "/messages", body: body, headers: [
                "x-api-key": settings.apiKey,
                "anthropic-version": "2023-06-01"
            ])
            if let u = TokenUsage(json: json) {
                total.inputTokens += u.inputTokens
                total.outputTokens += u.outputTokens
            }
            let content = json["content"] as? [[String: Any]] ?? []
            text += content.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined()
            let stop = json["stop_reason"] as? String
            if stop == "refusal" { throw AnalysisError.badResponse("模型拒绝了这次请求") }
            guard stop == "pause_turn" else { break }
            // 服务端搜索循环被暂停：把已有回复带回去继续
            messages = [messages[0], ["role": "assistant", "content": content]]
        }
        return (text, total)
    }

    /// OpenAI：Responses 接口的 web_search 工具
    private func openAISearch(_ prompt: String) async throws -> (String, TokenUsage?) {
        let body: [String: Any] = [
            "model": settings.model,
            "instructions": Self.shoppingSystem,
            "input": prompt,
            "tools": [["type": "web_search"]],
            "max_output_tokens": 8000
        ]
        let json = try await post(path: "/responses", body: body, headers: [
            "Authorization": "Bearer \(settings.apiKey)"
        ])
        let output = json["output"] as? [[String: Any]] ?? []
        let text = output
            .filter { ($0["type"] as? String) == "message" }
            .flatMap { ($0["content"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["text"] as? String }
            .joined()
        return (text, TokenUsage(json: json))
    }

    /// 千问：enable_search 联网；DeepSeek：不联网，只凭已有知识
    private func chatSearch(_ prompt: String, enableSearch: Bool) async throws -> (String, TokenUsage?) {
        var body: [String: Any] = [
            "model": settings.model,
            "max_tokens": 4096,
            "messages": [["role": "system", "content": Self.shoppingSystem],
                         ["role": "user", "content": prompt]]
        ]
        if enableSearch {
            body["enable_search"] = true
            body["search_options"] = ["forced_search": true]
        }
        let json = try await post(path: "/chat/completions", body: body, headers: [
            "Authorization": "Bearer \(settings.apiKey)"
        ])
        let message = ((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]) ?? [:]
        return (Self.cleanReply(message["content"] as? String ?? ""), TokenUsage(json: json))
    }

    // MARK: 提示词

    /// 简短的商品背景（不含原文，减少花费）
    static func shoppingContext(record: ScanRecord) -> String {
        let r = record.result
        var lines: [String] = []
        let name = record.productName.isEmpty ? (r?.productName ?? "未知") : record.productName
        lines.append("商品：\(name)")
        if let t = r?.productType { lines.append("商品类型：\(t)（\(record.category.title)）") }
        if let s = record.specText, !s.isEmpty { lines.append("规格：\(s)") }
        if let p = record.price { lines.append("用户看到的价格：\(String(format: "%.2f", p)) \(record.currency)") }
        if let u = record.sourceURL { lines.append("商品网页：\(u)") }
        if let r {
            lines.append("分析结论：\(r.verdict)。\(r.summary)")
            lines.append("\(record.category.primaryScoreLabel)：\(r.primaryScore)/5（\(r.primaryScoreReason)）")
            if let v = r.valueScore { lines.append("性价比：\(v)/5（\(r.valueScoreReason ?? "")）") }
            let risky = r.ingredients.filter { $0.risk == .high || $0.risk == .medium }.map(\.name)
            if !risky.isEmpty { lines.append("需要注意的成分/问题：\(risky.joined(separator: "、"))") }
        }
        return lines.joined(separator: "\n")
    }

    static let shoppingSystem = """
    你是「成分扫描」App 的购物助手，帮消费者客观地找更好的商品或比较价格。你不接受任何商家推广，\
    不推荐广告位或软文里的商品，只依据搜索到的真实信息和商品本身的成分/品质。\
    用简体中文。最终只输出一个 JSON 对象，不要 markdown 代码块，不要其他文字。
    """

    static func shoppingPrompt(kind: ShoppingKind, context: String, shop: ShoppingSettings, canSearch: Bool) -> String {
        let searchLine = canSearch
            ? "请先联网搜索再回答。"
            : "你当前无法联网，请基于已有知识回答：price 写大致参考价并注明「参考价，可能已变动」，url 一律填 null。"
        let format = #"{"summary": "结论", "items": [{"name": "品牌 + 品名 + 规格", "platform": "网站名", "price": "价格及规格", "reason": "说明", "url": "页面地址或 null"}]}"#

        switch kind {
        case .alternatives:
            let site = shop.linkSite.map { "优先选择在\($0.title)上能买到的商品，platform 填「\($0.shortTitle)」。" } ?? ""
            return """
            \(context)

            用户在网购页面看到这个商品，分析得分偏低。\(searchLine)找 3~5 个同类型、能直接替代它、但更健康/品质更好或更划算的商品。
            要求：
            1. 必须是同一类型的商品，写清楚品牌、品名和规格；不要推荐原商品本身。\(site)
            2. price 写搜索到的大致售价（如「¥39.9/500g」），找不到写 null。
            3. reason 写它比原商品好在哪里，40 字以内，要具体（如「配料只有生牛乳，无添加糖」）。
            4. url 只能填你在搜索结果中真实看到的商品页或评测页地址，没有就填 null，绝不编造。
            5. summary 写 60 字以内：原商品的主要问题，以及挑选同类商品时该看什么。
            输出格式：\(format)
            """
        case .prices:
            let sites = shop.priceSites.map(\.title).joined(separator: "、")
            return """
            \(context)

            用户在线下实体店看到这个商品。\(searchLine)查询它在这些网站的售价：\(sites)。
            要求：
            1. 尽量找同品牌同规格；找不到同款时可列同类相近商品，并在 name 里注明「同类」。
            2. 每个网站最多 2 条，platform 写网站名；price 写价格和规格（如「¥12.5/瓶，整箱24瓶¥280」）；1688 写批发价和起批量。
            3. reason 写简短说明（如 官方旗舰店/第三方店铺、是否需凑单或另付运费）。
            4. url 只能填你在搜索结果中真实看到的页面地址，没有就填 null，绝不编造。
            5. summary 写 80 字以内：线下价格和网上相比贵还是便宜、大约差多少、建议在哪买；用户没提供线下价格就只总结网上价格区间。
            输出格式：\(format)
            """
        }
    }
}
