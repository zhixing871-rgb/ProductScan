import Foundation

/// 结果页「继续追问」里的一条消息
struct FollowUpMessage: Codable, Identifiable, Hashable {
    enum Role: String, Codable { case user, assistant }

    var id = UUID()
    var role: Role
    var text: String
    var date = Date()
    var usageText: String? = nil       // AI 回复的用量/花费

    init(role: Role, text: String, usageText: String? = nil) {
        self.role = role
        self.text = text
        self.usageText = usageText
    }
}

/// 进入追问页面时可带一个要立即发送的问题
struct FollowUpStart: Hashable, Identifiable {
    let id = UUID()
    var question: String?
}

extension ProductCategory {
    /// 追问页的推荐问题
    var suggestedQuestions: [String] {
        let specific: [String]
        switch self {
        case .food: specific = ["每次吃多少合适？", "减脂期能吃吗？"]
        case .cosmetic: specific = ["敏感肌能用吗？", "能和其他护肤品一起用吗？"]
        case .clothing: specific = ["怎么洗护不容易坏？", "适合什么季节穿？"]
        case .household: specific = ["对孩子和宠物安全吗？", "怎么用最省又有效？"]
        case .other: specific = ["和用手机/其他设备替代有什么区别？", "购买时要看哪些参数？"]
        }
        return specific + ["和同类产品比怎么样？", "有更值得买的替代吗？"]
    }
}
