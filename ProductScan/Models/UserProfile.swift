import Foundation

/// 用户个人信息：只保存在本机，开启后随分析请求发给 AI，用于个性化建议
struct UserProfile: Codable, Equatable {
    var enabled = true
    var age: Int?
    var gender: Gender = .unspecified
    var heightCm: Double?
    var weightKg: Double?
    var goals: Set<HealthGoal> = []
    var skinType: SkinType = .unspecified
    var allergies: Set<Allergen> = []
    var customAllergies = ""
    var diets: Set<DietRestriction> = []
    var customDiet = ""
    var notes = ""

    init() {}

    // 宽松解码：以后新增字段时，旧数据也能正常读取
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        age = try? c.decodeIfPresent(Int.self, forKey: .age)
        gender = (try? c.decode(Gender.self, forKey: .gender)) ?? .unspecified
        heightCm = try? c.decodeIfPresent(Double.self, forKey: .heightCm)
        weightKg = try? c.decodeIfPresent(Double.self, forKey: .weightKg)
        goals = (try? c.decode(Set<HealthGoal>.self, forKey: .goals)) ?? []
        skinType = (try? c.decode(SkinType.self, forKey: .skinType)) ?? .unspecified
        allergies = (try? c.decode(Set<Allergen>.self, forKey: .allergies)) ?? []
        customAllergies = (try? c.decode(String.self, forKey: .customAllergies)) ?? ""
        diets = (try? c.decode(Set<DietRestriction>.self, forKey: .diets)) ?? []
        customDiet = (try? c.decode(String.self, forKey: .customDiet)) ?? ""
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
    }

    // MARK: BMI（中国成人标准）

    var bmi: Double? {
        guard let h = heightCm, let w = weightKg, h > 50, w > 10 else { return nil }
        let m = h / 100
        return w / (m * m)
    }

    var bmiCategory: String? {
        guard let bmi else { return nil }
        switch bmi {
        case ..<18.5: return "偏瘦"
        case ..<24: return "正常"
        case ..<28: return "超重"
        default: return "肥胖"
        }
    }

    var isEmpty: Bool {
        age == nil && gender == .unspecified && heightCm == nil && weightKg == nil &&
        goals.isEmpty && skinType == .unspecified && allergies.isEmpty &&
        customAllergies.trimmed.isEmpty && diets.isEmpty && customDiet.trimmed.isEmpty && notes.trimmed.isEmpty
    }

    /// 是否参与分析
    var isActive: Bool { enabled && !isEmpty }

    /// 所有过敏项的名称（含自定义）
    var allergyNames: [String] {
        allergies.sorted { $0.rawValue < $1.rawValue }.map(\.title) + Self.splitList(customAllergies)
    }

    /// 设置页、扫描页上显示的一行摘要
    var summary: String {
        var parts: [String] = []
        if let age { parts.append("\(age)岁") }
        if gender != .unspecified { parts.append(gender.title) }
        if let bmi, let cat = bmiCategory { parts.append("BMI \(String(format: "%.1f", bmi)) \(cat)") }
        parts += goals.sorted { $0.rawValue < $1.rawValue }.map(\.title)
        if !allergyNames.isEmpty { parts.append("过敏：" + allergyNames.joined(separator: "、")) }
        let dietNames = diets.sorted { $0.rawValue < $1.rawValue }.map(\.title) + Self.splitList(customDiet)
        if !dietNames.isEmpty { parts.append("忌口：" + dietNames.joined(separator: "、")) }
        return parts.isEmpty ? "未填写" : parts.joined(separator: " · ")
    }

    /// 发给 AI 的个人情况描述
    var promptText: String {
        var lines: [String] = []
        var basic: [String] = []
        if let age { basic.append("\(age)岁") }
        if gender != .unspecified { basic.append(gender.title) }
        if let h = heightCm { basic.append("身高\(Int(h))cm") }
        if let w = weightKg { basic.append("体重\(String(format: "%.1f", w))kg") }
        if let bmi, let cat = bmiCategory { basic.append("BMI \(String(format: "%.1f", bmi))（\(cat)）") }
        if !basic.isEmpty { lines.append("- 基本信息：" + basic.joined(separator: "，")) }
        if !goals.isEmpty {
            lines.append("- 当前状态/健康目标：" + goals.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: "、"))
        }
        if skinType != .unspecified { lines.append("- 肤质：\(skinType.title)") }
        if !allergyNames.isEmpty { lines.append("- 过敏/不耐受（务必重点检查）：" + allergyNames.joined(separator: "、")) }
        let dietNames = diets.sorted { $0.rawValue < $1.rawValue }.map(\.title) + Self.splitList(customDiet)
        if !dietNames.isEmpty { lines.append("- 忌口/饮食习惯：" + dietNames.joined(separator: "、")) }
        if !notes.trimmed.isEmpty { lines.append("- 其他情况：\(notes.trimmed)") }
        return lines.joined(separator: "\n")
    }

    static func splitList(_ s: String) -> [String] {
        s.components(separatedBy: CharacterSet(charactersIn: ",，、;；/ \n"))
            .map(\.trimmed).filter { !$0.isEmpty }
    }

    // MARK: 存储

    private static let storageKey = "userProfile"

    static func load() -> UserProfile {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let p = try? JSONDecoder().decode(UserProfile.self, from: data) else { return UserProfile() }
        return p
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

enum Gender: String, Codable, CaseIterable, Identifiable {
    case unspecified, male, female
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unspecified: return "不填"
        case .male: return "男"
        case .female: return "女"
        }
    }
}

