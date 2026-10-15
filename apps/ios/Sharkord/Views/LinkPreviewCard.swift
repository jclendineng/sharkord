import SwiftUI

// a page's preview under the message that links it, like imessage's: the page's picture, its
// title and where it is from, opening the page on a tap
struct LinkPreviewCard: View {
    let preview: MessageMetadata

    @Environment(\.openURL) private var openURL

    private var url: URL? {
        URL(string: preview.url)
    }

    private var imageURL: URL? {
        preview.previewImageURL
    }

    // the address, as imessage shows it, a site's own name when it gives one
    private var source: String {
        if let siteName = preview.siteName, !siteName.isEmpty, siteName != preview.title {
            return siteName
        }

        return url?.host() ?? preview.url
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                if let imageURL {
                    // a picture that will not load takes no room, rather than a dark block
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 160)
                                .clipped()
                        case .failure:
                            EmptyView()
                        default:
                            Theme.deepBackground
                                .frame(height: 160)
                        }
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let title = preview.title, !title.isEmpty {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.header)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }

                        Text(source)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // no picture of its own, so its icon on the right, as imessage shows it
                    if imageURL == nil, let faviconURL = preview.faviconURL {
                        FaviconImage(url: faviconURL)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: 280)
            .background(Theme.listBackground)
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
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
                    .frame(width: 40, height: 40)
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))
            }
        }
    }
}
