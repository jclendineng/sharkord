import SwiftUI

// a sheet's cancel or confirm button, or a settings page's own action. on a mac it is the window's
// own push button with its title alone, as apple's sheets end: the sheet around it draws the app's
// borderless buttons, which made these plain text with an icon beside them
struct ActionToolbarItem<Content: View>: ToolbarContent {
    let placement: ActionToolbarPlacement
    @ViewBuilder let content: Content

    var body: some ToolbarContent {
        ToolbarItem(placement: placement.toolbarPlacement) {
            #if os(macOS)
            if placement != .confirmationAction {
                // a mac's cancel is a plain push button beside the filled confirm, the accent
                // tint turned its title the app's colour
                pushButton
                    .tint(Theme.header)
            } else {
                // the app's colour by name: a stack tinted neutral for its back button turned
                // the default button white
                pushButton
                    .tint(Theme.blurple)
            }
            #else
            content
            #endif
        }
    }

    #if os(macOS)
    private var pushButton: some View {
        content
            .buttonStyle(.automatic)
            // a menu as a pull down push button, as a mac's toolbar draws one
            .menuStyle(.button)
            .labelStyle(.titleOnly)
    }
    #endif
}

enum ActionToolbarPlacement {
    case cancellationAction
    case confirmationAction
    case pageAction

    var toolbarPlacement: ToolbarItemPlacement {
        switch self {
        case .cancellationAction:
            .cancellationAction
        case .confirmationAction:
            .confirmationAction
        case .pageAction:
            .barTrailing
        }
    }
}
