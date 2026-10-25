import AVKit
import Photos
import SwiftUI

// discord's media viewer, opened from a channel's media: one picture or video at a time, swiped
// through, with save, share, open in the browser and a jump to the message it came in, and the
// rest of the channel's media in a strip along the bottom
struct MediaViewer: View {
    let items: [MediaItem]
    let onJump: (MediaItem) -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var selection: String
    @State private var savedMessage: String?

    init(items: [MediaItem], startingAt item: MediaItem, onJump: @escaping (MediaItem) -> Void) {
        self.items = items
        self.onJump = onJump
        _selection = State(initialValue: item.id)
    }

    private var current: MediaItem? {
        items.first { $0.id == selection }
    }

    var body: some View {
        // stacked, not layered: pages running under the bar let their scroll view take the first
        // tap meant for the close button
        VStack(spacing: 0) {
            topBar

            PagedTabs(selection: $selection, items: items, value: \.id) { item in
                MediaPage(item: item, url: url(for: item))
            }

            ThumbnailStrip(items: items, selection: $selection, url: url(for:))
        }
        .background(Color.black.ignoresSafeArea())
        .overlay {
            if let savedMessage {
                Text(savedMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.75), in: .capsule)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: savedMessage)
    }

    private var topBar: some View {
        HStack {
            Button(action: close) {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }

            Spacer()

            if let current {
                Menu {
                    if !current.isVideo {
                        Button("Save", systemImage: "square.and.arrow.down", action: save)
                    }

                    if let url = url(for: current) {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button("Open in Browser", systemImage: "arrow.up.forward.square") {
                            openURL(url)
                        }
                    }

                    Button("Jump to Message", systemImage: "arrow.uturn.left.circle", action: jump)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func url(for item: MediaItem) -> URL? {
        switch item {
        case .file(let file):
            return session.address?.fileURL(file.file)
        case .link(let url, _, _, _):
            return url
        }
    }

    private func close() {
        dismiss()
    }

    private func jump() {
        guard let current else {
            return
        }

        dismiss()
        onJump(current)
    }

    private func save() {
        guard let current, let url = url(for: current) else {
            return
        }

        Task {
            show(await PhotoSaver.save(from: url) ? "Saved to Photos" : "Couldn't save")
        }
    }

    private func show(_ message: String) {
        savedMessage = message

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            savedMessage = nil
        }
    }
}

// a picture from the server or a link into the photo library, asking only for the right to add.
// the media viewer's menu and a long press in the media grid both save through it
enum PhotoSaver {
    static func save(from url: URL) async -> Bool {
        guard
            await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized,
            let (data, _) = try? await URLSession.shared.data(from: url)
        else {
            return false
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }

            return true
        } catch {
            return false
        }
    }
}

// one picture, which pinches to zoom, or a video that plays in place
private struct MediaPage: View {
    let item: MediaItem
    let url: URL?

    @State private var scale: CGFloat = 1
    @State private var player: AVPlayer?

    var body: some View {
        if item.isVideo {
            VideoPlayer(player: player)
                .onAppear(perform: makePlayer)
                .onDisappear(perform: stop)
        } else {
            AnimatedImage(url: url, maxPointSize: 1200, contentMode: .fit)
                .scaleEffect(scale)
                .gesture(zoom)
        }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = max(1, value.magnification)
            }
            .onEnded { _ in
                withAnimation(.smooth(duration: 0.25)) {
                    scale = 1
                }
            }
    }

    private func makePlayer() {
        guard player == nil, let url else {
            return
        }

        player = AVPlayer(url: url)
    }

    private func stop() {
        player?.pause()
    }
}

// the channel's media along the bottom, the one on screen outlined
private struct ThumbnailStrip: View {
    let items: [MediaItem]
    @Binding var selection: String
    let url: (MediaItem) -> URL?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 4) {
                    ForEach(items) { item in
                        Button {
                            select(item)
                        } label: {
                            thumbnail(item)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.never)
            .frame(height: 64)
            .padding(.vertical, 8)
            .background(.black)
            .onAppear {
                proxy.scrollTo(selection, anchor: .center)
            }
            .onChange(of: selection) { _, id in
                withAnimation(.smooth(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func thumbnail(_ item: MediaItem) -> some View {
        Color.clear
            .frame(width: item.id == selection ? 64 : 44, height: 64)
            .overlay {
                if item.isVideo {
                    Image(systemName: "play.fill")
                        .foregroundStyle(.white)
                } else {
                    AnimatedImage(url: url(item), maxPointSize: 120)
                }
            }
            .background(Theme.listBackground)
            .clipShape(.rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white, lineWidth: item.id == selection ? 2 : 0)
            }
            .animation(.smooth(duration: 0.2), value: selection)
    }

    private func select(_ item: MediaItem) {
        withAnimation(.smooth(duration: 0.25)) {
            selection = item.id
        }
    }
}
