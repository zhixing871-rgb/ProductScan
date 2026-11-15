import Foundation

/// 购物网站：用于生成商品搜索链接、指定比价范围
enum ShopSite: String, CaseIterable, Codable, Identifiable {
    case taobao, jd, pdd, alibaba1688, amazon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .taobao: return "淘宝/天猫"
        case .jd: return "京东"
        case .pdd: return "拼多多"
        case .alibaba1688: return "1688（批发）"
        case .amazon: return "亚马逊"
        }
    }

    var shortTitle: String {
        switch self {
        case .taobao: return "淘宝"
        case .jd: return "京东"
        case .pdd: return "拼多多"
        case .alibaba1688: return "1688"
        case .amazon: return "亚马逊"
        }
    }

    var domains: [String] {
        switch self {
        case .taobao: return ["taobao.com", "tmall.com"]
        case .jd: return ["jd.com"]
        case .pdd: return ["pinduoduo.com", "yangkeduo.com"]
        case .alibaba1688: return ["1688.com"]
        case .amazon: return ["amazon.com", "amazon.co.jp", "amazon.com.au"]
        }
    }

    /// 在该网站搜索某个商品的链接（不由 AI 编造，保证能打开）
    func searchURL(_ query: String) -> URL? {
        var c: URLComponents
        switch self {
        case .taobao:
            c = URLComponents(string: "https://s.taobao.com/search")!
            c.queryItems = [URLQueryItem(name: "q", value: query)]
        case .jd:
            c = URLComponents(string: "https://search.jd.com/Search")!
            c.queryItems = [URLQueryItem(name: "keyword", value: query), URLQueryItem(name: "enc", value: "utf-8")]
        case .pdd:
            c = URLComponents(string: "https://mobile.yangkeduo.com/search_result.html")!
            c.queryItems = [URLQueryItem(name: "search_key", value: query)]
        case .alibaba1688:
            c = URLComponents(string: "https://s.1688.com/selloffer/offer_search.htm")!
            c.queryItems = [URLQueryItem(name: "keywords", value: query), URLQueryItem(name: "charset", value: "utf8")]
        case .amazon:
            c = URLComponents(string: "https://www.amazon.com/s")!
            c.queryItems = [URLQueryItem(name: "k", value: query)]
        }
        return c.url
    }

    /// 按名称（AI 返回的平台名）找网站
    init?(loose raw: String?) {
        guard let s = raw?.lowercased(), !s.isEmpty else { return nil }
        if s.contains("1688") || s.contains("批发") || s.contains("阿里巴巴") { self = .alibaba1688 }
        else if s.contains("淘宝") || s.contains("天猫") || s.contains("taobao") || s.contains("tmall") { self = .taobao }
        else if s.contains("京东") || s.contains("jd") { self = .jd }
        else if s.contains("拼多多") || s.contains("pdd") || s.contains("pinduoduo") { self = .pdd }
        else if s.contains("亚马逊") || s.contains("amazon") { self = .amazon }
        else { return nil }
    }
}

/// 「联网购物助手」设置（默认全部关闭）
struct ShoppingSettings {
    static let recommendKey = "shop.recommend"
    static let priceCheckKey = "shop.priceCheck"
    static let linkSiteKey = "shop.linkSite"        // ShopSite.rawValue，或 "none"
    static let priceSitesKey = "shop.priceSites"    // 逗号分隔的 ShopSite.rawValue
    static let defaultPriceSites = "alibaba1688,taobao,jd,pdd"

    var recommendEnabled: Bool
    var priceCheckEnabled: Bool
    var linkSite: ShopSite?
    var priceSites: [ShopSite]

    static func current() -> ShoppingSettings {
        let d = UserDefaults.standard
        let sites = (d.string(forKey: priceSitesKey) ?? defaultPriceSites)
            .split(separator: ",").compactMap { ShopSite(rawValue: String($0)) }
        return ShoppingSettings(
            recommendEnabled: d.bool(forKey: recommendKey),
            priceCheckEnabled: d.bool(forKey: priceCheckKey),
            linkSite: ShopSite(rawValue: d.string(forKey: linkSiteKey) ?? "taobao"),
            priceSites: sites.isEmpty ? [.taobao, .jd] : sites
        )
    }

    /// 低于这个分数（健康/品质 或 性价比）时推荐替代品
    static let threshold = 3.0

    /// 这条记录应自动执行哪项联网查询（nil = 不需要）
    func task(for record: ScanRecord) -> ShoppingKind? {
        guard let r = record.result, r.productType != "非商品" else { return nil }
        if record.sourceURL != nil {
            guard recommendEnabled else { return nil }
            let low = r.primaryScore < Self.threshold || (r.valueScore ?? 5) < Self.threshold
            return low ? .alternatives : nil
        }
        return priceCheckEnabled ? .prices : nil
    }
}

enum ShoppingKind: String, Codable {
    case alternatives   // 线上链接：低分时推荐更好的同类商品
    case prices         // 线下拍照：查询网上价格
}

/// 联网查询得到的一个商品
struct ShoppingItem: Codable, Hashable {
    var name: String
    var platform: String?
    var price: String?
    var reason: String?
    var url: String?

    init(name: String, platform: String? = nil, price: String? = nil, reason: String? = nil, url: String? = nil) {
        self.name = name; self.platform = platform; self.price = price; self.reason = reason; self.url = url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys) -> String? {
            if let s = try? c.decode(String.self, forKey: k) { return s.trimmed.isEmpty ? nil : s.trimmed }
            if let d = try? c.decode(Double.self, forKey: k) { return String(format: "%g", d) }
            return nil
        }
        name = str(.name) ?? "未命名商品"
        platform = str(.platform)
        price = str(.price)
        reason = str(.reason)
        url = str(.url)
    }

    /// 只信任 https 网页链接
    var webURL: URL? {
        guard let url, let u = URL(string: url), u.scheme == "https", u.host != nil else { return nil }
        return u
    }
}

/// 一次联网查询的结果
struct ShoppingResult: Codable, Hashable {
    var kind: ShoppingKind
    var summary: String
    var items: [ShoppingItem]
    var searched: Bool          // 是否真的联网搜索了（DeepSeek 等不支持时为 false）
    var date = Date()
    var usageText: String?
}
