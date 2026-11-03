import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// 二维码生成（用 CoreImage，不依赖第三方库）。
enum QRCodeImage {
    static func make(from content: String, size: CGFloat = 240) -> UIImage? {
        guard !content.isEmpty, let data = content.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
