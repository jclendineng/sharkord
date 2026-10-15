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
                        FaviconImage(url: faviconURL)
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
            .background(Theme.listBackground)
            .overlay(alignment: .leading) {
                Theme.divider
                    .frame(width: 4)
            }
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
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

// a page's icon, which takes no room when it will not load
private struct FaviconImage: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
            }
        }
    }
}
