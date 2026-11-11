import AVFoundation
import os
import SwiftUI
import WebRTC

// a webrtc track on screen. the renderer is attached and detached by hand, a track left
// attached to a dismantled view keeps decoding frames for nothing
#if os(macOS)
// a mac draws through a sample buffer layer, which fits, fills and mirrors, see SampleBufferVideoView
struct VideoView: NSViewRepresentable {
    let track: VideoTrackBox
    var contentMode: ContentMode = .fill
    var isMirrored = false
    // the picture's size once turned upright, as it arrives and whenever it changes
    var onVideoSize: ((CGSize) -> Void)?

    private var videoGravity: AVLayerVideoGravity {
        contentMode == .fit ? .resizeAspect : .resizeAspectFill
    }

    func makeNSView(context: Context) -> SampleBufferVideoView {
        let view = SampleBufferVideoView()

        view.videoGravity = videoGravity
        view.isMirrored = isMirrored
        view.onAspectChange = onVideoSize
        track.track.add(view.renderer)
        context.coordinator.track = track.track

        return view
    }

    func updateNSView(_ view: SampleBufferVideoView, context: Context) {
        view.videoGravity = videoGravity
        view.isMirrored = isMirrored
        view.onAspectChange = onVideoSize

        guard context.coordinator.track !== track.track else {
            return
        }

        context.coordinator.track?.remove(view.renderer)
        track.track.add(view.renderer)
        context.coordinator.track = track.track
    }

    static func dismantleNSView(_ view: SampleBufferVideoView, coordinator: Coordinator) {
        coordinator.track?.remove(view.renderer)
        coordinator.track = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var track: RTCVideoTrack?
    }
}
#else
struct VideoView: UIViewRepresentable {
    let track: VideoTrackBox
    var contentMode: ContentMode = .fill
    var isMirrored = false
    // drawn at this turn rather than the one each frame carries, which only changes how it is
    // drawn here, not what is sent. read once, when the view is made
    var drawnRotation: RTCVideoRotation?
    // the picture's size once turned upright, as it arrives and whenever it changes
    var onVideoSize: ((CGSize) -> Void)?

    private var videoContentMode: UIView.ContentMode {
        contentMode == .fit ? .scaleAspectFit : .scaleAspectFill
    }

    private var mirror: CGAffineTransform {
        isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
    }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()

        view.videoContentMode = videoContentMode
        view.transform = mirror
        view.delegate = context.coordinator
        context.coordinator.onVideoSize = onVideoSize
        context.coordinator.sink = drawnRotation.map { RetaggingRenderer(view: view, rotation: $0) } ?? view
        track.track.add(context.coordinator.sink!)
        context.coordinator.track = track.track

        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        view.videoContentMode = videoContentMode
        view.transform = mirror
        context.coordinator.onVideoSize = onVideoSize

        guard context.coordinator.track !== track.track, let sink = context.coordinator.sink else {
            return
        }

        context.coordinator.track?.remove(sink)
        track.track.add(sink)
        context.coordinator.track = track.track
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
        if let sink = coordinator.sink {
            coordinator.track?.remove(sink)
        }

        coordinator.track = nil
        coordinator.sink = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // the view tells its delegate the frame's size, already turned by the frame's rotation
    final class Coordinator: NSObject, RTCVideoViewDelegate {
        var track: RTCVideoTrack?
        // what the track draws into: the view, or the view behind a retagging renderer
        var sink: (any RTCVideoRenderer)?
        var onVideoSize: ((CGSize) -> Void)?

        func videoView(_ videoView: any RTCVideoRenderer, didChangeVideoSize size: CGSize) {
            onVideoSize?(size)
        }
    }
}

// hands each frame on with another turn, so it is drawn that way here. a phone's own preview
// takes its frames as the screen is held, the way they look when the phone is upright, while the
// same frames go out upright to gravity
nonisolated private final class RetaggingRenderer: NSObject, RTCVideoRenderer, @unchecked Sendable {
    private let view: any RTCVideoRenderer
    private let rotation: RTCVideoRotation
    private let lastSize = OSAllocatedUnfairLock(initialState: CGSize.zero)

    init(view: any RTCVideoRenderer, rotation: RTCVideoRotation) {
        self.view = view
        self.rotation = rotation
    }

    // the size the track gives follows the frames' own turn, so it is worked out from the frame
    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else {
            view.renderFrame(nil)
            return
        }

        let isSideways = rotation == ._90 || rotation == ._270
        let width = CGFloat(isSideways ? frame.buffer.height : frame.buffer.width)
        let height = CGFloat(isSideways ? frame.buffer.width : frame.buffer.height)
        let size = CGSize(width: width, height: height)

        let hasChanged = lastSize.withLock { last in
            guard last != size else {
                return false
            }

            last = size
            return true
        }

        if hasChanged {
            view.setSize(size)
        }

        view.renderFrame(RTCVideoFrame(buffer: frame.buffer, rotation: rotation, timeStampNs: frame.timeStampNs))
    }
}
#endif

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
