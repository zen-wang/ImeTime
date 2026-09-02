import Testing
import UIKit
@testable import ImeTime

@Suite struct AvatarImageEncoderTests {
    private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func downscalesLongestSideTo512AndStaysUnder200KB() throws {
        let data = try #require(AvatarImageEncoder.jpegData(from: solidImage(width: 2000, height: 1000)))
        #expect(data.count <= 200_000)
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size.width == 512)
        #expect(decoded.size.height == 256)
    }

    @Test func doesNotUpscaleSmallImages() throws {
        let data = try #require(AvatarImageEncoder.jpegData(from: solidImage(width: 100, height: 80)))
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size.width == 100)
        #expect(decoded.size.height == 80)
    }

    @Test func returnsNilWhenImpossibleToFitBudget() {
        // 1 byte 的預算不可能達成
        #expect(AvatarImageEncoder.jpegData(from: solidImage(width: 512, height: 512), maxBytes: 1) == nil)
    }

    /// 雜訊圖在低品質下明顯變小；預算設為「0.9 品質大小 − 1」可確定迫使迴圈至少遞減一次。
    @Test func lowersQualityUntilBudgetFits() throws {
        let image = noiseImage(side: 512)
        let atTopQuality = try #require(image.jpegData(compressionQuality: 0.9)).count
        let atBottomQuality = try #require(image.jpegData(compressionQuality: 0.3)).count
        try #require(atBottomQuality < atTopQuality)
        let budget = atTopQuality - 1
        let data = try #require(AvatarImageEncoder.jpegData(from: image, maxBytes: budget))
        #expect(data.count <= budget)
    }

    private func noiseImage(side: Int) -> UIImage {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cgImage = CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return UIImage(cgImage: cgImage)
    }
}
