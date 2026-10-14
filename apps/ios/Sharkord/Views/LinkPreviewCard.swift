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
        preview.images?.first.flatMap(URL.init(string:))
    }

    private var source: String {
        if let siteName = preview.siteName, !siteName.isEmpty {
            return siteName
        }

        return url?.host() ?? preview.url
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                if let imageURL {
                    AsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Theme.deepBackground
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipped()
                }

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
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
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
