import AVKit
import Photos
import SwiftUI

// discord's media viewer, opened from a channel's media: one picture or video at a time, swiped
// through, with save, share, open in the browser and a jump to the message it came in, and the
// rest of the channel's media in a strip along the bottom
struct MediaViewer: View {
    let items: [MediaItem]
    // left out when it was opened from the message itself
    let onJump: ((MediaItem) -> Void)?

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var selection: String
    @State private var toast: Toast?

    // what a save came to, each one its own so a second save's message is not taken down by
    // the first one's timer
    private struct Toast: Equatable {
        let id = UUID()
        let message: String
    }

    init(items: [MediaItem], startingAt item: MediaItem, onJump: ((MediaItem) -> Void)? = nil) {
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

            // one picture has nothing to pick between
            if items.count > 1 {
                ThumbnailStrip(items: items, selection: $selection, url: url(for:))
            }
        }
        .background(Color.black.ignoresSafeArea())
        .overlay {
            if let toast {
                Text(toast.message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.75), in: .rect(cornerRadius: Radius.card))
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: toast)
        .task(id: toast) {
            guard toast != nil else {
                return
            }

            // cancelled when another message takes its place, which then gets its own time
            guard (try? await Task.sleep(for: .seconds(2.5))) != nil else {
                return
            }

            toast = nil
        }
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

                    if onJump != nil {
                        Button("Jump to Message", systemImage: "arrow.uturn.left.circle", action: jump)
                    }
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
        onJump?(current)
    }

    private func save() {
        guard let current, let url = url(for: current) else {
            return
        }

        Task {
            let outcome = await PhotoSaver.save(from: url)

            if outcome == .saved {
                Haptics.success()
            }

            toast = Toast(message: outcome.message)
        }
    }
}

// a picture from the server or a link into the photo library, asking only for the right to add.
// the media viewer's menu and a long press in the media grid both save through it
enum PhotoSaver {
    enum Outcome {
        case saved
        // the app may not add to the library, which only the system's settings can change
        case notAllowed
        case failed

        var message: String {
            switch self {
            case .saved:
                String(localized: "Saved to Photos")
            case .notAllowed:
                String(localized: "Sharkord can't add to your photos. Allow it in \(SystemSettings.name).")
            case .failed:
                String(localized: "This picture could not be saved to Photos.")
            }
        }
    }

    // nonisolated: Photos runs the change block on a queue of its own, and a block that took
    // the app's main actor isolation from here crashed the moment Photos called it
    nonisolated static func save(from url: URL) async -> Outcome {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else {
            return .notAllowed
        }

        guard let (data, _) = try? await URLSession.shared.data(from: url) else {
            return .failed
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }

            return .saved
        } catch {
            return .failed
        }
    }
}

// one picture, which zooms and pans, or a video that plays in place
private struct MediaPage: View {
    let item: MediaItem
    let url: URL?

    @State private var player: AVPlayer?

    var body: some View {
        if item.isVideo {
            VideoPlayer(player: player)
                .onAppear(perform: makePlayer)
                .onDisappear(perform: stop)
        } else {
            ZoomableView {
                AnimatedImage(url: url, maxPointSize: 1200, contentMode: .fit)
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
                withAnimation(Motion.standard) {
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
            .animation(Motion.quick, value: selection)
    }

    private func select(_ item: MediaItem) {
        withAnimation(Motion.standard) {
            selection = item.id
        }
    }
}
