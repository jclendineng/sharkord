import SwiftUI

// a page in a mac settings sidebar, discord's: a soft rounded fill under the pointer and a firmer
// one once picked, the label going from muted to bright with it. the list's own hover probe does
// not reach a split view's column, so the row tints itself, and draws the selection too, its own
// background covering the list's
struct SettingsSidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var tint: Color?

    @State private var isHovered = false

    private var fill: Color {
        if isSelected {
            return Theme.hover
        }

        return isHovered ? Theme.hover.opacity(0.55) : .clear
    }

    private var labelTint: Color {
        if let tint {
            return tint
        }

        return isSelected || isHovered ? Theme.header : Theme.muted
    }

    var body: some View {
        SettingsRow(title: title, systemImage: systemImage, tint: labelTint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(fill, in: .rect(cornerRadius: 6, style: .continuous))
            .contentShape(.rect)
            .onHover(perform: setHovered)
            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }
}

extension View {
    // a mac settings sidebar list, plain rows with no cards or lines between them
    func settingsSidebarStyle() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.listBackground)
    }
}
