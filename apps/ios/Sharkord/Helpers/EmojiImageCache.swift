import Observation
import UIKit

// custom emoji render inline inside Text, which needs a ready UIImage rather than an AsyncImage
@Observable
final class EmojiImageCache {
    static let shared = EmojiImageCache()

    // the point size is part of the key: a 14pt render reused at 44pt in the picker was blurry,
    // and a 44pt one reused in a message was needlessly heavy
    private struct Key: Hashable {
        let url: URL
        let pointSize: CGFloat
    }

    private var images: [Key: UIImage] = [:]

    @ObservationIgnored private var requested: Set<Key> = []

    func image(for url: URL, pointSize: CGFloat) -> UIImage? {
        let key = Key(url: url, pointSize: pointSize)

        if let image = images[key] {
            return image
        }

        if requested.insert(key).inserted {
            // deferred so the state change never happens during the view update that asked
            Task {
                await load(key)
            }
        }

        return nil
    }

    private func load(_ key: Key) async {
        guard
            let (data, _) = try? await URLSession.shared.data(from: key.url),
            let image = UIImage(data: data)
        else {
            // a failed fetch used to stay requested forever, so it was never tried again
            requested.remove(key)

            return
        }

        let scale = key.pointSize / max(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        images[key] = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
