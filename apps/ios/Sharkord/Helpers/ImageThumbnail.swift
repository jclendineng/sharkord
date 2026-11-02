import Foundation
import ImageIO
import UniformTypeIdentifiers

// a picture about to be sent shows as itself, anything else by its name
enum ImageThumbnail {
    static func make(of url: URL) -> PlatformImage? {
        guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 180
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { PlatformImage(cgImage: $0) }
    }
}
