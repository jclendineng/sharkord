import SwiftUI

// a page in a mac settings sidebar, discord's: a soft rounded fill under the pointer and a firmer
// one once picked, the label going from muted to bright with it. the list's own hover probe does
// not reach a split view's column, so the row tints itself, and draws the selection too. a button
// rather than the list's selection, which a native mac draws as a blue band no row background
// covers
struct SettingsSidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var tint: Color?
    let action: () -> Void

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
        Button(action: action) {
            SettingsRow(title: title, systemImage: systemImage, tint: labelTint)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .background(fill, in: .rect(cornerRadius: 6, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover(perform: setHovered)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }
}

// a mac settings window: the pages down the side and the page beside them, laid out by hand. a
// split view in a mac sheet floated its sidebar as an inset card, out of line with the page and
// taller than it, and the sheet's glass showed the window through wherever the page did not paint
struct SettingsWindow<Sidebar: View, Detail: View>: View {
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let detail: Detail

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
                .frame(maxHeight: .infinity)

            Theme.divider
                .frame(width: 1)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // a pushed page's back button in the bar's neutral colour, not a blurple disc
        .tint(Theme.header)
        .background(Theme.deepBackground)
        // the sheet is as dark as the chat behind it, which hid its edge
        .overlay {
            ConcentricRectangle()
                // half the line falls outside the sheet, the inner half shows
                .stroke(Theme.divider, lineWidth: 2)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .presentationBackground(Theme.deepBackground)
        // escape closes it, as it does every other mac sheet
        .escapeGoesBack()
    }
}

// a sidebar section's title, lined up over its rows' icons rather than out at the list's edge
// a row rather than a section header: a mac pins a plain list's header to the top and draws a
// line under it, which sat between the first heading and its rows
struct SettingsSidebarHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            // apart from the section above, whose last row it otherwise sat against
            .padding(.top, 10)
            .padding(.bottom, 2)
            // the row's 8 inset and 10 padding, and the icon's own 2 inside its frame
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    // a mac settings sidebar list, plain rows with no cards or lines between them
    func settingsSidebarStyle() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.listBackground)
            // a mac sheet's split view squeezed the sidebar to a sliver. a column width here
            // crashed swiftui on opening, a frame does not
            .frame(minWidth: 260)
    }

    // a settings page beside the sidebar. its bar takes the page's colour only when set on the
    // page itself, set on the split view a mac drew it a shade off. a mac's close sits in the
    // page's own bottom bar, beside a page's save: one in the sidebar went on a bar of the
    // window's across the whole sheet, tinted by the desktop
    // no close in the settings window, which has the window's own
    func settingsPage(onClose close: (() -> Void)?) -> some View {
        navigationBarBackground(Theme.deepBackground)
            .navigationBarBackgroundVisible()
            #if os(macOS)
            .toolbar {
                if let close {
                    ActionToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: close)
                    }
                }
            }
            #endif
    }
}
