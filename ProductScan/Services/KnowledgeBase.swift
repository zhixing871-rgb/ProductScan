import Foundation

/// 本地成分知识库：在调用 AI 之前先做一次关键词匹配，命中的条目会作为"参考资料"发给 AI，
/// 让结论更稳定。你可以随时往 Resources/knowledge_base.json 里加条目。
struct KBEntry: Codable {
    let keywords: [String]
    let category: String   // food / cosmetic / clothing / household / all
    let level: String      // 安全 / 低风险 / 注意 / 高风险 / 面料档次 等
    let note: String
}

enum KnowledgeBase {
    static let entries: [KBEntry] = {
        guard let url = Bundle.main.url(forResource: "knowledge_base", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([KBEntry].self, from: data) else { return [] }
        return list
    }()

    /// 预先转成小写，避免每次匹配重复计算
    private static let loweredKeywords: [[String]] = entries.map { e in
        e.keywords.map { $0.lowercased() }.filter { !$0.isEmpty }
    }

    /// 匹配规则：
    /// 1. 长词优先：「苯氧乙醇」命中后，其中的「乙醇」不再单独算命中；
    /// 2. 英文关键词按整词匹配：「tea」不会命中「stearate」；
    /// 3. 按成分在文字里出现的先后排序（配料表越靠前含量越高），最多返回 limit 条。
    static func matches(in text: String, category: ProductCategory?, limit: Int = 60) -> [String] {
        let lower = text.lowercased() as NSString
        guard lower.length > 0 else { return [] }

        struct Hit { let entry: Int; let range: NSRange; let keyword: String }
        var hits: [Hit] = []
        for (i, entry) in entries.enumerated() {
            guard category == nil || entry.category == category?.rawValue || entry.category == "all" else { continue }
            for kw in loweredKeywords[i] {
                let isASCII = kw.unicodeScalars.allSatisfy(\.isASCII)
                var search = NSRange(location: 0, length: lower.length)
                while true {
                    let r = lower.range(of: kw, options: [], range: search)
                    guard r.location != NSNotFound else { break }
                    if !isASCII || isWordBoundary(lower, r) { hits.append(Hit(entry: i, range: r, keyword: kw)) }
                    let next = r.location + max(r.length, 1)
                    guard next < lower.length else { break }
                    search = NSRange(location: next, length: lower.length - next)
                }
            }
        }

        // 长的命中优先占位，被其他条目的更长命中完全覆盖的短命中丢弃
        var accepted: [Hit] = []
        for hit in hits.sorted(by: { $0.range.length > $1.range.length }) {
            let covered = accepted.contains { a in
                a.entry != hit.entry && a.range.length > hit.range.length &&
                NSIntersectionRange(a.range, hit.range).length == hit.range.length
            }
            if !covered { accepted.append(hit) }
        }

        // 每个条目取最早出现的命中
        var first: [Int: Hit] = [:]
        for hit in accepted where hit.range.location < (first[hit.entry]?.range.location ?? .max) {
            first[hit.entry] = hit
        }
        return first.values
            .sorted { $0.range.location < $1.range.location }
            .prefix(limit)
            .map { hit in
                let e = entries[hit.entry]
                let name = e.keywords.first ?? hit.keyword
                // 显示实际命中的词；自动类别时标注条目所属类别，同名成分在不同品类的结论可能不同
                let label = hit.keyword == name.lowercased() ? name : "\(hit.keyword)（\(name)）"
                let scope = category == nil ? "[\(ProductCategory(rawValue: e.category)?.shortTitle ?? "通用")] " : ""
                return "\(scope)\(label)【\(e.level)】\(e.note)"
            }
    }

    private static func isWordBoundary(_ s: NSString, _ r: NSRange) -> Bool {
        func isWordChar(_ c: unichar) -> Bool {
            (c >= 48 && c <= 57) || (c >= 97 && c <= 122) || (c >= 65 && c <= 90)
        }
        if r.location > 0, isWordChar(s.character(at: r.location - 1)) { return false }
        let end = r.location + r.length
        if end < s.length, isWordChar(s.character(at: end)) { return false }
        return true
    }
}
