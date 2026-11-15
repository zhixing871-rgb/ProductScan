import SwiftUI
import SwiftData

enum InputMode: String, CaseIterable, Identifiable {
    case photo, link
    var id: String { rawValue }
    var title: String { self == .photo ? "拍照识别" : "链接 / 文字" }
}

/// 让 URL 能用于 .sheet(item:)
struct WebTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

@MainActor
@Observable
final class ScanViewModel {
    var mode: InputMode = .photo
    var category: ProductCategory? = nil      // nil = AI 自动识别类别
    var image: UIImage?
    var ocrText = ""
    var productName = ""
    var priceText = ""
    var specText = ""

    // 链接模式
    var linkText = ""
    var sourceURL: String?                    // 已抓取的网页地址
    var pageCurrency: String?                 // 网页上的价格货币
    var webTarget: WebTarget?                 // 要打开的网页
    var detectedLink: URL?                    // 拍照模式下在照片里发现的二维码链接

    var isRecognizing = false
    var isAnalyzing = false
    var errorMessage: String?

    var price: Double? {
        Double(priceText.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "¥", with: "").replacingOccurrences(of: "￥", with: "")
            .trimmingCharacters(in: .whitespaces))
    }

    var canAnalyze: Bool {
        !isAnalyzing && !isRecognizing &&
        (image != nil ||
         !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
         !productName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    func setImage(_ newImage: UIImage) async {
        image = newImage
        sourceURL = nil
        detectedLink = nil
        isRecognizing = true
        errorMessage = nil
        defer { isRecognizing = false }
        async let codes = OCRService.detectCodes(in: newImage)
        do {
            ocrText = try await OCRService.recognizeText(in: newImage)
        } catch {
            errorMessage = error.localizedDescription
        }
        // 照片里有商品二维码时，提示可以改用链接抓取
        detectedLink = await codes.lazy.compactMap(LinkExtractor.firstURL(in:)).first
        if detectedLink != nil { errorMessage = nil }
    }

    // MARK: 链接模式

    enum LinkAction { case openedWeb, useAsText, nothing }

    /// 输入框里有链接 → 打开网页抓取；只有文字 → 直接当商品描述分析
    func submitLink() -> LinkAction {
        errorMessage = nil
        let text = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .nothing }
        if let url = LinkExtractor.firstURL(in: text) {
            webTarget = WebTarget(url: url)
            return .openedWeb
        }
        sourceURL = nil
        image = nil
        ocrText = text
        return .useAsText
    }

    /// 从二维码图片里读取链接
    func scanCode(from img: UIImage) async {
        errorMessage = nil
        isRecognizing = true
        defer { isRecognizing = false }
        let codes = await OCRService.detectCodes(in: img)
        if let url = codes.lazy.compactMap(LinkExtractor.firstURL(in:)).first {
            linkText = url.absoluteString
            webTarget = WebTarget(url: url)
        } else if let code = codes.first {
            if code.allSatisfy(\.isNumber) {
                errorMessage = "识别到商品条形码 \(code)，暂不支持条码查询。可以在网购 App 里搜索后复制商品链接粘贴进来"
            } else {
                linkText = code
                errorMessage = "二维码内容不是链接，已填入输入框，可直接作为文字分析"
            }
        } else {
            errorMessage = "图片里没有识别到二维码，请拍得更近更清楚一些"
        }
    }

    func applyCapture(_ capture: WebCapture) {
        sourceURL = capture.url
        ocrText = capture.content
        image = capture.snapshot
        pageCurrency = capture.currency
        if productName.trimmingCharacters(in: .whitespaces).isEmpty {
            productName = String(capture.title.prefix(60))
        }
        if priceText.trimmingCharacters(in: .whitespaces).isEmpty, let p = capture.price, Double(p) != nil {
            priceText = p
        }
    }

    // MARK: 分析

    /// 调用 AI 分析并保存记录，成功返回记录
    func analyze(context: ModelContext) async -> ScanRecord? {
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }

        let defaultCurrency = UserDefaults.standard.string(forKey: "currency") ?? SettingsView.defaultCurrency
        let currency = (sourceURL != nil ? pageCurrency : nil) ?? defaultCurrency
        let settings = AISettings.current()
        let service = AnalysisService(settings: settings)

        let input = AnalysisService.Input(
            category: category,
            productName: productName.trimmingCharacters(in: .whitespaces),
            price: price,
            currency: currency,
            spec: specText.trimmingCharacters(in: .whitespaces),
            ocrText: ocrText.trimmingCharacters(in: .whitespacesAndNewlines),
            imageJPEG: image?.thumbnailJPEG(maxDimension: 1568, quality: 0.7),
            sourceURL: sourceURL
        )

        do {
            let result = try await service.analyze(input)
            // 用户手动选的类别优先，否则用 AI 识别出的类别
            let finalCategory = category ?? ProductCategory(loose: result.category) ?? .food
            let finalPrice = price ?? result.detectedPrice
            let finalCurrency = price == nil ? (result.detectedCurrency ?? currency) : currency
            let record = ScanRecord(
                category: finalCategory,
                productName: input.productName.isEmpty ? result.productName : input.productName,
                price: finalPrice,
                currency: finalCurrency,
                ocrText: input.ocrText,
                imageData: image?.thumbnailJPEG(),
                result: result,
                modelName: "\(settings.provider.shortTitle) · \(settings.model)",
                sourceURL: sourceURL
            )
            context.insert(record)
            try? context.save()
            return record
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func reset() {
        image = nil
        ocrText = ""
        productName = ""
        priceText = ""
        specText = ""
        linkText = ""
        sourceURL = nil
        pageCurrency = nil
        detectedLink = nil
        errorMessage = nil
    }
}
