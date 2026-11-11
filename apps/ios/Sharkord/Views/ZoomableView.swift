import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// a picture in the media viewer that zooms about the point between two fingers, pans with
// momentum while zoomed and zooms in and out on a double tap. the system's own scroll view
// does all of it, so a pinch can be caught mid flight and the edges give like every other one.
// unzoomed it has nothing to scroll, so a swipe goes on to the pages and a pull down to the
// viewer's own dismissal
#if os(macOS)
struct ZoomableView<Content: View>: NSViewRepresentable {
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> ZoomScrollView {
        let scrollView = ZoomScrollView()
        let hosted = NSHostingView(rootView: AnyView(content))

        // the scroll view sizes it, at its content's own size a picture not yet loaded was a point
        hosted.sizingOptions = []
        scrollView.documentView = hosted
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = ZoomScale.minimum
        scrollView.maxMagnification = ZoomScale.maximum

        let doubleClick = NSClickGestureRecognizer(target: scrollView, action: #selector(ZoomScrollView.toggleZoom))

        doubleClick.numberOfClicksRequired = 2
        scrollView.addGestureRecognizer(doubleClick)

        return scrollView
    }

    func updateNSView(_ scrollView: ZoomScrollView, context: Context) {
        if let hosted = scrollView.documentView as? NSHostingView<AnyView> {
            hosted.rootView = AnyView(content)
        }
    }
}

final class ZoomScrollView: NSScrollView {
    private var laidOutSize = CGSize.zero

    override func layout() {
        super.layout()

        guard frame.size != laidOutSize else {
            return
        }

        // a new size starts over unzoomed, the picture filling the view again
        laidOutSize = frame.size
        magnification = ZoomScale.minimum
        documentView?.setFrameSize(contentSize)
    }

    @objc func toggleZoom(_ recognizer: NSClickGestureRecognizer) {
        guard let documentView else {
            return
        }

        let point = recognizer.location(in: documentView)
        let isZoomed = magnification > ZoomScale.minimum

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            animator().setMagnification(isZoomed ? ZoomScale.minimum : ZoomScale.doubleTap, centeredAt: point)
        }
    }
}
#else
struct ZoomableView<Content: View>: UIViewRepresentable {
    @ViewBuilder let content: Content

    func makeCoordinator() -> ZoomCoordinator {
        ZoomCoordinator(content: AnyView(content))
    }

    func makeUIView(context: Context) -> ZoomScrollView {
        let coordinator = context.coordinator
        let scrollView = ZoomScrollView(hosted: coordinator.host.view)

        scrollView.delegate = coordinator
        scrollView.minimumZoomScale = ZoomScale.minimum
        scrollView.maximumZoomScale = ZoomScale.maximum
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear

        let doubleTap = UITapGestureRecognizer(target: coordinator, action: #selector(ZoomCoordinator.toggleZoom))

        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: ZoomScrollView, context: Context) {
        context.coordinator.host.rootView = AnyView(content)
    }
}

final class ZoomCoordinator: NSObject, UIScrollViewDelegate {
    let host: UIHostingController<AnyView>

    init(content: AnyView) {
        host = UIHostingController(rootView: content)
        // the picture is centered in the view it is given, not in what is left of it inside
        // the safe area, which moved it as the bars came and went
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        host.view
    }

    @objc func toggleZoom(_ recognizer: UITapGestureRecognizer) {
        guard let scrollView = recognizer.view as? UIScrollView else {
            return
        }

        guard scrollView.zoomScale == scrollView.minimumZoomScale else {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)

            return
        }

        // in on the point tapped, which stays under the finger
        let point = recognizer.location(in: host.view)
        let size = CGSize(
            width: scrollView.bounds.width / ZoomScale.doubleTap,
            height: scrollView.bounds.height / ZoomScale.doubleTap
        )
        let target = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)

        scrollView.zoom(to: target, animated: true)
    }
}

final class ZoomScrollView: UIScrollView {
    private let hosted: UIView
    private var laidOutSize = CGSize.zero

    init(hosted: UIView) {
        self.hosted = hosted

        super.init(frame: .zero)

        addSubview(hosted)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard bounds.size != laidOutSize else {
            return
        }

        // a new size, a rotation among them, starts over unzoomed with the picture filling
        // the view again
        laidOutSize = bounds.size
        zoomScale = minimumZoomScale
        hosted.frame = CGRect(origin: .zero, size: bounds.size)
        contentSize = bounds.size
    }
}
#endif

private enum ZoomScale {
    static var minimum: CGFloat { 1 }
    static var maximum: CGFloat { 5 }
    static var doubleTap: CGFloat { 2.5 }
}
