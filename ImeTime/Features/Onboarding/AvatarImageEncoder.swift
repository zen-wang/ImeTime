import UIKit

/// 把使用者選的圖縮到最長邊 ≤ 512、JPEG ≤ 200 KB（avatars bucket 的 file_size_limit）。
enum AvatarImageEncoder {
    static let defaultMaxDimension: CGFloat = 512
    static let defaultMaxBytes = 200_000

    static func jpegData(
        from image: UIImage,
        maxDimension: CGFloat = defaultMaxDimension,
        maxBytes: Int = defaultMaxBytes
    ) -> Data? {
        let scaled = downscale(image, maxDimension: maxDimension)
        var quality: CGFloat = 0.9
        while quality >= 0.3 {
            if let data = scaled.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
            quality -= 0.1
        }
        return nil
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let ratio = maxDimension / longest
        let target = CGSize(
            width: (image.size.width * ratio).rounded(.down),
            height: (image.size.height * ratio).rounded(.down)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