enum HealthGoal: String, Codable, CaseIterable, Identifiable {
    case loseFat, gainMuscle, controlSugar, lowSalt, lowLipid, gout, pregnant, breastfeeding,
         conceiving, kidney, sensitiveStomach, hasInfant
    var id: String { rawValue }
    var title: String {
        switch self {
        case .loseFat: return "减脂期"
        case .gainMuscle: return "增肌期"
        case .controlSugar: return "控糖/糖尿病"
        case .lowSalt: return "高血压/控盐"
        case .lowLipid: return "高血脂"
        case .gout: return "痛风/高尿酸"
        case .pregnant: return "孕期"
        case .breastfeeding: return "哺乳期"
        case .conceiving: return "备孕"
        case .kidney: return "肾病"
        case .sensitiveStomach: return "肠胃敏感"
        case .hasInfant: return "家有婴幼儿"
        }
    }
}

enum SkinType: String, Codable, CaseIterable, Identifiable {
    case unspecified, dry, oily, combination, normal, sensitive, acne
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unspecified: return "不填"
        case .dry: return "干性"
        case .oily: return "油性"
        case .combination: return "混合性"
        case .normal: return "中性"
        case .sensitive: return "敏感肌"
        case .acne: return "痘痘肌"
        }
    }
}

enum DietRestriction: String, Codable, CaseIterable, Identifiable {
    case vegetarian, vegan, halal, noPork, noBeef, glutenFree, lowCarb, noAlcohol, noCaffeine, noSpicy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vegetarian: return "素食（蛋奶素）"
        case .vegan: return "纯素"
        case .halal: return "清真"
        case .noPork: return "不吃猪肉"
        case .noBeef: return "不吃牛肉"
        case .glutenFree: return "无麸质"
        case .lowCarb: return "低碳水/生酮"
        case .noAlcohol: return "不含酒精"
        case .noCaffeine: return "不含咖啡因"
        case .noSpicy: return "不吃辣"
        }
    }
}

