import AVFoundation
import SwiftUI

struct AttachmentView: View {
    let file: SharkordFile

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.isShowingMessageActions) private var isShowingMessageActions

    @State private var isViewerPresented = false

    var body: some View {
        if let address = session.address {
            let url = address.fileURL(file)

            if file.isImage {
                Button(action: openViewer) {
                    AttachmentImage(file: file, url: url)
                        .frame(maxWidth: 300, maxHeight: 300, alignment: .leading)
                        .clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                // handed over by hand: on a mac a sheet's background is worked out before it inherits
                // anything, so a sheet reading a store it was not given crashed on opening
                .fullScreenCover(isPresented: $isViewerPresented) {
                    ImageViewer(url: url)
                        .environment(session)
                        .environment(servers)
                }
            } else if file.isAudio {
                AudioPlayerCard(file: file, url: url)
            } else {
                FileCard(file: file, url: url)
            }
        }
    }

    private func openViewer() {
        guard !isShowingMessageActions else {
            return
        }

        isViewerPresented = true
    }
}

// a picture in a message, from memory when it has been shown before: a row drawn again then
// has its size at once, where a fresh download first showed a placeholder of another size and
// made the conversation jump
private struct AttachmentImage: View {
    let file: SharkordFile
    let url: URL

    @State private var image: UIImage?

    var body: some View {
        if let image = image ?? FileImageCache.cached(file, at: url) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Theme.listBackground
                .frame(width: 240, height: 160)
                .task(id: file.id) {
                    image = await FileImageCache.load(file, from: url)
                }
        }
    }
}

// opens on the phone in quick look, not in a web page. a document small enough to fetch shows
// its first page above the name, the way quick look draws it in files
private struct FileCard: View {
    let file: SharkordFile
    let url: URL

    @Environment(SessionStore.self) private var session

    @State private var thumbnail: UIImage?

    var body: some View {
        OpenFileButton(file: file) { isLoading in
            VStack(alignment: .leading, spacing: 0) {
                if let thumbnail = thumbnail ?? FileThumbnails.cached(for: file, from: url) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 200)
                        .background(Theme.deepBackground)
                }

                HStack(spacing: 10) {
                    Image(systemName: file.symbol)
                        .font(.title)
                        .foregroundStyle(Theme.blurple)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.originalName)
                            .foregroundStyle(Theme.link)
                            .lineLimit(1)

                        Text(file.size.formatted(.byteCount(style: .file)))
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }

                    Spacer(minLength: 0)

                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(12)
            }
            .frame(maxWidth: 320)
            .background(Theme.listBackground)
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.deepBackground)
            }
            .contentShape(.rect)
        }
        .task(id: file.id) {
            thumbnail = await FileThumbnails.thumbnail(for: file, from: url)
        }
    }
}

struct ImageViewer: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in scale = max(1, value.magnification) }
                            .onEnded { _ in withAnimation { scale = 1 } }
                    )
            } placeholder: {
                ProgressView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                }

                Button("Close", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .padding()
        }
    }

    private func close() {
        dismiss()
    }
}

// discord's voice message: a round play button, a waveform that fills as it plays and the
// length, played here rather than downloaded
private struct AudioPlayerCard: View {
    private static let barCount = 28

    let file: SharkordFile
    let url: URL

    @State private var playback = AudioPlayback.shared
    @State private var duration: Double?

    private var isCurrent: Bool {
        playback.currentFileId == file.id
    }

    private var isPlaying: Bool {
        isCurrent && playback.isPlaying
    }

    // the same file always draws the same shape
    private var bars: [CGFloat] {
        var seed = UInt64(truncatingIfNeeded: file.id) &* 2_654_435_761 &+ 1

        return (0..<Self.barCount).map { _ in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407

            return 0.25 + CGFloat(seed >> 33) / CGFloat(UInt32.max) * 0.75
        }
    }

    private var timeText: String {
        let total = duration ?? 0
        let shown = isCurrent ? total * playback.progress : total
        let seconds = Int(shown.rounded())

        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill", action: toggle)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.blurple, in: .circle)

            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, height in
                    let played = isCurrent && Double(index) / Double(Self.barCount) < playback.progress

                    Capsule()
                        .fill(played ? Theme.header : Theme.muted.opacity(0.6))
                        .frame(width: 3, height: 22 * height)
                }
            }
            .frame(height: 24)

            Text(timeText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.muted)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(Theme.listBackground, in: .capsule)
        .task {
            if let seconds = try? await AVURLAsset(url: url).load(.duration).seconds, seconds.isFinite {
                duration = seconds
            }
        }
    }

    private func toggle() {
        playback.toggle(fileId: file.id, url: url)
    }
}

