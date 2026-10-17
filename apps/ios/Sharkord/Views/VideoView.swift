import SwiftUI
import WebRTC

// a webrtc track on screen. the renderer is attached and detached by hand, a track left
// attached to a dismantled view keeps decoding frames for nothing
struct VideoView: UIViewRepresentable {
    let track: VideoTrackBox
    var contentMode: UIView.ContentMode = .scaleAspectFill
    var isMirrored = false

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()

        view.videoContentMode = contentMode
        view.transform = isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        track.track.add(view)
        context.coordinator.track = track.track

        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        view.videoContentMode = contentMode
        view.transform = isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity

        guard context.coordinator.track !== track.track else {
            return
        }

        context.coordinator.track?.remove(view)
        track.track.add(view)
        context.coordinator.track = track.track
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.track?.remove(view)
        coordinator.track = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var track: RTCVideoTrack?
    }
}

extension View {
    // tells the session how big a stream is drawn, so it can ask for no more than that
    func reportsVideoSize(of key: VoiceStreamKey) -> some View {
        modifier(VideoSizeReporter(key: key))
    }
}

private struct VideoSizeReporter: ViewModifier {
    let key: VoiceStreamKey

    @Environment(SessionStore.self) private var session
    @Environment(\.displayScale) private var displayScale

    @State private var tile = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                session.setVideoTileHeight(height * displayScale, tile: tile, for: key)
            }
            .onDisappear(perform: forget)
    }

    private func forget() {
        session.setVideoTileHeight(nil, tile: tile, for: key)
    }
}