/// 常见过敏原，带本地关键词，用于在 AI 之外再做一次可靠的本地检查
enum Allergen: String, Codable, CaseIterable, Identifiable {
    case peanut, treeNut, milk, egg, shellfish, fish, soy, gluten, sesame, sulfite,
         fragrance, alcohol, isothiazolinone, wool, latex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .peanut: return "花生"
        case .treeNut: return "坚果"
        case .milk: return "乳制品/乳糖"
        case .egg: return "鸡蛋"
        case .shellfish: return "虾蟹贝类"
        case .fish: return "鱼类"
        case .soy: return "大豆"
        case .gluten: return "小麦/麸质"
        case .sesame: return "芝麻"
        case .sulfite: return "亚硫酸盐"
        case .fragrance: return "香精香料"
        case .alcohol: return "酒精"
        case .isothiazolinone: return "MIT/卡松防腐剂"
        case .wool: return "羊毛/动物毛"
        case .latex: return "乳胶"
        }
    }

    var keywords: [String] {
        switch self {
        case .peanut: return ["花生", "peanut", "groundnut"]
        case .treeNut: return ["坚果", "杏仁", "扁桃仁", "核桃", "腰果", "榛子", "开心果", "碧根果", "夏威夷果", "松子", "巴旦木",
                               "almond", "walnut", "cashew", "hazelnut", "pistachio", "pecan", "macadamia"]
        case .milk: return ["牛奶", "生牛乳", "生乳", "乳粉", "奶粉", "乳清", "酪蛋白", "酪朊酸", "奶油", "黄油", "奶酪", "干酪", "芝士",
                            "乳糖", "炼乳", "牛乳", "milk", "whey", "casein", "lactose", "butter", "cheese"]
        case .egg: return ["鸡蛋", "蛋黄", "蛋清", "蛋白粉", "全蛋", "蛋液", "蛋粉", "egg"]
        case .shellfish: return ["虾", "蟹", "贝类", "扇贝", "牡蛎", "生蚝", "蚝油", "蛤", "贻贝", "鱿鱼", "shrimp", "prawn", "crab",
                                 "lobster", "shellfish", "oyster", "mussel"]
        case .fish: return ["鱼", "鱼露", "鱼油", "fish", "anchovy", "salmon", "tuna"]
        case .soy: return ["大豆", "黄豆", "豆粕", "酱油", "豆腐", "豆浆", "soy", "soya", "soybean"]
        case .gluten: return ["小麦", "面粉", "麸质", "谷朊粉", "面筋", "大麦", "黑麦", "wheat", "gluten", "barley", "rye"]
        case .sesame: return ["芝麻", "麻酱", "香油", "sesame"]
        case .sulfite: return ["二氧化硫", "亚硫酸", "焦亚硫酸", "sulfite", "sulphite", "metabisulfite"]
        case .fragrance: return ["香精", "香料", "香氛", "fragrance", "parfum", "芳樟醇", "柠檬烯", "linalool", "limonene"]
        case .alcohol: return ["乙醇", "酒精", "变性乙醇", "ethanol", "alcohol denat", "alcohol"]
        case .isothiazolinone: return ["甲基异噻唑啉酮", "甲基氯异噻唑啉酮", "卡松", "methylisothiazolinone",
                                       "methylchloroisothiazolinone", "kathon"]
        case .wool: return ["羊毛", "羊绒", "马海毛", "兔毛", "驼绒", "羊驼毛", "wool", "cashmere", "mohair", "angora"]
        case .latex: return ["乳胶", "天然橡胶", "latex"]
        }
    }

    /// 会造成误报的词，匹配前先去掉（如「苯氧乙醇」不是酒精，「无麸质」不是含麸质）
    var excludes: [String] {
        switch self {
        case .alcohol: return ["苯氧乙醇", "苯乙醇", "乙醇胺", "苯甲醇", "cetyl alcohol", "stearyl alcohol", "cetearyl alcohol",
                               "benzyl alcohol", "behenyl alcohol", "lanolin alcohol", "phenethyl alcohol", "无酒精", "不含酒精",
                               "alcohol free", "alcohol-free"]
        case .gluten: return ["无麸质", "不含麸质", "gluten free", "gluten-free"]
        case .milk: return ["可可脂", "乳化剂", "乳木果", "乳酸", "cocoa butter", "shea butter", "peanut butter", "无乳糖", "lactose free",
                            "乳酸菌"]
        case .fish: return ["鱿鱼"]   // 鱿鱼属于软体动物，归到虾蟹贝类
        case .fragrance: return ["无香精", "不含香精", "fragrance free", "fragrance-free"]
        case .peanut: return ["无花生"]
        case .soy: return []
        default: return []
        }
    }
}

/// 本地过敏原检查结果
struct AllergenHit: Hashable {
    let name: String
    let words: [String]
}

enum AllergenChecker {
    /// 在标签文字里查找用户选择的过敏原
    static func check(_ text: String, profile: UserProfile) -> [AllergenHit] {
        guard profile.enabled, !text.isEmpty else { return [] }
        let lower = text.lowercased()
        var hits: [AllergenHit] = []
        for allergen in Allergen.allCases where profile.allergies.contains(allergen) {
            var cleaned = lower
            for ex in allergen.excludes { cleaned = cleaned.replacingOccurrences(of: ex.lowercased(), with: " ") }
            let found = allergen.keywords.filter { contains(cleaned, $0.lowercased()) }
            if !found.isEmpty { hits.append(AllergenHit(name: allergen.title, words: found)) }
        }
        // 自定义过敏项直接按文字匹配
        for custom in UserProfile.splitList(profile.customAllergies) where custom.count >= 1 {
            if contains(lower, custom.lowercased()) { hits.append(AllergenHit(name: custom, words: [custom])) }
        }
        return hits
    }

    private static func contains(_ text: String, _ kw: String) -> Bool {
        guard !kw.isEmpty else { return false }
        guard kw.unicodeScalars.allSatisfy(\.isASCII) else { return text.contains(kw) }
        // 英文按整词匹配
        var start = text.startIndex
        while let r = text.range(of: kw, range: start..<text.endIndex) {
            let before = r.lowerBound == text.startIndex ? nil : text[text.index(before: r.lowerBound)]
            let after = r.upperBound == text.endIndex ? nil : text[r.upperBound]
            let isWord: (Character?) -> Bool = { c in c.map { $0.isASCII && ($0.isLetter || $0.isNumber) } ?? false }
            if !isWord(before) && !isWord(after) { return true }
            start = r.upperBound
        }
        return false
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
