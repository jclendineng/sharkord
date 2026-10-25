import SwiftUI

// a mac's way to move a row up or down a list, where edit mode's drag handles do not work. each
// arrow a full size target, the icon alone was too small to hit
struct ReorderArrows: View {
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            arrow("Move Up", systemImage: "arrow.up", action: moveUp)
                .disabled(!canMoveUp)

            arrow("Move Down", systemImage: "arrow.down", action: moveDown)
                .disabled(!canMoveDown)
        }
    }

    private func arrow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
        .help(title)
    }
}
