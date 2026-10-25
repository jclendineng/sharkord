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
        }
        .formStyle(.grouped)
        .buttonStyle(FormButtonStyle())
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
            Button(configuration)
                .buttonStyle(.automatic)
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
