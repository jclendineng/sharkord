import SwiftUI

// with reduce motion on, things that slide or grow in fade in place instead. the system's own
// sheets and pushes already do this, these are for the views that move on their own
extension View {
    func slideTransition(from edge: Edge) -> some View {
        modifier(ReducibleTransition(moving: .move(edge: edge).combined(with: .opacity)))
    }

    func popTransition(scale: CGFloat = 0.9, anchor: UnitPoint = .center) -> some View {
        modifier(ReducibleTransition(moving: .opacity.combined(with: .scale(scale: scale, anchor: anchor))))
    }
}

private struct ReducibleTransition: ViewModifier {
    let moving: AnyTransition

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : moving)
    }
}
