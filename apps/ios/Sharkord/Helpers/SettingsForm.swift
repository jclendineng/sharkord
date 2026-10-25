import SwiftUI

// a settings page's rows. a phone's inset grouped list, and on a mac the grouped form its own
// settings use: rounded sections, the label at the leading edge and its control at the trailing
// one, a push button for an action. a mac list has no grouped style of its own
struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if os(macOS)
        Form {
            content
                // neutral, as a mac's own forms are: a pop up's value in the accent read as a
                // link. the switches carry the app's colour themselves
                .tint(Theme.header)
        }
        .formStyle(.grouped)
        .buttonStyle(FormButtonStyle())
        // every form here is a page in a sheet, or pushed inside one
        .sheetBarBackground()
        #else
        List {
            content
        }
        #endif
    }
}

#if os(macOS)
// a mac form's push buttons, where the sheet around it draws the app's own borderless ones. one
// that deletes is red: the form's accent tint turned it the same colour as the rest
private struct FormButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if configuration.role == .destructive {
            Button(configuration)
                .buttonStyle(.automatic)
                .tint(Theme.red)
        } else {
            // the label's own colour, as a mac's push buttons are, not the form's accent tint
            Button(configuration)
                .buttonStyle(.automatic)
                .tint(Theme.header)
        }
    }
}
#endif

// a page's action, its change password or delete. a row of its own on a phone, and on a mac a
// push button at the trailing edge under the sections, where apple's forms keep it
struct SettingsActions<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if os(macOS)
        Section {
        } footer: {
            HStack {
                Spacer()

                content
            }
        }
        #else
        Section {
            content
        }
        #endif
    }
}
