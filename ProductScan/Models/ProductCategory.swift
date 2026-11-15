import Foundation

/// 商品类别：由 AI 自动判断。前四类有专门的成分分析要点，其余所有商品归入 other。
enum ProductCategory: String, CaseIterable, Codable, Identifiable {
    case food
    case cosmetic
    case clothing
    case household
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: return "食品"
        case .cosmetic: return "化妆/护肤"
        case .clothing: return "服装纺织"
        case .household: return "日化用品"
        case .other: return "其他商品"
        }
    }

    /// 分段选择器用的短名称
    var shortTitle: String {
        switch self {
        case .food: return "食品"
        case .cosmetic: return "护肤"
        case .clothing: return "服装"
        case .household: return "日化"
        case .other: return "其他"
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
        else { self = .other }
    }

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .cosmetic: return "drop"
        case .clothing: return "tshirt"
        case .household: return "bubbles.and.sparkles"
        case .other: return "shippingbox"
        }
    }

    /// 第一项评分的含义随类别变化
    var primaryScoreLabel: String {
        switch self {
        case .food: return "健康度"
        case .cosmetic: return "成分安全度"
        case .clothing: return "品质/实用性"
        case .household: return "安全/实用性"
        case .other: return "品质/安全"
        }
    }

    /// 结果页「成分」区块的标题
    var ingredientsLabel: String {
        switch self {
        case .clothing: return "面料与成分"
        case .other: return "材质 / 部件 / 关键参数"
        default: return "成分解读"
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
        case .other:
            return """
            适用于前四类以外的所有商品：电子产品/数码/家电、玩具、家具家居、厨具餐具、母婴用品、文具、\
            运动户外、汽车用品、宠物用品、保健品/营养补充剂、医疗器械、图书等。
            先判断具体商品类型并填入 productType（如「智能手机」「儿童积木」「保温杯」）。
            ingredients 改为列出主要材质、关键部件或核心参数（如 机身材质、电池容量/类型、屏幕、处理器、接口、\
            食品接触材料、填充物），function 写用途或参数含义，risk 写安全风险等级。
            重点：安全认证与合规（中国 3C/CCC、CE、FCC、食品接触材料 GB 4806、儿童玩具 GB 6675、无线电型号核准等），\
            材质安全（如 BPA、邻苯二甲酸酯、铅镉等重金属、甲醛释放、小零件窒息风险），电池与电气安全\
            （锂电池鼓包、充电发热、过充保护），耐用性与做工、维修与售后、环保（RoHS），\
            电子产品还要关注隐私与数据安全、系统更新支持年限、配置与同价位竞品对比。
            保健品/营养补充剂：看有效成分及剂量、是否有国家「蓝帽子」保健食品批号、是否夸大宣传，强调不能替代药物。
            药品和医疗器械：只做科普说明，提醒遵医嘱，不给剂量建议。
            短期影响写使用体验和可能的不适/风险；长期影响写耐用性、健康或安全隐患、持续使用成本。
            品质/安全评分：5=做工可靠、认证齐全、材质安全；1=存在明显安全隐患或无合规认证。
            """
        }
    }
}
