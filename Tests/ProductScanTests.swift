import XCTest
@testable import ProductScan

/// AI 返回结果的清洗与解码
final class ResultParsingTests: XCTestCase {
    private func decode(_ raw: Any) throws -> AnalysisResult {
        let dict = try XCTUnwrap(AnalysisService.normalize(raw))
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(AnalysisResult.self, from: data)
    }

    func testNestedFieldsWrittenAsJSONStrings() throws {
        let r = try decode([
            "category": "food", "verdict": "偏甜", "summary": "s", "primaryScore": "3.5",
            "ingredients": #"[{"name":"白砂糖","function":"甜味","risk":"medium","note":""}]"#,
            "company": #"{"name":"某公司","background":"b","reputation":"r"}"#,
            "shortTermEffects": "血糖升高\n口渴"
        ])
        XCTAssertEqual(r.primaryScore, 3.5)
        XCTAssertEqual(r.ingredients.first?.name, "白砂糖")
        XCTAssertEqual(r.ingredients.first?.risk, .medium)
        XCTAssertEqual(r.company?.name, "某公司")
        XCTAssertEqual(r.shortTermEffects, ["血糖升高", "口渴"])
    }

    func testMarkdownFenceThinkTagAndTrailingComma() throws {
        let text = "<think>思考</think>结果如下：\n```json\n{\"category\":\"化妆品\",\"verdict\":\"温和\",\"primaryScore\":4,\"ingredients\":[\"水\",{\"name\":\"甘油\",\"risk\":\"安全\"}],\"company\":null,}\n```"
        let r = try decode(text)
        XCTAssertEqual(r.verdict, "温和")
        XCTAssertEqual(r.ingredients.map(\.name), ["水", "甘油"])
        XCTAssertEqual(r.ingredients.last?.risk, .safe)
        XCTAssertNil(r.company)
        XCTAssertEqual(ProductCategory(loose: r.category), .cosmetic)
    }

    func testWrappedObjectAndMissingFields() throws {
        let r = try decode(["result": ["verdict": "ok", "primaryScore": 2, "valueScore": NSNull()]])
        XCTAssertEqual(r.verdict, "ok")
        XCTAssertNil(r.valueScore)
        XCTAssertEqual(r.confidence, "中")
        XCTAssertTrue(r.personalWarnings.isEmpty)
    }

    func testNoJSONReturnsNil() {
        XCTAssertNil(AnalysisService.normalize("抱歉，我无法分析"))
    }
}

/// 本地知识库匹配
final class KnowledgeBaseTests: XCTestCase {
    func testEntriesLoaded() {
        XCTAssertGreaterThan(KnowledgeBase.entries.count, 500)
    }

    func testLongerNameWins() {
        let hits = KnowledgeBase.matches(in: "水、苯氧乙醇、甘油", category: .cosmetic)
        XCTAssertTrue(hits.contains { $0.hasPrefix("苯氧乙醇") })
        XCTAssertFalse(hits.contains { $0.hasPrefix("乙醇") }, "「苯氧乙醇」里的「乙醇」不应单独命中")
    }

    func testEnglishWholeWord() {
        let hits = KnowledgeBase.matches(in: "glyceryl stearate", category: .cosmetic)
        XCTAssertFalse(hits.contains { $0.contains("三乙醇胺") }, "tea 不应命中 stearate")
    }

    func testOrderFollowsLabel() {
        let hits = KnowledgeBase.matches(in: "小麦粉、白砂糖、棕榈油", category: .food)
        XCTAssertEqual(hits.first?.hasPrefix("小麦粉"), true)
    }

    func testAutoCategoryLabelsScope() {
        let hits = KnowledgeBase.matches(in: "烟酰胺", category: nil)
        XCTAssertTrue(hits.contains { $0.hasPrefix("[护肤]") })
    }
}

/// 过敏原本地检查
final class AllergenTests: XCTestCase {
    private var profile: UserProfile {
        var p = UserProfile()
        p.allergies = [.milk, .alcohol, .gluten, .peanut]
        p.customAllergies = "芒果"
        return p
    }

    private func names(_ text: String) -> [String] {
        AllergenChecker.check(text, profile: profile).map(\.name)
    }

    func testDetectsAllergens() {
        let n = names("小麦粉、全脂乳粉、花生碎、芒果干")
        XCTAssertTrue(n.contains("乳制品/乳糖"))
        XCTAssertTrue(n.contains("小麦/麸质"))
        XCTAssertTrue(n.contains("花生"))
        XCTAssertTrue(n.contains("芒果"))
    }

