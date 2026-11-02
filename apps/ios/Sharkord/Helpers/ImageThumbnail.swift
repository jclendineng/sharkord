import Foundation
import ImageIO
import QuickLookThumbnailing
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

    // a document's first page too, drawn by quick look, for files about to be shared
    static func make(ofAnyFile url: URL) async -> PlatformImage? {
        if let image = make(of: url) {
            return image
        }

        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 90, height: 90), scale: 2, representationTypes: .thumbnail)
        let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)

        return representation.map { PlatformImage(cgImage: $0.cgImage) }
    }
}
