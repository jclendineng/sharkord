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
