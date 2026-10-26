import SwiftUI

extension EnvironmentValues {
    // closes the call the way it opened, the mac's zoom back into the voice bar. nil elsewhere,
    // where the system's own transition runs on dismiss
    @Entry var closeCall: (@MainActor () -> Void)?
}

// the mac's call growing out of the voice bar and shrinking back into it. an ipad app on a mac
// does not draw the system's zoom transition and slid the call off the bottom of the window, so
// the cover opens without an animation of its own and this draws the zoom instead: the call laid
// out at the window's size, clipped and scaled from the bar's frame to the whole window
struct MacCallZoom<Content: View>: View {
    // the voice bar, in the window's coordinates
    let source: CGRect
    @Binding var isPresented: Bool
    @ViewBuilder let content: Content

    @State private var isOpen = false

    private static var opening: Animation {
        .smooth(duration: 0.35)
    }

    private static var closing: Animation {
        .smooth(duration: 0.3)
    }

    var body: some View {
        GeometryReader { proxy in
            let window = proxy.frame(in: .global)
            let full = CGRect(origin: .zero, size: proxy.size)
            let bar = source.offsetBy(dx: -window.minX, dy: -window.minY)
            let frame = isOpen ? full : bar
            let scale = frame.width / max(full.width, 1)

            content
                #if os(macOS)
                .background(ArrowCursorArea())
                #endif
                .frame(width: full.width, height: full.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                .clipShape(.rect(cornerRadius: isOpen ? 0 : 20, style: .continuous))
                .offset(x: frame.minX, y: frame.minY)
                .opacity(isOpen ? 1 : 0)
        }
        // the native mac's call is drawn under the window's toolbar, which hid its header
        #if os(iOS)
        .ignoresSafeArea()
        #endif
        .presentationBackground(.clear)
        .environment(\.closeCall, close)
        .onAppear(perform: open)
    }

    private func open() {
        withAnimation(Self.opening) {
            isOpen = true
        }
    }

    private func close() {
        withAnimation(Self.closing) {
            isOpen = false
        } completion: {
            var transaction = Transaction()

            transaction.disablesAnimations = true

            withTransaction(transaction) {
                isPresented = false
            }
        }
    }
}

#if os(macOS)
// the native mac's call is drawn over the chat, and the message box's text view under it still
// set its i-beam over the call's controls. a cursor rect lost to the text view's own tracking, so
// the arrow is set again on every move over the call
private struct ArrowCursorArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ArrowCursorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class ArrowCursorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}
#endif
