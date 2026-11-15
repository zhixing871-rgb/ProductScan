import Foundation

/// 营养成分
enum Nutrient: String, CaseIterable, Codable {
    case energy, protein, fat, saturatedFat, transFat, carbohydrate, sugar, fiber, sodium

    var title: String {
        switch self {
        case .energy: return "能量"
        case .protein: return "蛋白质"
        case .fat: return "脂肪"
        case .saturatedFat: return "饱和脂肪"
        case .transFat: return "反式脂肪"
        case .carbohydrate: return "碳水化合物"
        case .sugar: return "糖"
        case .fiber: return "膳食纤维"
        case .sodium: return "钠"
        }
    }

    /// 统一单位：能量 kJ，钠 mg，其余 g
    var unit: String {
        switch self {
        case .energy: return "kJ"
        case .sodium: return "mg"
        default: return "g"
        }
    }

    /// 是「越少越好」的限制型营养素
    var isLimit: Bool {
        switch self {
        case .protein, .fiber: return false
        default: return true
        }
    }

    /// 每日参考量（中国 GB 28050 营养素参考值 NRV；糖按膳食指南 50g），结合个人情况调整
    func dailyReference(for profile: UserProfile?) -> Double {
        let goals = profile?.isActive == true ? profile!.goals : []
        switch self {
        case .energy: return Self.energyTargetKJ(profile) ?? 8400
        case .protein: return 60
        case .fat: return 60
        case .saturatedFat: return goals.contains(.lowLipid) ? 15 : 20
        case .transFat: return 2.2
        case .carbohydrate: return goals.contains(.controlSugar) ? 200 : 300
        case .sugar: return goals.contains(.controlSugar) || goals.contains(.loseFat) ? 25 : 50
        case .fiber: return 25
        case .sodium: return goals.contains(.lowSalt) || goals.contains(.kidney) ? 1500 : 2000
        }
    }

    /// 根据身高体重年龄性别估算每日能量（Mifflin-St Jeor × 1.4 轻体力活动；减脂期再减 400 kcal）
    static func energyTargetKJ(_ profile: UserProfile?) -> Double? {
        guard let p = profile, p.isActive, let w = p.weightKg, let h = p.heightCm, let a = p.age,
              p.gender != .unspecified else { return nil }
        var kcal = 10 * w + 6.25 * h - 5 * Double(a) + (p.gender == .male ? 5 : -161)
        kcal *= 1.4
        if p.goals.contains(.loseFat) { kcal = max(1200, kcal - 400) }
        if p.goals.contains(.gainMuscle) { kcal += 300 }
        return kcal * 4.184
    }

    /// 每 100g（或 100ml）的高/中/低分级阈值（参考英国 FSA 红绿灯标签）
    func level(per100 value: Double, isLiquid: Bool) -> NutrientLevel? {
        let t: (low: Double, high: Double)
        switch self {
        case .fat: t = isLiquid ? (1.5, 8.75) : (3, 17.5)
        case .saturatedFat: t = isLiquid ? (0.75, 2.5) : (1.5, 5)
        case .sugar: t = isLiquid ? (2.5, 11.25) : (5, 22.5)
        case .sodium: t = isLiquid ? (120, 300) : (120, 600)
        case .transFat: t = (0.3, 0.3)
        default: return nil
        }
        if value <= t.low { return .low }
        if value > t.high { return .high }
        return .medium
    }
}

enum NutrientLevel {
    case low, medium, high
    var title: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }
}

struct NutrientValue: Hashable {
    let nutrient: Nutrient
    let value: Double

    var displayValue: String {
        let v = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        return "\(v)\(nutrient.unit)"
    }
}

struct NutritionFacts {
    enum Basis { case per100g, per100ml, perServing }

    var basis: Basis
    var servingText: String?          // 每份的描述，如「每份(30g)」
    var items: [NutrientValue]
    var netContent: Double?           // 净含量（g 或 ml）

    var basisTitle: String {
        switch basis {
        case .per100g: return "每100g"
        case .per100ml: return "每100ml"
        case .perServing: return servingText ?? "每份"
        }
    }

    var isLiquid: Bool { basis == .per100ml }

    func value(_ n: Nutrient) -> Double? { items.first { $0.nutrient == n }?.value }

    /// 整包是 100g/ml 的多少倍（仅当按每 100 计且知道净含量时）
    var packageFactor: Double? {
        guard basis != .perServing, let net = netContent, net > 0 else { return nil }
        return net / 100
    }
}

