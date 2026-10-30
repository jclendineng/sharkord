import SwiftUI

extension View {
    // a row drawn with plain gestures rather than a button, so a long press cancels its tap,
    // still opens from the keyboard: Full Keyboard Access presses its accessibility action, and a
    // mac's Tab reaches it, ringed while focused, for Return or Space to open it
    func keyboardActivatable(cornerRadius: CGFloat = 6, perform action: @escaping () -> Void) -> some View {
        modifier(KeyboardActivation(cornerRadius: cornerRadius, action: action))
    }
}

private struct KeyboardActivation: ViewModifier {
    let cornerRadius: CGFloat
    let action: () -> Void

    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityAction(.default, action)
            #if os(macOS)
            .focusable(interactions: .activate)
            .focused($isFocused)
            .onKeyPress(keys: [.return, .space]) { _ in
                action()

                return .handled
            }
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            #endif
    }
}
