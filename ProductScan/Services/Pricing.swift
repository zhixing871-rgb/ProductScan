import Foundation

/// 一次请求的 token 用量
struct TokenUsage: Codable, Hashable {
    var inputTokens: Int
    var outputTokens: Int

    var total: Int { inputTokens + outputTokens }

    /// 从 Claude（input_tokens/output_tokens）或 OpenAI 兼容接口（prompt_tokens/completion_tokens）的 usage 读取
    init?(json: [String: Any]?) {
        guard let u = json?["usage"] as? [String: Any] else { return nil }
        func int(_ k: String) -> Int? { (u[k] as? NSNumber)?.intValue }
        if let i = int("input_tokens"), let o = int("output_tokens") {
            // Claude：缓存读写的 token 也算输入
            inputTokens = i + (int("cache_read_input_tokens") ?? 0) + (int("cache_creation_input_tokens") ?? 0)
            outputTokens = o
        } else if let i = int("prompt_tokens"), let o = int("completion_tokens") {
            inputTokens = i
            outputTokens = o
        } else {
            return nil
        }
    }

    init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// 按官方公开价估算花费（价格会变动，仅供参考）
enum Pricing {
    struct Price {
        let input: Double      // 每百万输入 token
        let output: Double     // 每百万输出 token
        let currency: String   // USD / CNY
    }

    /// 价格表：Claude 来自 Anthropic 官方价格（2026-11），其余为各家公开价的近似值
    static func price(for model: String) -> Price? {
        let m = model.lowercased()
        let table: [(String, Price)] = [
            ("claude-opus-5-5", Price(input: 4, output: 20, currency: "USD")),
            ("claude-sonnet-5-5", Price(input: 2, output: 10, currency: "USD")),
            ("claude-haiku-5-5", Price(input: 0.10, output: 0.50, currency: "USD")),
            ("gpt-5-mini", Price(input: 0.25, output: 2, currency: "USD")),
            ("gpt-5", Price(input: 1.25, output: 10, currency: "USD")),
            ("deepseek-chat", Price(input: 2, output: 3, currency: "CNY")),
            ("deepseek-reasoner", Price(input: 2, output: 3, currency: "CNY")),
            ("qwen-vl-max", Price(input: 1.6, output: 4, currency: "CNY")),
            ("qwen-plus", Price(input: 0.8, output: 2, currency: "CNY")),
            ("qwen-max", Price(input: 2.4, output: 9.6, currency: "CNY"))
        ]
        // 先精确匹配，再按前缀匹配（gpt-5-mini 要排在 gpt-5 前面）
        if let exact = table.first(where: { $0.0 == m }) { return exact.1 }
        return table.first(where: { m.hasPrefix($0.0) })?.1
    }

    /// 估算花费文字，如「约 $0.012」「约 ¥0.008」；未知模型返回 nil
    static func costText(model: String, usage: TokenUsage) -> String? {
        guard let p = price(for: model) else { return nil }
        let cost = (Double(usage.inputTokens) * p.input + Double(usage.outputTokens) * p.output) / 1_000_000
        let symbol = p.currency == "USD" ? "$" : "¥"
        let digits = cost < 0.01 ? 4 : 3
        return "约 \(symbol)\(String(format: "%.\(digits)f", cost))"
    }

    static func usageText(model: String, usage: TokenUsage) -> String {
        var s = "输入 \(usage.inputTokens) + 输出 \(usage.outputTokens) tokens"
        if let cost = costText(model: model, usage: usage) { s += "，\(cost)" }
        return s
    }
}
