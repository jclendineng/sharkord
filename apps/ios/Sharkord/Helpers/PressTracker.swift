import SwiftUI

// whether a finger rests on a view, from uikit's own recogniser alongside every other one. a
// swiftui gesture tracking it shared the touch with the list, and a menu opening part way through
// a press left it holding on, the messages no longer scrolling. this one never claims the touch
// and lets go as soon as the finger moves, so a scroll always wins
#if os(iOS)
struct PressTracker: UIGestureRecognizerRepresentable {
    @Binding var isPressed: Bool

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()

        recognizer.minimumPressDuration = 0.05
        recognizer.allowableMovement = 10
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator

        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began:
            isPressed = true
        case .ended, .cancelled, .failed:
            isPressed = false
        default:
            break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif

extension View {
    // lit the moment a finger lands, where a button in a scroll view only lights once the scroll
    // view has waited to see whether the touch is a scroll, and a long press shows nothing until
    // its menu opens. nothing on a mac, where the pointer's hover does that job
    func tracksPress(_ isPressed: Binding<Bool>) -> some View {
        #if os(iOS)
        gesture(PressTracker(isPressed: isPressed))
        #else
        self
        #endif
    }
}

extension View {
    // a tap, and a hold that opens a menu, the hold counted from the moment the finger lands as
    // a message's is. onLongPressGesture in a scroll view only starts counting once the scroll
    // view has let the touch through, which made every other menu take noticeably longer
    func onTapOrHold(tap: @escaping () -> Void, hold: @escaping () -> Void) -> some View {
        modifier(TapOrHold(onTap: tap, onHold: hold))
    }
}

private struct TapOrHold: ViewModifier {
    let onTap: () -> Void
    let onHold: () -> Void

    // a simultaneous hold leaves the tap free to fire as the finger lifts, so the release
    // after a hold is swallowed here
    @State private var didHold = false
    @State private var isDown = false

    func body(content: Content) -> some View {
        content
            .onTapGesture(perform: tap)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.3).onEnded(hold))
            .tracksPress($isDown)
            .onChange(of: isDown, forgetHold)
    }

    private func tap() {
        guard !didHold else {
            didHold = false
            return
        }

        onTap()
    }

    private func hold(_: Bool) {
        didHold = true
        onHold()
    }

    // a hold that ended in a scroll leaves no release to take the flag, so every new press
    // starts without one
    private func forgetHold(_: Bool, _ down: Bool) {
        if down {
            didHold = false
        }
    }
}
