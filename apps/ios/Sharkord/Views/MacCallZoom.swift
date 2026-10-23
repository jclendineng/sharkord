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
                .frame(width: full.width, height: full.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                .clipShape(.rect(cornerRadius: isOpen ? 0 : 20, style: .continuous))
                .offset(x: frame.minX, y: frame.minY)
                .opacity(isOpen ? 1 : 0)
        }
        .ignoresSafeArea()
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
