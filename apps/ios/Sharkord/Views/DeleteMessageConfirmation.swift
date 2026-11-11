import SwiftUI

// discord's delete confirmation: the message itself in a card, then yes or no
struct DeleteMessageConfirmation: View {
    let message: Message
    let onConfirm: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // a long message is cut off here and fades out, a short one takes only its own height
    private static let previewLimit: CGFloat = 140

    @State private var isShown = false
    @State private var contentHeight: CGFloat = 0

    private var previewMask: LinearGradient {
        let fades = contentHeight > Self.previewLimit

        return LinearGradient(colors: [.black, .black, fades ? .clear : .black], startPoint: .top, endPoint: .bottom)
    }

    private var author: PublicUser? {
        message.userId.flatMap { session.usersById[$0] }
    }

    // the text as the chat shows it: a message that is only the link to a gif or a picture
    // shows the picture there, the link would only repeat it
    private var shownContent: String? {
        guard let content = message.content, !content.isEmpty, !message.isMediaLinkOnly else {
            return nil
        }

        return content
    }

    var body: some View {
        ZStack {
            Color.black.opacity(isShown ? 0.6 : 0)
                .ignoresSafeArea()
                .onTapGesture(perform: cancel)

            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text("Delete Message")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.header)

                    Text("Are you sure you want to delete this message?")
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                }

                HStack(alignment: .top, spacing: 12) {
                    AvatarView(user: author, size: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(author?.name ?? message.pluginId ?? "Unknown")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(session.nameColor(for: author))

                            Text(MessageDate.timestamp(message.createdDate))
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                        }

                        if let content = shownContent {
                            MessageContentView(html: content)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
                                .frame(height: min(contentHeight, Self.previewLimit), alignment: .top)
                                .clipped()
                                .mask(previewMask)
                        }

                        DeletePreviewItems(message: message)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .allowsHitTesting(false)

                VStack(spacing: 10) {
                    Button(action: confirm) {
                        Text("Yes")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Theme.blurple, in: .rect(cornerRadius: Radius.control))
                    }

                    Button(action: cancel) {
                        Text("No")
                            .font(.headline)
                            .foregroundStyle(Theme.header)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Theme.inputBackground, in: .rect(cornerRadius: Radius.control))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .background(Theme.listBackground, in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24).stroke(Theme.divider, lineWidth: 1)
            }
            .padding(.horizontal, 20)
            .scaleEffect(isShown || reduceMotion ? 1 : 0.92)
            .opacity(isShown ? 1 : 0)
        }
        .onAppear(perform: show)
    }

    private func show() {
        withAnimation(Motion.press) {
            isShown = true
        }
    }

    private func confirm() {
        onConfirm()
        close()
    }

    private func cancel() {
        close()
    }

    private func close() {
        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            dismiss()
        }
    }
}

// everything else the message holds, so it is recognisable before it goes: the sticker, the
// pictures and videos as a row of thumbnails, every other file by its name, and the poll
private struct DeletePreviewItems: View {
    let message: Message

    @Environment(SessionStore.self) private var session

    private static let thumbnailSize: CGFloat = 56
    private static let maxThumbnails = 4
    private static let maxFiles = 3

    // pictures and videos the chat draws as media, attached first and then shown from links
    private var visualURLs: [(id: String, url: URL, isVideo: Bool)] {
        var items: [(id: String, url: URL, isVideo: Bool)] = []

        if let address = session.address {
            for file in message.files where file.isImage || file.isVideo {
                items.append((id: "file-\(file.id)", url: address.fileURL(file), isVideo: file.isVideo))
            }
        }

        for media in message.mediaImages {
            if let url = URL(string: media.url) {
                items.append((id: media.url, url: url, isVideo: false))
            }
        }

        return items
    }

    private var otherFiles: [SharkordFile] {
        message.files.filter { !$0.isImage && !$0.isVideo }
    }

    var body: some View {
        let visuals = visualURLs
        let files = otherFiles

        if let sticker = message.sticker {
            AnimatedImage(url: session.address?.fileURL(sticker.file), maxPointSize: 80, contentMode: .fit)
                .frame(width: 80, height: 80)
        }

        if !visuals.isEmpty {
            HStack(spacing: 6) {
                ForEach(visuals.prefix(Self.maxThumbnails), id: \.id) { item in
                    thumbnail(item.url, isVideo: item.isVideo)
                }

                if visuals.count > Self.maxThumbnails {
                    Text("+\(visuals.count - Self.maxThumbnails)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
        }

        ForEach(files.prefix(Self.maxFiles)) { file in
            Label {
                Text(file.originalName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: file.symbol)
                    .foregroundStyle(Theme.accentText)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.text)
        }

        if files.count > Self.maxFiles {
            Text(files.count - Self.maxFiles == 1 ? "1 more file" : "\(files.count - Self.maxFiles) more files")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }

        if let poll = message.poll {
            Label {
                Text(poll.question)
                    .lineLimit(3)
            } icon: {
                Image(systemName: "text.alignleft")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.text)
        }
    }

    @ViewBuilder
    private func thumbnail(_ url: URL, isVideo: Bool) -> some View {
        Group {
            if isVideo {
                VideoThumbnail(url: url)
            } else {
                AnimatedImage(url: url, maxPointSize: Self.thumbnailSize, contentMode: .fill)
            }
        }
        .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
        .background(Theme.inputBackground)
        .clipShape(.rect(cornerRadius: Radius.media))
        .accessibilityHidden(true)
    }
}
