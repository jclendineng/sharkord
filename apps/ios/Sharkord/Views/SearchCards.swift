import SwiftUI

// discord's files and links tabs: two cards across, each a preview over what it is, who posted
// it and in which channel, with a menu to jump to the message
struct SearchCardGrid<Content: View>: View {
    @ViewBuilder let content: Content

    // an ipad's cards stay two across as discord's do, just bigger, with more room around them
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var spacing: CGFloat {
        sizeClass == .regular ? 18 : 12
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 2), spacing: spacing) {
            content
        }
        .padding(.horizontal, sizeClass == .regular ? 28 : 14)
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
            SearchCard(userId: file.userId, channelId: file.channelId, channelName: file.channelName, onJump: onJump) {
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
            // the page fills the card from its top, as discord shows one
            Color.clear
                .overlay(alignment: .top) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
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
    let channelId: Int
    let channelName: String
    let onJump: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: open) {
            SearchCard(userId: userId, channelId: channelId, channelName: channelName, onJump: onJump) {
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
                } else if let favicon = preview?.faviconURL {
                    SiteIcon(url: favicon, fallback: linkIcon)
                } else {
                    linkIcon
                }
            } details: {
                // discord's: the page's name, or the link itself when it has none, then the link
                Text(preview?.title ?? url.absoluteString)
                    .font(.headline)
                    .foregroundStyle(Theme.header)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)

                Text(url.absoluteString)
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

// a pinned message: its picture, gif, sticker or link preview, or its words when it has none,
// jumping to it on a tap and unpinned from a long press
struct PinCardTile: View {
    let message: Message
    let onOpen: () -> Void
    let onUnpinned: () -> Void

    @Environment(SessionStore.self) private var session

    private var text: String {
        HTMLText.plainText(from: message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var channelName: String {
        session.channel(message.channelId)?.name ?? ""
    }

    private var image: SharkordFile? {
        message.files.first { $0.isImage }
    }

    var body: some View {
        Button(action: onOpen) {
            SearchCard(userId: message.userId, channelId: message.channelId, channelName: channelName) {
                preview
            } details: {
                if !text.isEmpty && !message.isMediaLinkOnly {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.header)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Text(MessageDate.timestamp(message.createdDate))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Jump to Message", systemImage: "arrow.uturn.left.circle", action: onOpen)

            if !text.isEmpty {
                Button("Copy Text", systemImage: "doc.on.doc", action: copyText)
            }

            if session.canPin(in: message.channelId) {
                Button("Unpin Message", systemImage: "pin.slash", role: .destructive, action: unpin)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image, let address = session.address {
            CachedFileImage(file: image, url: address.fileURL(image)) {
                Theme.deepBackground
            }
        } else if let media = message.mediaImages.first {
            AnimatedImage(url: URL(string: media.url), maxPointSize: 300)
        } else if let sticker = message.sticker {
            AnimatedImage(url: session.address?.fileURL(sticker.file), maxPointSize: 160, contentMode: .scaleAspectFit)
                .padding(12)
        } else if let favicon = message.linkPreviews.first.flatMap({ $0.previewImageURL == nil ? $0.faviconURL : nil }) {
            SiteIcon(url: favicon, fallback: Theme.deepBackground)
        } else if let linkImage = message.linkPreviews.first?.previewImageURL {
            AsyncImage(url: linkImage) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Theme.deepBackground
                }
            }
        } else {
            // words only: the pin and the start of what was said, like a quote
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "pin.fill")
                    .foregroundStyle(Theme.muted)

                Text(text.isEmpty ? "Attachment" : text)
                    .font(.footnote)
                    .foregroundStyle(Theme.text)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func copyText() {
        UIPasteboard.general.string = text
    }

    private func unpin() {
        Task {
            do {
                try await session.perform("messages.togglePin", ["messageId": message.id])
                onUnpinned()
            } catch {
                session.showError(error)
            }
        }
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
    let channelId: Int
    let channelName: String
    // the poster and the channel go to the message, the rest of the card opens what it shows
    var onJump: (() -> Void)?
    @ViewBuilder let preview: Preview
    @ViewBuilder let details: Details

    @Environment(SessionStore.self) private var session

    private var author: PublicUser? {
        userId.flatMap { session.usersById[$0] }
    }

    // discord's: a channel's #, the person's avatar for a direct message, a group's picture
    @ViewBuilder
    private var placeIcon: some View {
        if !session.isDirectMessage(channelId) {
            Image(systemName: "number")
        } else if session.group(for: channelId) != nil {
            GroupAvatar(size: 18)
        } else {
            AvatarView(user: session.directMessagePartner(for: channelId), size: 18)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // discord's: the picture takes the card's width, a little shorter than it is wide
            Color.clear
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay {
                    preview
                }
                .background(Theme.deepBackground)
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                details

                if let onJump {
                    Button(action: onJump) {
                        source
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to Message")
                } else {
                    source
                }
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

    // who posted it and where
    private var source: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                    Text(session.placeName(channelId: channelId, channelName: channelName))
                        .lineLimit(1)
                } icon: {
                    placeIcon
                }
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
    }
}

