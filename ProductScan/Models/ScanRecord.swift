import Foundation
import SwiftData

/// 本地保存的一次扫描记录（SwiftData）
@Model
final class ScanRecord {
    var id: UUID
    var createdAt: Date
    var categoryRaw: String
    var productName: String
    var price: Double?
    var currency: String
    var ocrText: String
    var primaryScore: Double
    var valueScore: Double?
    @Attribute(.externalStorage) var imageData: Data?
    var resultData: Data
    var modelName: String?              // 用哪个 AI 模型分析的
    var sourceURL: String?              // 链接模式下的商品网址
    var isFavorite: Bool = false        // 收藏
    var specText: String?               // 用户填写的规格/净含量
    var categoryWasAuto: Bool?          // 类别是否由 AI 自动判断（重新分析时沿用）
    var inputTokens: Int?               // 本次分析用量
    var outputTokens: Int?
    var costText: String?               // 估算花费，如「约 $0.012」
    var followUpData: Data?             // 追问对话（[FollowUpMessage] 的 JSON）
    var shoppingData: Data?             // 联网购物助手结果（ShoppingResult 的 JSON）

    init(category: ProductCategory,
         productName: String,
         price: Double?,
         currency: String,
         ocrText: String,
         imageData: Data?,
         result: AnalysisResult,
         modelName: String? = nil,
         sourceURL: String? = nil) {
        self.id = UUID()
        self.createdAt = .now
        self.categoryRaw = category.rawValue
        self.productName = productName
        self.price = price
        self.currency = currency
        self.ocrText = ocrText
        self.imageData = imageData
        self.primaryScore = result.primaryScore
        self.valueScore = result.valueScore
        self.resultData = (try? JSONEncoder().encode(result)) ?? Data()
        self.modelName = modelName
        self.sourceURL = sourceURL
    }

    var category: ProductCategory { ProductCategory(rawValue: categoryRaw) ?? .other }

    var usage: TokenUsage? {
        guard let i = inputTokens, let o = outputTokens else { return nil }
        return TokenUsage(inputTokens: i, outputTokens: o)
    }

    var followUps: [FollowUpMessage] {
        get { followUpData.flatMap { try? JSONDecoder().decode([FollowUpMessage].self, from: $0) } ?? [] }
        set { followUpData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var shopping: ShoppingResult? {
        get { shoppingData.flatMap { try? JSONDecoder().decode(ShoppingResult.self, from: $0) } }
        set { shoppingData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var result: AnalysisResult? {
        try? JSONDecoder().decode(AnalysisResult.self, from: resultData)
    }
}
