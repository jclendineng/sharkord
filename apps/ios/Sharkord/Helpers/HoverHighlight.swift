import SwiftUI

extension View {
    // a row lights up under the pointer, as discord's do on a mac, so it is clear what a click
    // will pick. nothing changes without a pointer
    func hoverHighlight(cornerRadius: CGFloat = 6) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, style: .fill))
    }

    // a tile or card with a background of its own brightens under the pointer instead, a fill
    // behind it would not show
    func hoverBrighten(cornerRadius: CGFloat = 8) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, style: .brighten))
    }

    // an icon button grows a touch under the pointer. the spring is critically damped, a hover
    // happens dozens of times a session and an overshoot on each one reads as wobble
    func hoverPop(scale: CGFloat = 1.12) -> some View {
        modifier(HoverPop(scale: scale))
    }
}

private struct HoverPop: ViewModifier {
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered && !reduceMotion ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 1), value: isHovered)
            .onHover(perform: setHovered)
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }
}

private struct HoverHighlight: ViewModifier {
    enum Style {
        case fill
        case brighten
    }

    let cornerRadius: CGFloat
    let style: Style

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                if style == .fill, isHovered {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.hover)
                }
            }
            .overlay {
                if style == .brighten, isHovered {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.hoverOverlay)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(.rect(cornerRadius: cornerRadius))
            .onHover(perform: setHovered)
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }
}
