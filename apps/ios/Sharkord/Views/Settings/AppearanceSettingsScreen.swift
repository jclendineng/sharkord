import SwiftUI

struct AppearanceSettingsScreen: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        SettingsForm {
            Section {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppSettings.Appearance.allCases, id: \.self) { appearance in
                        Text(appearance.title)
                    }
                }
                .pickerStyle(.segmented)
                // a mac form's row reads its label at the leading edge, the control at the
                // trailing one. a phone's row is the control alone
                #if os(iOS)
                .labelsHidden()
                #endif
            } footer: {
                Text("System follows this device's light or dark setting. Calls and sign in stay dark either way.")
                    .wrappingFooter()
            }
        }
        .settingsListStyle()
        .navigationTitle("Appearance")
        .inlineNavigationTitle()
    }
}

extension View {
    // the appearance picked in settings, or none to follow the system's
    func appAppearance(isSheet: Bool = false) -> some View {
        modifier(AppAppearance(isSheet: isSheet))
    }
}

private struct AppAppearance: ViewModifier {
    let isSheet: Bool

    @State private var settings = AppSettings.shared

    func body(content: Content) -> some View {
        #if os(macOS)
        // the app's own appearance rather than a preference: it reaches the settings window too,
        // and a window handed back to the system after a preference kept the old one
        content
            .onChange(of: settings.appearance, initial: true, apply)
        #else
        content
            .preferredColorScheme(colorScheme)
        #endif
    }

    #if os(macOS)
    private func apply() {
        switch settings.appearance {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    #else
    private var colorScheme: ColorScheme? {
        switch settings.appearance {
        case .system:
            isSheet ? systemColorScheme : nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    // an open sheet handed no preference keeps the one it had, so a switch to System showed only
    // once it closed. a sheet is given the system's appearance itself, read off the screen, which
    // the app's own preference does not reach
    private var systemColorScheme: ColorScheme? {
        let scene = UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene

        guard let scene else {
            return nil
        }

        return scene.screen.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }
    #endif
}
