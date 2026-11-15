import Foundation

enum AnalysisError: LocalizedError {
    case missingAPIKey(AIProvider)
    case emptyInput
    case imageNotSupported(String)
    case http(Int, String)
    case truncated
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let p): return "请先在「设置」里填写 \(p.shortTitle) 的 API Key"
        case .emptyInput: return "请拍照识别配料表，或至少填写商品名称"
        case .imageNotSupported(let model):
            return "当前模型 \(model) 不能识别图片，照片里也没识别出文字。请换一个支持图片的模型，或手动输入配料表/商品名"
        case .http(let code, let msg): return "AI 服务出错（\(code)）：\(msg)"
        case .truncated: return "AI 输出太长被截断了，请重试，或减少识别文字后再试"
        case .badResponse(let detail): return "AI 返回的内容无法解析，请重试。\n（\(detail)）"
        }
    }
}

/// 分析进度，用于界面显示
enum AnalysisStage: Equatable {
    case preparing
    case waitingAI(String)
    case parsing

    var title: String {
        switch self {
        case .preparing: return "整理识别内容、匹配知识库…"
        case .waitingAI(let name): return "\(name) 分析中…"
        case .parsing: return "解析结果…"
        }
    }
}

/// 一次分析的输出
struct AnalysisOutput {
    var result: AnalysisResult
    var usage: TokenUsage?
}

/// 商品分析 Agent：只做「商品成分 + 品牌/公司信息」分析，支持 Claude / GPT / DeepSeek / 千问。
struct AnalysisService {
    let settings: AISettings

    struct Input {
        var category: ProductCategory?      // nil = 让 AI 自动判断
        var productName: String
        var price: Double?
        var currency: String
        var spec: String
        var ocrText: String
        var images: [Data] = []             // 最多 4 张照片（JPEG）
        var sourceURL: String? = nil        // 非空表示内容来自网页抓取
        var profile: UserProfile? = nil     // 用户个人信息（开启时）
    }

    func analyze(_ input: Input,
                 onStage: @escaping @MainActor (AnalysisStage) -> Void = { _ in }) async throws -> AnalysisOutput {
        guard !settings.apiKey.isEmpty else { throw AnalysisError.missingAPIKey(settings.provider) }

        let canSeeImage = settings.sendImage && settings.provider.supportsVision(model: settings.model)
        let images = canSeeImage ? Array(input.images.prefix(4)) : []
        if input.ocrText.isEmpty && input.productName.isEmpty && images.isEmpty {
            if !input.images.isEmpty && !canSeeImage { throw AnalysisError.imageNotSupported(settings.model) }
            throw AnalysisError.emptyInput
        }

        await onStage(.preparing)
        let userText = buildUserMessage(input, imageCount: images.count)
        try Task.checkCancellation()

        await onStage(.waitingAI(settings.provider.shortTitle))
        let raw: Any
        let usage: TokenUsage?
        switch settings.provider {
        case .claude:
            (raw, usage) = try await callClaude(userText: userText, images: images)
        case .openai, .deepseek, .qwen:
            (raw, usage) = try await callOpenAICompatible(userText: userText, images: images)
        }
        try Task.checkCancellation()
        await onStage(.parsing)

        guard let dict = Self.normalize(raw) else {
            throw AnalysisError.badResponse("没有找到 JSON 对象：\(Self.preview(raw))")
        }
        let data = try JSONSerialization.data(withJSONObject: dict)
        var result: AnalysisResult
        do {
            result = try JSONDecoder().decode(AnalysisResult.self, from: data)
        } catch {
            throw AnalysisError.badResponse("字段格式不符：\(error.localizedDescription)")
        }
        if result.verdict.isEmpty && result.summary.isEmpty && result.ingredients.isEmpty {
            throw AnalysisError.badResponse("返回内容为空：\(Self.preview(raw))")
        }

        result.primaryScore = Self.clamp(result.primaryScore)
        if input.profile?.isActive != true {
            result.personalVerdict = nil
            result.personalWarnings = []
            result.personalAdvice = nil
        }
        if let p = result.detectedPrice, p <= 0 { result.detectedPrice = nil }
        if input.price != nil || input.sourceURL == nil { result.detectedPrice = nil }
        if input.price == nil && result.detectedPrice == nil {
            result.valueScore = nil
            result.valueScoreReason = nil
        } else if let v = result.valueScore {
            result.valueScore = Self.clamp(v)
        }
        return AnalysisOutput(result: result, usage: usage)
    }

