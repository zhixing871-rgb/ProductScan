import Foundation

/// 支持分析的商品类别。Agent 只处理这些类别。
enum ProductCategory: String, CaseIterable, Codable, Identifiable {
    case food
    case cosmetic
    case clothing
    case household

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: return "食品"
        case .cosmetic: return "化妆/护肤"
        case .clothing: return "服装纺织"
        case .household: return "日化用品"
        }
    }

    /// 分段选择器用的短名称
    var shortTitle: String {
        switch self {
        case .food: return "食品"
        case .cosmetic: return "护肤"
        case .clothing: return "服装"
        case .household: return "日化"
        }
    }

    /// 把 AI 返回的类别（英文或中文）转成枚举
    init?(loose raw: String?) {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return nil }
        if let exact = ProductCategory(rawValue: raw) { self = exact; return }
        if raw.contains("食") || raw.contains("饮") { self = .food }
        else if raw.contains("妆") || raw.contains("护肤") || raw.contains("cosmetic") || raw.contains("skin") { self = .cosmetic }
        else if raw.contains("服") || raw.contains("衣") || raw.contains("纺织") || raw.contains("cloth") { self = .clothing }
        else if raw.contains("日化") || raw.contains("清洁") || raw.contains("洗") || raw.contains("house") { self = .household }
        else { return nil }
    }

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .cosmetic: return "drop"
        case .clothing: return "tshirt"
        case .household: return "bubbles.and.sparkles"
        }
    }

    /// 第一项评分的含义随类别变化
    var primaryScoreLabel: String {
        switch self {
        case .food: return "健康度"
        case .cosmetic: return "成分安全度"
        case .clothing: return "品质/实用性"
        case .household: return "安全/实用性"
        }
    }

    /// 发给 AI 的类别专属分析要点
    var analysisFocus: String {
        switch self {
        case .food:
            return """
            重点：配料表排序（越靠前含量越高）、添加糖/代糖、钠、反式脂肪/氢化油、精制碳水、\
            防腐剂、合成色素、增稠剂/乳化剂、超加工程度、过敏原；营养成分表（如果有）。\
            短期影响：血糖波动、肠胃反应、过敏等；长期影响：长期大量食用对代谢、心血管、肠道菌群等的风险。\
            健康度评分：5=天然少加工、配料简单；1=高糖/高盐/反式脂肪/大量添加剂的超加工食品。
            """
        case .cosmetic:
            return """
            重点：致敏/刺激成分（香精、酒精、某些防腐剂如 MIT/MCI）、甲醛释放体、争议成分（部分对羟基苯甲酸酯、\
            某些化学防晒剂）、违禁或限用成分（汞、氢醌等）、孕妇/哺乳期慎用成分（如高浓度视黄醇、水杨酸）、\
            有效活性成分及其大致位置（浓度）、是否有"概念性添加"（宣传成分排在很后）。\
            短期影响：刺激、泛红、闷痘、过敏；长期影响：屏障受损、内分泌干扰争议、光敏等。\
            安全度评分：5=温和无争议且配方合理；1=含违禁/高风险成分。
            """
        case .clothing:
            return """
            重点：纤维成分及比例（棉、羊毛、真丝、亚麻、莫代尔、粘纤、聚酯纤维、锦纶、腈纶、氨纶等）、\
            对应用途是否合理（贴身、保暖、运动、透气）、起球/缩水/静电/耐用性、护理难度、安全技术类别（A/B/C类）。\
            短期：穿着舒适度、透气、静电、致敏；长期：耐穿性、变形、起球、洗涤后表现。\
            品质评分：结合面料档次与用途匹配度；性价比评分重点判断"这个价格买这个成分值不值"。
            """
        case .household:
            return """
            重点：表面活性剂类型与刺激性、防腐剂、香精、荧光增白剂、磷、含氯/强酸强碱成分、混用危险\
            （如含氯与酸性清洁剂混用）、对皮肤和环境的影响、对儿童宠物的安全性。\
            安全/实用性评分：兼顾安全性与功效。
            """
        }
    }
}
