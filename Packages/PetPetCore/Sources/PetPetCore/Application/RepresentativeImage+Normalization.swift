#if canImport(ImageIO)
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension RepresentativeImage {
    /// Decode a thumbnail directly, without expanding a full camera image in watch memory.
    public static func thumbnail(from data: Data) throws -> RepresentativeImage {
        guard !data.isEmpty, data.count <= 12_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                 kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 160] as CFDictionary) else { throw BackendError.invalidResponse }
        for quality in [0.85, 0.6, 0.35, 0.15] {
            let result = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else { throw BackendError.invalidResponse }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination), result.length <= maximumBytes { return try RepresentativeImage(data: result as Data) }
        }
        throw BackendError.transferTooLarge
    }
}
#endif
