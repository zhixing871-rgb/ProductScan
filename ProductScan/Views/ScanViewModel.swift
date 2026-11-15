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

/// 一张照片及其识别出的文字
struct ScanPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    var text: String = ""
}

@MainActor
@Observable
final class ScanViewModel {
    static let maxPhotos = 4

    var mode: InputMode = .photo
    var category: ProductCategory? = nil      // nil = AI 自动识别类别
    var photos: [ScanPhoto] = []
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
    var errorMessage: String?

    // 分析进度
    var stage: AnalysisStage?
    var analysisStartedAt: Date?
    var finishedRecord: ScanRecord?
    private var analysisTask: Task<Void, Never>?

    var isAnalyzing: Bool { analysisTask != nil }
    var image: UIImage? { photos.first?.image }
    var canAddPhoto: Bool { photos.count < Self.maxPhotos }

    var price: Double? {
        Double(priceText.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "¥", with: "").replacingOccurrences(of: "￥", with: "")
            .trimmingCharacters(in: .whitespaces))
    }

    var canAnalyze: Bool {
        !isAnalyzing && !isRecognizing &&
        (!photos.isEmpty ||
         !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
         !productName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: 照片

    /// 添加一张照片（最多 4 张），识别文字后合并到可编辑文本里
    func addPhoto(_ newImage: UIImage) async {
        guard canAddPhoto else {
            errorMessage = "最多 \(Self.maxPhotos) 张照片"
            return
        }
        if sourceURL != nil {          // 之前是网页截图，换成拍照内容
            sourceURL = nil
            photos = []
            ocrText = ""
        }
        var photo = ScanPhoto(image: newImage)
        isRecognizing = true
        errorMessage = nil
        defer { isRecognizing = false }
        async let codes = OCRService.detectCodes(in: newImage)
        do {
            photo.text = try await OCRService.recognizeText(in: newImage)
        } catch {
            errorMessage = error.localizedDescription
        }
        photos.append(photo)
        rebuildText()
        // 照片里有商品二维码时，提示可以改用链接抓取
        if let link = await codes.lazy.compactMap(LinkExtractor.firstURL(in:)).first {
            detectedLink = link
            errorMessage = nil
        }
    }

    func removePhoto(_ id: UUID) {
        photos.removeAll { $0.id == id }
        rebuildText()
        if photos.isEmpty { detectedLink = nil }
    }

    /// 多张照片的文字按顺序拼在一起
    private func rebuildText() {
        let parts = photos.map(\.text).filter { !$0.isEmpty }
        if parts.count <= 1 {
            ocrText = parts.first ?? ""
        } else {
            ocrText = parts.enumerated().map { "【第\($0.offset + 1)张照片】\n\($0.element)" }.joined(separator: "\n\n")
        }
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
        photos = []
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
        photos = capture.snapshot.map { [ScanPhoto(image: $0)] } ?? []
        pageCurrency = capture.currency
        if productName.trimmingCharacters(in: .whitespaces).isEmpty {
            productName = String(capture.title.prefix(60))
        }
        if priceText.trimmingCharacters(in: .whitespaces).isEmpty, let p = capture.price, Double(p) != nil {
            priceText = p
        }
    }

    // MARK: 分析

    /// 开始分析（可取消）；完成后 finishedRecord 被设置
    func startAnalysis(context: ModelContext) {
        guard analysisTask == nil else { return }
        errorMessage = nil
        analysisStartedAt = .now
        stage = .preparing

        let defaultCurrency = UserDefaults.standard.string(forKey: "currency") ?? SettingsView.defaultCurrency
        let currency = (sourceURL != nil ? pageCurrency : nil) ?? defaultCurrency
        let input = AnalysisService.Input(
            category: category,
            productName: productName.trimmingCharacters(in: .whitespaces),
            price: price,
            currency: currency,
            spec: specText.trimmingCharacters(in: .whitespaces),
            ocrText: ocrText.trimmingCharacters(in: .whitespacesAndNewlines),
            images: photos.compactMap { $0.image.thumbnailJPEG(maxDimension: 1568, quality: 0.7) },
            sourceURL: sourceURL,
            profile: UserProfile.load()
        )
        let thumbnail = image?.thumbnailJPEG()

        analysisTask = Task { [weak self] in
            defer {
                self?.analysisTask = nil
                self?.stage = nil
            }
            do {
                let record = try await AnalysisRunner.run(input, thumbnail: thumbnail, context: context) { stage in
                    self?.stage = stage
                }
                self?.finishedRecord = record
            } catch is CancellationError {
                self?.errorMessage = "已取消分析"
            } catch let error as URLError where error.code == .cancelled {
                self?.errorMessage = "已取消分析"
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
    }

    func reset() {
        photos = []
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

/// 执行一次分析并保存为历史记录（扫描页和「重新分析」共用）
@MainActor
enum AnalysisRunner {
    static func run(_ input: AnalysisService.Input,
                    thumbnail: Data?,
                    context: ModelContext,
                    onStage: @escaping @MainActor (AnalysisStage) -> Void) async throws -> ScanRecord {
        let settings = AISettings.current()
        let output = try await AnalysisService(settings: settings).analyze(input, onStage: onStage)
        let result = output.result

        // 用户手动选的类别优先，否则用 AI 识别出的类别
        let finalCategory = input.category ?? ProductCategory(loose: result.category) ?? .food
        let finalPrice = input.price ?? result.detectedPrice
        let finalCurrency = input.price == nil ? (result.detectedCurrency ?? input.currency) : input.currency
        let record = ScanRecord(
            category: finalCategory,
            productName: input.productName.isEmpty ? result.productName : input.productName,
            price: finalPrice,
            currency: finalCurrency,
            ocrText: input.ocrText,
            imageData: thumbnail,
            result: result,
            modelName: "\(settings.provider.shortTitle) · \(settings.model)",
            sourceURL: input.sourceURL
        )
        record.specText = input.spec.isEmpty ? nil : input.spec
        record.categoryWasAuto = input.category == nil
        if let usage = output.usage {
            record.inputTokens = usage.inputTokens
            record.outputTokens = usage.outputTokens
            record.costText = Pricing.costText(model: settings.model, usage: usage)
        }
        context.insert(record)
        try? context.save()
        return record
    }

    /// 用当前设置的模型重新分析一条历史记录
    static func reanalyze(_ record: ScanRecord, context: ModelContext,
                          onStage: @escaping @MainActor (AnalysisStage) -> Void) async throws -> ScanRecord {
        let input = AnalysisService.Input(
            category: record.categoryWasAuto == true ? nil : record.category,
            productName: record.productName,
            price: record.price,
            currency: record.currency,
            spec: record.specText ?? "",
            ocrText: record.ocrText,
            images: record.imageData.map { [$0] } ?? [],
            sourceURL: record.sourceURL,
            profile: UserProfile.load()
        )
        return try await run(input, thumbnail: record.imageData, context: context, onStage: onStage)
    }
}
