import UIKit
import Vision

enum OCRError: LocalizedError {
    case invalidImage
    case noText

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "图片无法读取"
        case .noText: return "没有识别到文字，请靠近配料表、保持光线充足后重拍"
        }
    }
}

/// 使用 Apple Vision 在手机本地做文字识别（支持简体/繁体中文和英文，不上传图片）
enum OCRService {
    static func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw OCRError.invalidImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        let text: String = try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handler.perform([request])

            let observations = request.results ?? []
            // 按从上到下、从左到右排序（Vision 坐标原点在左下角）
            let sorted = observations.sorted { a, b in
                if abs(a.boundingBox.midY - b.boundingBox.midY) > 0.01 {
                    return a.boundingBox.midY > b.boundingBox.midY
                }
                return a.boundingBox.minX < b.boundingBox.minX
            }
            return sorted
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OCRError.noText }
        return trimmed
    }
}

extension OCRService {
    /// 识别图片里的二维码/条形码，返回内容（链接、口令或条码数字）
    static func detectCodes(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try? handler.perform([request])
            var seen = Set<String>()
            return (request.results ?? [])
                .compactMap { $0.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
        }.value
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

extension UIImage {
    /// 压缩成缩略图用于本地保存
    func thumbnailJPEG(maxDimension: CGFloat = 1024, quality: CGFloat = 0.6) -> Data? {
        let longest = max(size.width, size.height)
        let scale = min(1, maxDimension / longest)
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }
}
