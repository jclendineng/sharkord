import SwiftUI

// a sheet's cancel or confirm button. on a mac it is the window's own push button with its title
// alone, as apple's sheets end: the sheet around it draws the app's borderless buttons, which made
// these plain text with an icon beside them
struct ActionToolbarItem<Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    @ViewBuilder let content: Content

    var body: some ToolbarContent {
        ToolbarItem(placement: placement) {
            #if os(macOS)
            content
                .buttonStyle(.automatic)
                .labelStyle(.titleOnly)
            #else
            content
            #endif
        }
    }
}
