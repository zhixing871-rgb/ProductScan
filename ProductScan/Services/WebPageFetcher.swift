import Foundation
import UIKit
import WebKit

/// 从网页抓取到的商品信息
struct WebCapture {
    var url: String
    var title: String
    var price: String?          // 页面结构化数据里的价格（找不到时交给 AI 从正文里找）
    var currency: String?
    var content: String         // 发给 AI 的整理后文字
    var snapshot: UIImage?      // 当前可见区域截图（支持图片的模型可以直接看）
}

enum WebFetchError: LocalizedError {
    case noURL
    case notLoaded
    case empty

    var errorDescription: String? {
        switch self {
        case .noURL: return "没有找到有效的链接"
        case .notLoaded: return "页面还没加载完成，请稍等"
        case .empty: return "页面上没有抓到内容，可能需要先登录，或往下滑动让商品详情加载出来"
        }
    }
}

/// 从一段文字（如淘宝/京东/拼多多的分享口令）里找出第一个网址
enum LinkExtractor {
    static func firstURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        // iOS 默认禁止明文 http，统一升级为 https（主流购物网站都支持）
        let urls = detector.matches(in: trimmed, range: range).compactMap(\.url).map { u -> URL in
            guard u.scheme?.lowercased() == "http",
                  var c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return u }
            c.scheme = "https"
            return c.url ?? u
        }
        return urls.first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
            ?? urls.first.flatMap { u in
                // "item.jd.com/123.html" 这种没写 https 的
                u.scheme == nil ? URL(string: "https://" + u.absoluteString) : nil
            }
    }
}