/// 从 OCR 文字里解析营养成分表。OCR 常把表格拆成多行（「钠」「450mg」「23%」各一行），所以名称和数字之间允许换行。
enum NutritionParser {
    static func parse(_ text: String, spec: String = "") -> NutritionFacts? {
        let lower = text.lowercased()
        guard lower.contains("营养") || lower.contains("nutrition") || lower.contains("能量") || lower.contains("energy") else {
            return nil
        }

        var items: [NutrientValue] = []
        for nutrient in Nutrient.allCases {
            if let v = find(nutrient, in: lower) { items.append(NutrientValue(nutrient: nutrient, value: v)) }
        }
        guard items.count >= 2 else { return nil }

        var basis: NutritionFacts.Basis = .per100g
        var servingText: String?
        if match(#"(每|per)\s*100\s*(ml|毫升)"#, lower) != nil {
            basis = .per100ml
        } else if match(#"(每|per)\s*100\s*(g|克)"#, lower) != nil {
            basis = .per100g
        } else if let s = match(#"每份\s*[（(]?\s*\d+(?:\.\d+)?\s*(?:g|克|ml|毫升)?\s*[)）]?"#, lower) {
            basis = .perServing
            servingText = s.replacingOccurrences(of: " ", with: "")
        }

        return NutritionFacts(basis: basis, servingText: servingText, items: items,
                              netContent: netContent(lower + " " + spec.lowercased()))
    }

    private static let number = #"(\d+(?:\.\d+)?)"#

    private static func find(_ n: Nutrient, in text: String) -> Double? {
        let sep = #"\s*[:：]?\s*"#
        switch n {
        case .energy:
            if let v = capture(#"(?:能量|热量|energy)"# + sep + number + #"\s*(?:kj|千焦)"#, text) { return v }
            if let v = capture(#"(?:能量|热量|energy)"# + sep + number + #"\s*(?:kcal|千卡|大卡)"#, text) { return v * 4.184 }
            return nil
        case .protein:
            return capture(#"(?:蛋白质|protein)"# + sep + number + #"\s*(?:g|克)"#, text)
        case .fat:
            return capture(#"(?<!饱和)(?<!反式)(?<!saturated )(?<!trans )(?:脂肪|fat)(?!酸)"# + sep + number + #"\s*(?:g|克)"#, text)
        case .saturatedFat:
            return capture(#"(?:饱和脂肪(?:酸)?|saturated fat|saturates)"# + sep + number + #"\s*(?:g|克)"#, text)
        case .transFat:
            return capture(#"(?:反式脂肪(?:酸)?|trans fat)"# + sep + number + #"\s*(?:g|克)"#, text)
        case .carbohydrate:
            return capture(#"(?:碳水化合物|碳水|carbohydrate)"# + sep + number + #"\s*(?:g|克)"#, text)
        case .sugar:
            // 排除「白砂糖」「葡萄糖」「糖醇」等配料名
            return capture(#"(?:(?<![砂白红冰蔗果葡麦乳芽浆转化醇])糖|sugars?)(?!醇)"# + sep + number + #"\s*(?:g|克)"#, text)
        case .fiber:
            return capture(#"(?:膳食纤维|fibre|fiber)"# + sep + number + #"\s*(?:g|克)"#, text)
        case .sodium:
            if let v = capture(#"(?:钠|sodium)"# + sep + number + #"\s*(?:mg|毫克)"#, text) { return v }
            if let v = capture(#"(?:钠|sodium)"# + sep + number + #"\s*(?:g|克)(?![a-z])"#, text) { return v * 1000 }
            return nil
        }
    }

    private static func netContent(_ text: String) -> Double? {
        let pattern = #"(?:净含量|净重|net\s*(?:wt|weight|content)?)\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(kg|千克|g|克|ml|毫升|l|升)"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let vr = Range(m.range(at: 1), in: text), let ur = Range(m.range(at: 2), in: text),
              let v = Double(text[vr]) else {
            // 用户在「规格」里只写了「500g」
            if let v = capture(#"^\s*(\d+(?:\.\d+)?)\s*(?:g|克|ml|毫升)\s*$"#, text.components(separatedBy: " ").last ?? "") {
                return v
            }
            return nil
        }
        switch String(text[ur]) {
        case "kg", "千克", "l", "升": return v * 1000
        default: return v
        }
    }

    private static func capture(_ pattern: String, _ text: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return Double(text[r])
    }

    private static func match(_ pattern: String, _ text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range, in: text) else { return nil }
        return String(text[r])
    }
}