    // MARK: - Claude（工具调用强制结构化输出）

    private func callClaude(userText: String, images: [Data]) async throws -> (Any, TokenUsage?) {
        var content: [[String: Any]] = []
        for image in images {
            content.append(["type": "image",
                            "source": ["type": "base64", "media_type": "image/jpeg",
                                       "data": image.base64EncodedString()]])
        }
        content.append(["type": "text", "text": userText])

        let body: [String: Any] = [
            "model": settings.model,
            "max_tokens": 16000,   // 新模型默认开启思考，思考也占用输出 token
            "system": Self.systemPrompt + "\n\n必须调用 report_analysis 工具输出结果，不要输出其他文字。",
            "tools": [Self.reportTool],
            // Sonnet 5.5 / Opus 5.5 不再支持强制指定工具（会返回 400），改用 auto + 提示词要求
            "tool_choice": ["type": "auto"],
            "messages": [["role": "user", "content": content]]
        ]
        let json = try await post(path: "/messages", body: body, headers: [
            "x-api-key": settings.apiKey,
            "anthropic-version": "2023-06-01"
        ])

        let stop = json["stop_reason"] as? String
        if stop == "max_tokens" { throw AnalysisError.truncated }
        if stop == "refusal" { throw AnalysisError.badResponse("模型拒绝了这次请求") }
        let usage = TokenUsage(json: json)
        let blocks = json["content"] as? [[String: Any]] ?? []
        if let toolUse = blocks.first(where: { ($0["type"] as? String) == "tool_use" }),
           let toolInput = toolUse["input"] {
            return (toolInput, usage)
        }
        // 兜底：模型没调用工具而是直接输出了文字 JSON
        let text = blocks.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined()
        if !text.isEmpty { return (text, usage) }
        throw AnalysisError.badResponse("没有工具调用结果")
    }

    // MARK: - OpenAI 兼容接口（GPT / DeepSeek / 千问）