/// 用一个真实的 WKWebView 打开商品页（能执行 JS、能登录），再提取页面文字、价格和详情图里的文字
@MainActor
@Observable
final class WebPageController: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var isLoading = false
    var progress: Double = 0
    var pageTitle = ""
    var loadError: String?
    var isCapturing = false
    var captureStatus = ""

    private var observations: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // 保留登录状态
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.estimatedProgress) { [weak self] wv, _ in
                let p = wv.estimatedProgress
                Task { @MainActor in self?.progress = p }
            },
            webView.observe(\.title) { [weak self] wv, _ in
                let t = wv.title ?? ""
                Task { @MainActor in self?.pageTitle = t }
            }
        ]
    }

    func load(_ url: URL) {
        loadError = nil
        webView.load(URLRequest(url: url))
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // 商品页常会尝试跳转到 taobao:// openapp.jdmobile:// 等 App 协议，这里拦掉，留在网页里
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        decisionHandler(["http", "https", "about", "data", "blob"].contains(scheme) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishWithError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishWithError(error)
    }

    private func finishWithError(_ error: Error) {
        isLoading = false
        let ns = error as NSError
        // 被我们拦截的 App 跳转 / 用户点了别的链接，不算错误
        if ns.code == NSURLErrorCancelled || ns.domain == "WebKitErrorDomain" { return }
        loadError = error.localizedDescription
    }

    // MARK: 抓取

    func capture() async throws -> WebCapture {
        isCapturing = true
        defer { isCapturing = false; captureStatus = "" }

        captureStatus = "读取页面文字…"
        let raw = try await webView.evaluateJavaScript(Self.extractScript)
        guard let json = raw as? String,
              let dict = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else {
            throw WebFetchError.empty
        }

        let url = dict["url"] as? String ?? webView.url?.absoluteString ?? ""
        let title = (dict["ldName"] as? String).nonEmpty
            ?? (dict["ogTitle"] as? String).nonEmpty
            ?? (dict["title"] as? String) ?? ""
        let description = [dict["ldDesc"], dict["ogDesc"], dict["metaDesc"]]
            .compactMap { ($0 as? String).nonEmpty }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let bodyText = Self.cleanBody(dict["text"] as? String ?? "")
        let imageURLs = (dict["images"] as? [String] ?? []).compactMap(URL.init(string:))

        let snapshot = try? await webView.takeSnapshot(configuration: nil)

        captureStatus = "识别详情图里的文字…"
        let imageText = await Self.ocrDetailImages(imageURLs, referer: url)

        var sections: [String] = []
        sections.append("【页面标题】\(title)")
        if let price = (dict["price"] as? String).nonEmpty {
            sections.append("【页面标价】\(price) \((dict["currency"] as? String) ?? "")")
        }
        if !description.isEmpty { sections.append("【商品描述】\n" + description.joined(separator: "\n")) }
        if !imageText.isEmpty { sections.append("【详情图中识别出的文字】\n" + imageText) }
        if !bodyText.isEmpty { sections.append("【页面正文（含无关内容）】\n" + bodyText) }

        guard !title.isEmpty || !bodyText.isEmpty || !imageText.isEmpty else { throw WebFetchError.empty }

        return WebCapture(
            url: url,
            title: title,
            price: (dict["price"] as? String).nonEmpty,
            currency: (dict["currency"] as? String).nonEmpty,
            content: sections.joined(separator: "\n\n"),
            snapshot: snapshot
        )
    }

    /// 去掉空行和重复行，限制长度，避免把整页导航、推荐商品都发给 AI
    private static func cleanBody(_ text: String, limit: Int = 6000) -> String {
        var seen = Set<String>()
        var lines: [String] = []
        var count = 0
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.count >= 2, !seen.contains(t) else { continue }
            seen.insert(t)
            lines.append(t)
            count += t.count
            if count > limit { break }
        }
        return lines.joined(separator: "\n")
    }

    /// 很多商家把配料表/成分表做成详情图：下载较大的图片在本机 OCR，只保留和成分相关的文字
    private static func ocrDetailImages(_ urls: [URL], referer: String) async -> String {
        let keywords = ["配料", "成分", "原料", "ingredient", "面料", "材质", "含量", "营养", "净含量",
                        "规格", "产地", "生产商", "制造商", "执行标准", "保质期", "使用方法", "注意事项", "全成分"]
        var results: [String] = []
        for url in urls.prefix(12) {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue(referer, forHTTPHeaderField: "Referer")
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let image = UIImage(data: data),
                  min(image.size.width, image.size.height) >= 200,
                  let text = try? await OCRService.recognizeText(in: image) else { continue }
            let lower = text.lowercased()
            if keywords.contains(where: { lower.contains($0) }) {
                results.append(text)
            }
            if results.joined().count > 4000 { break }
        }
        return results.joined(separator: "\n---\n")
    }

    /// 在页面里执行：读取标题、meta、JSON-LD 商品数据、价格、正文文字、详情大图地址
    private static let extractScript = """
    (() => {
      const meta = (sel) => { const e = document.querySelector(sel); return e ? (e.getAttribute('content') || '') : ''; };
      const products = [];
      const walk = (o) => {
        if (Array.isArray(o)) { o.forEach(walk); return; }
        if (!o || typeof o !== 'object') return;
        const t = o['@type'];
        if (t === 'Product' || (Array.isArray(t) && t.includes('Product'))) products.push(o);
        if (o['@graph']) walk(o['@graph']);
      };
      document.querySelectorAll('script[type="application/ld+json"]').forEach(s => {
        try { walk(JSON.parse(s.textContent)); } catch (e) {}
      });
      const p = products[0] || {};
      let offer = p.offers || {};
      if (Array.isArray(offer)) offer = offer[0] || {};
      let price = String(offer.price || offer.lowPrice || '') ||
                  meta('meta[property="product:price:amount"]') || meta('meta[property="og:price:amount"]') ||
                  meta('meta[itemprop="price"]');
      if (!price) {
        const el = document.querySelector('[itemprop="price"]');
        if (el) price = (el.getAttribute('content') || el.textContent || '').trim();
      }
      const currency = String(offer.priceCurrency || '') || meta('meta[property="product:price:currency"]') ||
                       meta('meta[itemprop="priceCurrency"]');
      const seen = new Set();
      const images = [];
      document.querySelectorAll('img').forEach(img => {
        const src = img.currentSrc || img.src || img.getAttribute('data-src') ||
                    img.getAttribute('data-ks-lazyload') || img.getAttribute('data-lazyload') || '';
        if (!src || !src.startsWith('http') || seen.has(src)) return;
        const w = img.naturalWidth || img.width || 0;
        const h = img.naturalHeight || img.height || 0;
        if (w && w < 300 && h < 300) return;   // 跳过图标、头像、小缩略图
        seen.add(src); images.push(src);
      });
      return JSON.stringify({
        url: location.href,
        title: document.title || '',
        ogTitle: meta('meta[property="og:title"]'),
        ogDesc: meta('meta[property="og:description"]'),
        metaDesc: meta('meta[name="description"]'),
        ldName: String(p.name || ''),
        ldDesc: String(p.description || ''),
        price: String(price || ''),
        currency: String(currency || ''),
        text: (document.body ? document.body.innerText : '').slice(0, 20000),
        images: images.slice(0, 30)
      });
    })()
    """
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
