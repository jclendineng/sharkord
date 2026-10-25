import SwiftUI

// a page's preview under the message that links it, as discord's embed: the site, the page's
// title in the link color and what it says about itself, its icon on the right when it has no
// picture and its picture underneath when it does, opening the page on a tap
struct LinkPreviewCard: View {
    let preview: MessageMetadata

    @Environment(\.openURL) private var openURL

    private var url: URL? {
        URL(string: preview.url)
    }

    private var imageURL: URL? {
        preview.previewImageURL
    }

    private var siteName: String? {
        guard let siteName = preview.siteName, !siteName.isEmpty, siteName != preview.title else {
            return nil
        }

        return siteName
    }

    private var title: String {
        if let title = preview.title, !title.isEmpty {
            return title
        }

        return url?.host() ?? preview.url
    }

    private var description: String? {
        guard let description = preview.description, !description.isEmpty, description != preview.title else {
            return nil
        }

        return description
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let siteName {
                            Text(siteName)
                                .font(.caption)
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                        }

                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.link)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)

                        if let description {
                            Text(description)
                                .font(.subheadline)
                                .foregroundStyle(Theme.text)
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if imageURL == nil, let faviconURL = preview.faviconURL {
                        SiteIcon(url: faviconURL)
                    }
                }

                if let imageURL {
                    // a picture that will not load takes no room, rather than a dark block
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            // the whole picture, discord's way, where filling the box cut a page's
                            // screenshot off at both sides. no taller than the placeholder, so the
                            // chat never grows once it loads, and the card's width stops a wide
                            // one asking for its own and pushing the card off screen
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(.rect(cornerRadius: 8, style: .continuous))
                                .frame(maxWidth: .infinity, maxHeight: 180, alignment: .leading)
                        case .failure:
                            EmptyView()
                        default:
                            Theme.deepBackground
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                                .clipShape(.rect(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: 440, alignment: .leading)
            .background(Theme.listBackground, in: .rect(cornerRadius: 14, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func open() {
        if let url {
            openURL(url)
        }
    }
}

// a site's icon filling a 64 point tile, a tiny favicon scaled up with its pixels kept sharp
struct SiteIcon<Fallback: View>: View {
    let url: URL
    let fallback: Fallback

    @State private var image: PlatformImage?
    @State private var hasFailed = false

    private static var tileSize: CGFloat { 64 }

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    // a tiny favicon grown to the tile keeps hard pixel edges rather than a smear
                    .interpolation(isTiny(image) ? .none : .high)
                    .scaledToFit()
                    .frame(width: Self.tileSize, height: Self.tileSize)
                    .clipShape(.rect(cornerRadius: 14, style: .continuous))
            } else if hasFailed {
                fallback
            } else {
                Color.clear
                    .frame(width: Self.tileSize, height: Self.tileSize)
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func isTiny(_ image: PlatformImage) -> Bool {
        image.size.width * image.scale < Self.tileSize
    }

    private func load() async {
        guard
            let (data, response) = try? await URLSession.shared.data(from: url),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let loaded = PlatformImage(data: data)
        else {
            hasFailed = true
            return
        }

        image = loaded
    }
}

extension SiteIcon where Fallback == EmptyView {
    init(url: URL) {
        self.init(url: url, fallback: EmptyView())
    }
}
