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

    // an icon button grows a touch on a spring under the pointer, the small bounce discord's
    // buttons have
    func hoverPop(scale: CGFloat = 1.12) -> some View {
        modifier(HoverPop(scale: scale))
    }
}

private struct HoverPop: ViewModifier {
    let scale: CGFloat

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: isHovered)
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
                        .fill(.white.opacity(0.08))
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
