import SwiftUI

/// AI 返回的结构化分析结果（字段与 AnalysisService 中的 JSON Schema 一一对应）
struct AnalysisResult: Codable, Hashable {
    var category: String?               // AI 自动判断的类别：food / cosmetic / clothing / household / other
    var productName: String
    var verdict: String                 // 一句话结论
    var summary: String                 // 总体分析
    var primaryScore: Double            // 健康度/安全度/品质 1-5
    var primaryScoreReason: String
    var valueScore: Double?             // 性价比 1-5，未提供价格时为 nil
    var valueScoreReason: String?
    var ingredients: [IngredientItem]
    var shortTermEffects: [String]
    var longTermEffects: [String]
    var suitableFor: [String]
    var avoidFor: [String]
    var company: CompanyInfo?
    var alternatives: [String]
    var confidence: String              // 高/中/低（识别文字不全时会降低）
    var detectedPrice: Double?          // 从网页内容里找到的售价（链接模式）
    var detectedCurrency: String?
}

/// 宽松解码：不同模型返回的字段可能缺失、类型不一致（数字写成字符串、数组为空值等），
/// 这里全部给默认值，避免一个字段不对就整体解析失败。
extension AnalysisResult {
    private enum CodingKeys: String, CodingKey {
        case category, productName, verdict, summary, primaryScore, primaryScoreReason,
             valueScore, valueScoreReason, ingredients, shortTermEffects, longTermEffects,
             suitableFor, avoidFor, company, alternatives, confidence, detectedPrice, detectedCurrency
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = c.looseString(.category)
        productName = c.looseString(.productName) ?? ""
        verdict = c.looseString(.verdict) ?? ""
        summary = c.looseString(.summary) ?? ""
        primaryScore = c.looseDouble(.primaryScore) ?? 3
        primaryScoreReason = c.looseString(.primaryScoreReason) ?? ""
        valueScore = c.looseDouble(.valueScore)
        valueScoreReason = c.looseString(.valueScoreReason)
        ingredients = (try? c.decodeIfPresent([IngredientItem].self, forKey: .ingredients)) ?? []
        shortTermEffects = c.looseStrings(.shortTermEffects)
        longTermEffects = c.looseStrings(.longTermEffects)
        suitableFor = c.looseStrings(.suitableFor)
        avoidFor = c.looseStrings(.avoidFor)
        company = try? c.decodeIfPresent(CompanyInfo.self, forKey: .company)
        alternatives = c.looseStrings(.alternatives)
        confidence = c.looseString(.confidence) ?? "中"
        detectedPrice = c.looseDouble(.detectedPrice)
        detectedCurrency = c.looseString(.detectedCurrency)
    }
}

struct IngredientItem: Codable, Hashable {
    var name: String
    var function: String
    var risk: RiskLevel
    var note: String

    private enum CodingKeys: String, CodingKey { case name, function, risk, note }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.looseString(.name) ?? "未知成分"
        function = c.looseString(.function) ?? ""
        risk = (try? c.decodeIfPresent(RiskLevel.self, forKey: .risk)) ?? .unknown
        note = c.looseString(.note) ?? ""
    }
}

struct CompanyInfo: Codable, Hashable {
    var name: String
    var background: String
    var reputation: String

    private enum CodingKeys: String, CodingKey { case name, background, reputation }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.looseString(.name) ?? "未知"
        background = c.looseString(.background) ?? ""
        reputation = c.looseString(.reputation) ?? "暂无可靠信息"
    }
}

enum RiskLevel: String, Codable, Hashable {
    case safe, low, medium, high, unknown

    init(from decoder: Decoder) throws {
        let raw = ((try? decoder.singleValueContainer().decode(String.self)) ?? "")
            .trimmingCharacters(in: .whitespaces).lowercased()
        switch raw {
        case "safe", "安全", "无风险": self = .safe
        case "low", "低", "低风险": self = .low
        case "medium", "中", "中风险", "注意", "moderate": self = .medium
        case "high", "高", "高风险": self = .high
        default: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .safe: return "安全"
        case .low: return "低风险"
        case .medium: return "注意"
        case .high: return "高风险"
        case .unknown: return "未知"
        }
    }

    var color: Color {
        switch self {
        case .safe: return .green
        case .low: return .teal
        case .medium: return .orange
        case .high: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - 宽松解码工具

private extension KeyedDecodingContainer {
    func looseString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b ? "是" : "否" }
        return nil
    }

    func looseDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            // "4.5"、"4.5/5"、"4.5分" 都取第一个数字
            let scanner = Scanner(string: s)
            scanner.charactersToBeSkipped = CharacterSet.decimalDigits.inverted
            return scanner.scanDouble()
        }
        return nil
    }

    func looseStrings(_ key: Key) -> [String] {
        if let list = try? decodeIfPresent([String].self, forKey: key) { return list }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            return s.components(separatedBy: CharacterSet(charactersIn: "\n；;"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return []
    }
}
