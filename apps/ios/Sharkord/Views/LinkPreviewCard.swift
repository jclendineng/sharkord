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
                            // the picture fills a box the card's width, a wide one would
                            // otherwise ask for its own width and push the card off the screen
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                                .overlay {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                }
                                .clipShape(.rect(cornerRadius: 8, style: .continuous))
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

// a site's icon in a 64 point tile. a big one fills it, a tiny favicon sits in the middle at half
// the size with its pixels kept sharp, where stretching it to the whole tile would only blur it
struct SiteIcon<Fallback: View>: View {
    let url: URL
    let fallback: Fallback

    @State private var image: UIImage?
    @State private var hasFailed = false

    private static var tileSize: CGFloat { 64 }

    var body: some View {
        Group {
            if let image {
                if image.size.width * image.scale < Self.tileSize * 1.5 {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: Self.tileSize / 2, height: Self.tileSize / 2)
                        .frame(width: Self.tileSize, height: Self.tileSize)
                        .background(Theme.deepBackground, in: .rect(cornerRadius: 14, style: .continuous))
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Self.tileSize, height: Self.tileSize)
                        .clipShape(.rect(cornerRadius: 14, style: .continuous))
                }
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

    private func load() async {
        guard
            let (data, response) = try? await URLSession.shared.data(from: url),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let loaded = UIImage(data: data)
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