    func testNoFalsePositives() {
        XCTAssertTrue(names("可可脂、乳化剂、苯氧乙醇、Cetearyl Alcohol、无麸质燕麦").isEmpty)
    }

    func testDisabledProfileChecksNothing() {
        var p = profile
        p.enabled = false
        XCTAssertTrue(AllergenChecker.check("花生", profile: p).isEmpty)
    }

    func testBMI() {
        var p = UserProfile()
        p.heightCm = 170
        p.weightKg = 80
        XCTAssertEqual(p.bmi ?? 0, 27.68, accuracy: 0.01)
        XCTAssertEqual(p.bmiCategory, "超重")
    }
}

/// 营养成分表解析
final class NutritionTests: XCTestCase {
    func testMultilineChineseTable() throws {
        let text = "营养成分表\n项目\n每100克\nNRV%\n能量\n2050千焦\n24%\n蛋白质\n6.5克\n脂肪\n22.0克\n—饱和脂肪\n9.8克\n碳水化合物\n65.3克\n—糖\n28.0克\n钠\n380毫克\n配料：小麦粉、白砂糖\n净含量：120克"
        let n = try XCTUnwrap(NutritionParser.parse(text))
        XCTAssertEqual(n.basis, .per100g)
        XCTAssertEqual(n.value(.energy), 2050)
        XCTAssertEqual(n.value(.fat), 22)
        XCTAssertEqual(n.value(.saturatedFat), 9.8)
        XCTAssertEqual(n.value(.sugar), 28)
        XCTAssertEqual(n.value(.sodium), 380)
        XCTAssertEqual(n.netContent, 120)
        XCTAssertEqual(n.packageFactor ?? 0, 1.2, accuracy: 0.001)
    }

    func testEnglishPer100ml() throws {
        let n = try XCTUnwrap(NutritionParser.parse("Nutrition Facts per 100ml Energy 180kJ Fat 0g Carbohydrate 10.6g Sugars 10.6g Sodium 12mg"))
        XCTAssertEqual(n.basis, .per100ml)
        XCTAssertEqual(n.value(.sugar), 10.6)
        XCTAssertEqual(Nutrient.sugar.level(per100: 10.6, isLiquid: true), .medium)
    }

    func testKcalConverted() throws {
        let n = try XCTUnwrap(NutritionParser.parse("营养成分 每100g 能量 100kcal 蛋白质 3g"))
        XCTAssertEqual(n.value(.energy) ?? 0, 418.4, accuracy: 0.1)
    }

    func testIngredientSugarNotParsed() {
        XCTAssertNil(NutritionParser.parse("配料：白砂糖 20g、葡萄糖浆"))
    }

    func testPersonalReference() {
        var p = UserProfile()
        p.goals = [.controlSugar, .lowSalt]
        XCTAssertEqual(Nutrient.sugar.dailyReference(for: p), 25)
        XCTAssertEqual(Nutrient.sodium.dailyReference(for: p), 1500)
        XCTAssertEqual(Nutrient.sodium.dailyReference(for: nil), 2000)
    }
}

/// 链接提取与费用估算
final class MiscTests: XCTestCase {
    func testShareTextLink() {
        let url = LinkExtractor.firstURL(in: "【淘宝】7天无理由退货 https://e.tb.cn/h.abc?tk=xyz 「燕麦片」")
        XCTAssertEqual(url?.host, "e.tb.cn")
    }

    func testBareDomainUpgradedToHTTPS() {
        XCTAssertEqual(LinkExtractor.firstURL(in: "item.jd.com/100012345.html")?.scheme, "https")
    }

    func testPlainTextHasNoLink() {
        XCTAssertNil(LinkExtractor.firstURL(in: "某牌子洗发水 配料：水、月桂醇聚醚硫酸酯钠"))
    }

    func testUsageParsing() {
        let claude = TokenUsage(json: ["usage": ["input_tokens": 1000, "output_tokens": 500, "cache_read_input_tokens": 200]])
        XCTAssertEqual(claude?.inputTokens, 1200)
        let openai = TokenUsage(json: ["usage": ["prompt_tokens": 800, "completion_tokens": 300]])
        XCTAssertEqual(openai?.outputTokens, 300)
    }

    func testCostEstimate() {
        let usage = TokenUsage(inputTokens: 1_000_000, outputTokens: 0)
        XCTAssertEqual(Pricing.costText(model: "claude-sonnet-5-5", usage: usage), "约 $2.000")
        XCTAssertNotNil(Pricing.price(for: "gpt-5-mini-2026"))
        XCTAssertNil(Pricing.costText(model: "unknown-model", usage: usage))
    }
}
