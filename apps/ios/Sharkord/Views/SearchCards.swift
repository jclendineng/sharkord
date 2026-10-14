import SwiftUI

// discord's files and links tabs: two cards across, each a preview over what it is, who posted
// it and in which channel, with a menu to jump to the message
struct SearchCardGrid<Content: View>: View {
    @ViewBuilder let content: Content

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            content
        }
        .padding(.horizontal, 14)
    }
}

// a file: its picture, a still of a video or a document's first page, opening in quick look
struct FileCardTile: View {
    let file: SearchFile
    let onJump: () -> Void

    @Environment(SessionStore.self) private var session

    @State private var thumbnail: UIImage?

    var body: some View {
        OpenFileButton(file: file.file) { isLoading in
            SearchCard(userId: file.userId, channelName: file.channelName) {
                preview
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                    }
            } details: {
                Text(file.file.originalName)
                    .font(.headline)
                    .foregroundStyle(Theme.header)
                    .lineLimit(1)

                Text(file.file.size.formatted(.byteCount(style: .file)))
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
            }
        }
        .contextMenu {
            CardActions(onJump: onJump, link: nil)
        }
        .task(id: file.id) {
            await loadThumbnail()
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let address = session.address, file.file.isImage {
            CachedFileImage(file: file.file, url: address.fileURL(file.file)) {
                Theme.deepBackground
            }
        } else if let address = session.address, file.file.isVideo {
            VideoThumbnail(url: address.fileURL(file.file))
        } else if let thumbnail {
            // the whole page, a document cropped to its corner is mostly empty margin
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFit()
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .padding(12)
        } else {
            Image(systemName: file.file.symbol)
                .font(.system(size: 36))
                .foregroundStyle(Theme.blurple)
        }
    }

    // a document's first page, pictures and videos draw themselves
    private func loadThumbnail() async {
        guard let address = session.address, !file.file.isImage, !file.file.isVideo else {
            return
        }

        thumbnail = await FileThumbnails.thumbnail(for: file.file, from: address.fileURL(file.file))
    }
}

// a link: the page's picture once the server has fetched its preview, its title and site
struct LinkCardTile: View {
    let url: URL
    let preview: MessageMetadata?
    let userId: Int?
    let channelName: String
    let onJump: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: open) {
            SearchCard(userId: userId, channelName: channelName) {
                if let image = preview?.previewImageURL {
                    AsyncImage(url: image) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            linkIcon
                        }
                    }
                } else {
                    linkIcon
                }
            } details: {
                Text(preview?.title ?? url.host() ?? url.absoluteString)
                    .font(.headline)
                    .foregroundStyle(Theme.header)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(url.host() ?? url.absoluteString)
                    .font(.subheadline)
                    .foregroundStyle(Theme.link)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            CardActions(onJump: onJump, link: url)
        }
    }

    private var linkIcon: some View {
        Image(systemName: "link")
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(Theme.muted)
    }

    private func open() {
        openURL(url)
    }
}

// a long press on a card, the way ios lifts it with its options under it. a tap still opens it
private struct CardActions: View {
    let onJump: () -> Void
    let link: URL?

    var body: some View {
        Button("Jump to Message", systemImage: "arrow.uturn.left.circle", action: onJump)

        if let link {
            Button("Copy Link", systemImage: "doc.on.doc") {
                UIPasteboard.general.url = link
            }
        }
    }
}

// the card both share: the preview filling its top, then the details, the poster and the channel
private struct SearchCard<Preview: View, Details: View>: View {
    let userId: Int?
    let channelName: String
    @ViewBuilder let preview: Preview
    @ViewBuilder let details: Details

    @Environment(SessionStore.self) private var session

    private var author: PublicUser? {
        userId.flatMap { session.usersById[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 130)
                .overlay {
                    preview
                }
                .background(Theme.deepBackground)
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                details

                if let author {
                    HStack(spacing: 6) {
                        AvatarView(user: author, size: 18)

                        Text(author.name)
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                    .padding(.top, 4)
                }

                Label {
                    Text(channelName)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "number")
                }
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.listBackground)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.divider, lineWidth: 1)
        }
        .contentShape(.rect)
    }
}
