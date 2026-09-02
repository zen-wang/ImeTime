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
}