    private func callOpenAICompatible(userText: String, images: [Data]) async throws -> (Any, TokenUsage?) {
        let userContent: Any
        if !images.isEmpty {
            var parts: [[String: Any]] = images.map {
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\($0.base64EncodedString())"]]
            }
            parts.append(["type": "text", "text": userText])
            userContent = parts
        } else {
            userContent = userText
        }

        var body: [String: Any] = [
            "model": settings.model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt + Self.jsonInstruction],
                ["role": "user", "content": userContent]
            ]
        ]
        if settings.provider == .openai {
            body["max_completion_tokens"] = 16000   // 包含推理用的 token
        } else {
            body["max_tokens"] = 8192
        }
        if settings.provider.supportsJSONMode(model: settings.model) {
            body["response_format"] = ["type": "json_object"]
        }

        let json = try await post(path: "/chat/completions", body: body, headers: [
            "Authorization": "Bearer \(settings.apiKey)"
        ])

        guard let choice = (json["choices"] as? [[String: Any]])?.first else {
            throw AnalysisError.badResponse("没有 choices：\(Self.preview(json))")
        }
        if (choice["finish_reason"] as? String) == "length" { throw AnalysisError.truncated }
        let usage = TokenUsage(json: json)
        let message = choice["message"] as? [String: Any] ?? [:]
        if let text = message["content"] as? String, !text.isEmpty { return (text, usage) }
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { return (text, usage) }
        }
        throw AnalysisError.badResponse("模型没有返回内容")
    }

    // MARK: - 网络

    private func post(path: String, body: [String: Any], headers: [String: String]) async throws -> [String: Any] {
        var base = settings.baseURL
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + path) else {
            throw AnalysisError.http(0, "接口地址无效：\(base)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard status == 200, let json else {
            let err = json?["error"]
            let message = ((err as? [String: Any])?["message"] as? String)
                ?? (err as? String)
                ?? (json?["message"] as? String)
                ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw AnalysisError.http(status, message)
        }
        return json
    }

    // MARK: - 结果清洗

    /// 把模型返回的各种形态（字典 / JSON 字符串 / 带代码块的文字 / 外面包了一层）统一成结果字典
    static func normalize(_ raw: Any) -> [String: Any]? {
        var obj: Any = raw
        if let text = raw as? String {
            guard let parsed = extractJSONObject(from: text) else { return nil }
            obj = parsed
        }
        guard var dict = obj as? [String: Any] else { return nil }

        // 有的模型会包一层 {"result": {...}} / {"report_analysis": {...}}
        let markers = ["verdict", "primaryScore", "ingredients", "summary"]
        if !markers.contains(where: { dict[$0] != nil }),
           let inner = dict.values.compactMap({ value -> [String: Any]? in
               if let d = value as? [String: Any] { return d }
               if let s = value as? String { return extractJSONObject(from: s) as? [String: Any] }
               return nil
           }).first(where: { d in markers.contains { d[$0] != nil } }) {
            dict = inner
        }

        // 嵌套字段有时被模型写成了 JSON 字符串
        for key in ["ingredients", "company", "shortTermEffects", "longTermEffects",
                    "suitableFor", "avoidFor", "alternatives", "personalWarnings"] {
            if let s = dict[key] as? String,
               let data = s.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                dict[key] = parsed
            }
        }

        // 成分列表：字符串元素转成 {"name": ...}，丢掉无法识别的元素
        if let list = dict["ingredients"] as? [Any] {
            dict["ingredients"] = list.compactMap { item -> [String: Any]? in
                if let d = item as? [String: Any] { return d }
                if let s = item as? String, !s.isEmpty { return ["name": s] }
                return nil
            }
        } else {
            dict["ingredients"] = nil
        }

        // 公司：字符串转成 {"name": ...}
        if let s = dict["company"] as? String {
            let t = s.trimmingCharacters(in: .whitespaces)
            dict["company"] = (t.isEmpty || t.lowercased() == "null") ? nil : ["name": t]
        }

        // 字符串数组里混了对象 / null
        for key in ["shortTermEffects", "longTermEffects", "suitableFor", "avoidFor", "alternatives", "personalWarnings"] {
            if let list = dict[key] as? [Any] {
                dict[key] = list.compactMap { item -> String? in
                    if let s = item as? String { return s }
                    if let d = item as? [String: Any] {
                        return d.values.compactMap { $0 as? String }.joined(separator: "：")
                    }
                    if let n = item as? NSNumber { return n.stringValue }
                    return nil
                }
            }
        }
        return dict
    }

    /// 从一段文字里找出 JSON 对象（去掉思考过程、```json 代码块、前后说明文字、多余逗号）
    static func extractJSONObject(from text: String) -> Any? {
        var t = text
        if let r = t.range(of: "</think>") { t = String(t[r.upperBound...]) }
        guard let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}"), start < end else { return nil }
        let candidate = String(t[start...end])
        if let obj = try? JSONSerialization.jsonObject(with: Data(candidate.utf8)) { return obj }
        let repaired = candidate.replacingOccurrences(of: #",\s*([}\]])"#, with: "$1", options: .regularExpression)
        return try? JSONSerialization.jsonObject(with: Data(repaired.utf8))
    }

    /// 本机解析出的营养成分表，作为结构化数据提供给 AI
    private static func nutritionLine(_ text: String) -> String {
        guard let n = NutritionParser.parse(text), !n.items.isEmpty else { return "" }
        let values = n.items.map { "\($0.nutrient.title) \($0.displayValue)" }.joined(separator: "，")
        return "本机从营养成分表解析出（\(n.basisTitle)）：\(values)。请以此为准判断热量、糖、钠、脂肪是否偏高。\n"
    }

    private static func preview(_ raw: Any) -> String {
        let s: String
        if let str = raw as? String { s = str }
        else if let data = try? JSONSerialization.data(withJSONObject: raw) { s = String(decoding: data, as: UTF8.self) }
        else { s = "\(raw)" }
        return s.count > 150 ? String(s.prefix(150)) + "…" : s
    }

    private static func clamp(_ v: Double) -> Double {
        (min(5, max(1, v)) * 2).rounded() / 2   // 1~5，保留 0.5 步长
    }

    // MARK: - 提示词

    private func buildUserMessage(_ input: Input, imageCount: Int) -> String {
        let hasImage = imageCount > 0
        let priceLine: String
        if let price = input.price {
            priceLine = "\(price) \(input.currency)（detectedPrice 填 null）"
        } else if input.sourceURL != nil {
            priceLine = "用户未填写 → 请从网页内容中找出该商品的实际售价（优先到手价/券后价，注意区分划线原价、其他规格和推荐商品的价格），填入 detectedPrice（数字）和 detectedCurrency（如 CNY），并据此评性价比；找不到可靠价格时 detectedPrice、valueScore、valueScoreReason 都为 null"
        } else {
            priceLine = "用户未提供价格 → valueScore 和 valueScoreReason 必须为 null"
        }
        let kbHits = KnowledgeBase.matches(in: input.ocrText + " " + input.productName, category: input.category)
        let kbBlock = kbHits.isEmpty ? "（无命中）" : kbHits.map { "- \($0)" }.joined(separator: "\n")

        let categoryBlock: String
        if let c = input.category {
            categoryBlock = """
            商品类别：\(c.title)（category 字段填 \(c.rawValue)）

            本类别分析要点：
            \(c.analysisFocus)
            """
        } else {
            let all = ProductCategory.allCases
                .map { "【\($0.rawValue) · \($0.title)】\n\($0.analysisFocus)" }
                .joined(separator: "\n\n")
            categoryBlock = """
            商品类别：由你根据\(hasImage ? "照片和" : "")文字自动判断，可以是任何种类的商品。先确定具体商品类型填入 productType\
            （如「酸奶」「洗面奶」「羽绒服」「洗衣液」「智能手机」「儿童积木」），再把 category 填为：\
            food（食品饮料、保健食品）/ cosmetic（化妆护肤、个人洗护）/ clothing（服装鞋帽、床品纺织）/ \
            household（日化清洁）/ other（以上之外的所有商品，如电子产品、家电、玩具、家具、厨具、母婴、文具、宠物用品等），\
            然后按对应类别的分析要点分析。只有照片/文字里完全没有可识别的商品时，category 才填 other 且说明无法分析。

            各类别分析要点：
            \(all)
            """
        }

        let imageLine = hasImage && input.sourceURL != nil
            ? "\n随消息附上了商品网页的截图，可用来辅助识别商品和价格。\n"
            : hasImage
            ? "\n随消息附上了 \(imageCount) 张商品照片（可能分别是正面、配料表、营养成分表等）：请从照片中识别这是什么商品（品牌、品名、类型），并直接读取照片里的配料表/成分表/洗标。OCR 文字可能不完整或有错，以照片为准。\n"
            : ""

        let ocrBlock: String
        let ocrIntro: String
        if let url = input.sourceURL {
            ocrIntro = "以下内容是从商品网页（\(url)）抓取的标题、描述、详情图文字和正文。正文里混有导航、推荐商品、评价等无关内容，请只分析这个商品本身；配料/成分以商品描述和详情图文字为准："
        } else {
            ocrIntro = "以下是手机 OCR 识别出的包装/标签文字，可能有错别字、断行或顺序错乱，请先在心中纠正明显的识别错误再分析："
        }
        if !input.ocrText.isEmpty {
            ocrBlock = input.ocrText
        } else if hasImage {
            ocrBlock = "（本地没有识别出文字，请直接看照片）"
        } else {
            ocrBlock = "（用户没有拍照，只提供了商品名称，请基于你对该商品的了解分析，并把 confidence 设为“低”或“中”）"
        }

        var profileBlock = ""
        if let profile = input.profile, profile.isActive {
            let hits = AllergenChecker.check(input.ocrText + " " + input.productName, profile: profile)
            let hitLine = hits.isEmpty ? "" : "\n本地关键词检查发现可能含有用户的过敏原：" +
                hits.map { "\($0.name)（\($0.words.joined(separator: "、"))）" }.joined(separator: "；") +
                "。请核实，属实就放在 personalWarnings 第一条。"
            profileBlock = """

            用户本人的情况（请据此做个性化判断）：
            \(profile.promptText)\(hitLine)
            个性化要求：
            1. personalVerdict 只能填：适合 / 适量 / 慎用 / 避免，表示这个商品对该用户本人是否合适。
            2. personalWarnings：逐条写出与用户过敏、忌口、健康状况、孕期哺乳、肤质等冲突的具体成分和原因；命中过敏原或忌口必须写在最前面；没有冲突时为空数组。
            3. personalAdvice：结合用户情况给出 60~120 字的具体建议，如每次适合吃多少、多久吃一次、怎么搭配、换成什么更合适；减脂/控糖/控盐人群要结合热量、糖、钠的含量来说。
            4. primaryScore 仍按通用标准评分，不要因个人情况改动；个人适合程度只体现在 personal 相关字段。

            """
        }

        let ending = settings.provider == .claude
            ? "请调用 report_analysis 工具输出结果。"
            : "请严格按约定的 JSON 格式输出结果，只输出 JSON。"

        return """
        \(categoryBlock)

        商品名称（用户输入，可能为空）：\(input.productName.isEmpty ? "未提供" : input.productName)
        价格：\(priceLine)
        规格/净含量（用户输入，可能为空）：\(input.spec.isEmpty ? "未提供" : input.spec)
        \(imageLine)
        \(ocrIntro)
        \"\"\"
        \(ocrBlock)
        \"\"\"

        \(profileBlock)\(Self.nutritionLine(input.ocrText))
        本地知识库命中的参考条目（作为参考，仍需你结合含量和配料位置判断\(input.category == nil ? "；方括号里是条目所属类别，只采用与你判断出的类别一致的条目" : "")）：
        \(kbBlock)

        \(ending)
        """
    }

    static let systemPrompt = """
    你是「成分扫描」App 内置的商品分析助手，一个专注、严谨的消费品分析师。
    你可以分析任何种类的商品：食品、化妆护肤、服装纺织、日化清洁用品看成分和配料；电子产品、家电、玩具、家具、厨具、\
    母婴用品等其他商品看材质、部件、关键参数、安全认证和做工；同时给出品牌/生产公司信息。
    只有当输入里完全没有可识别的商品（例如风景、人像、与购物无关的问题）时才不分析：category 填 other，productType 填「非商品」，\
    在 verdict 中说明无法分析，分数给 1，confidence 为“低”。

    分析原则：
    1. 以监管机构（中国国家卫健委/市场监管总局、欧盟 EFSA/SCCS、美国 FDA、IARC 等）和主流科学共识为依据；
       有争议的结论要明确说是“有争议/证据有限”，不要危言耸听，也不要替商家洗白。
    2. 配料表按含量从高到低排列，判断时要考虑成分所在位置；“剂量决定毒性”。
       没有配料表的商品（如电子产品），ingredients 列主要材质、部件或核心参数，按重要程度排列。
    3. 区分短期影响（几天到几周内可能的感受或反应）与长期影响（长期、经常使用/食用的潜在风险）。
    4. 公司信息：只写你有把握的事实（所属集团、国家、主营业务、是否有过公开的质量/安全事件）。
       不确定就写“暂无可靠信息”，绝不编造。你的知识有截止日期，必要时提醒用户核实最新信息。
    5. 性价比评分：结合价格、规格/净含量、成分档次以及同类商品常见价位判断；没有价格时 valueScore 为 null。
    6. ingredients 列出主要成分（最多 25 个），risk 只能是 safe / low / medium / high / unknown。
    7. 全部用简体中文，语言通俗，面向普通消费者。评分 1~5，可用 0.5，必须是数字。
    8. 你提供的是科普参考，不是医疗建议；对孕妇、婴幼儿、过敏体质等特殊人群在 avoidFor 里明确提示。
    """

    /// 非 Claude 模型用：在系统提示词后附上 JSON 输出格式
    static let jsonInstruction = """


    输出格式要求：只输出一个 JSON 对象，不要 markdown 代码块，不要任何解释文字。所有字段都必须出现，结构如下：
    {
      "category": "food | cosmetic | clothing | household | other",
      "productType": "具体商品类型，如 智能手机",
      "productName": "识别或推断出的商品名称",
      "verdict": "一句话结论，20字以内",
      "summary": "总体分析，100~200字",
      "primaryScore": 3.5,
      "primaryScoreReason": "健康度/安全度/品质评分的理由",
      "valueScore": 4.0,
      "valueScoreReason": "性价比评分理由",
      "ingredients": [
        {"name": "成分名", "function": "作用，如 防腐剂/甜味剂/保湿剂/面料主成分", "risk": "safe | low | medium | high | unknown", "note": "30字以内说明"}
      ],
      "shortTermEffects": ["短期影响"],
      "longTermEffects": ["长期影响"],
      "suitableFor": ["适合人群"],
      "avoidFor": ["慎用人群"],
      "company": {"name": "公司名", "background": "公司背景", "reputation": "口碑、质量安全事件，不确定写暂无可靠信息"},
      "alternatives": ["更健康/更值的替代选择（类型即可）"],
      "confidence": "高 | 中 | 低",
      "detectedPrice": 59.9,
      "detectedCurrency": "CNY",
      "personalVerdict": "适合 | 适量 | 慎用 | 避免",
      "personalWarnings": ["针对用户本人的警示"],
      "personalAdvice": "针对用户本人的建议"
    }
    primaryScore、valueScore 必须是 1~5 的数字；未提供价格时 valueScore 和 valueScoreReason 为 null；无法确定公司时 company 为 null；detectedPrice 只在用户消息要求从网页找价格时填写，否则为 null；用户消息里没有提供个人情况时，personalVerdict、personalAdvice 为 null，personalWarnings 为空数组。
    """

    static var reportTool: [String: Any] {
        [
        "name": "report_analysis",
        "description": "输出商品成分分析的结构化结果",
        "input_schema": [
            "type": "object",
            "properties": [
                "category": ["type": "string", "enum": ["food", "cosmetic", "clothing", "household", "other"],
                             "description": "商品类别；电子产品、家电、玩具等前四类以外的商品填 other"],
                "productType": ["type": "string", "description": "具体商品类型，如 酸奶 / 洗面奶 / 智能手机 / 儿童积木"],
                "productName": ["type": "string", "description": "识别或推断出的商品名称"],
                "verdict": ["type": "string", "description": "一句话结论，20字以内"],
                "summary": ["type": "string", "description": "总体分析，100~200字"],
                "primaryScore": ["type": "number", "description": "健康度/安全度/品质评分 1-5"],
                "primaryScoreReason": ["type": "string"],
                "valueScore": ["type": ["number", "null"], "description": "性价比评分 1-5；未提供价格时为 null"],
                "valueScoreReason": ["type": ["string", "null"]],
                "ingredients": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string", "description": "成分名；非配料类商品写材质、部件或参数名"],
                            "function": ["type": "string", "description": "作用，如 防腐剂/甜味剂/面料主成分；电子产品写用途或参数值"],
                            "risk": ["type": "string", "enum": ["safe", "low", "medium", "high", "unknown"]],
                            "note": ["type": "string", "description": "简短说明，30字以内"]
                        ],
                        "required": ["name", "function", "risk", "note"]
                    ]
                ],
                "shortTermEffects": ["type": "array", "items": ["type": "string"]],
                "longTermEffects": ["type": "array", "items": ["type": "string"]],
                "suitableFor": ["type": "array", "items": ["type": "string"]],
                "avoidFor": ["type": "array", "items": ["type": "string"]],
                "company": [
                    "type": ["object", "null"],
                    "properties": [
                        "name": ["type": "string"],
                        "background": ["type": "string"],
                        "reputation": ["type": "string", "description": "口碑、质量安全事件等，不确定写暂无可靠信息"]
                    ],
                    "required": ["name", "background", "reputation"]
                ],
                "alternatives": ["type": "array", "items": ["type": "string"], "description": "更健康/更值的替代选择建议（类型即可，不必指定品牌）"],
                "confidence": ["type": "string", "enum": ["高", "中", "低"]],
                "detectedPrice": ["type": ["number", "null"], "description": "从网页内容找到的售价，仅在用户要求时填写，否则 null"],
                "detectedCurrency": ["type": ["string", "null"], "description": "detectedPrice 的货币代码，如 CNY"],
                "personalVerdict": ["type": ["string", "null"], "enum": ["适合", "适量", "慎用", "避免", NSNull()],
                                    "description": "对用户本人是否合适；没有提供个人情况时为 null"],
                "personalWarnings": ["type": "array", "items": ["type": "string"],
                                     "description": "与用户过敏、忌口、健康状况冲突的成分和原因；没有个人情况或无冲突时为空数组"],
                "personalAdvice": ["type": ["string", "null"], "description": "针对用户本人的建议；没有个人情况时为 null"]
            ],
            "required": [
                "category", "productType", "productName", "verdict", "summary", "primaryScore", "primaryScoreReason",
                "valueScore", "valueScoreReason", "ingredients", "shortTermEffects", "longTermEffects",
                "suitableFor", "avoidFor", "company", "alternatives", "confidence"
            ]
        ]
        ]
    }
}
