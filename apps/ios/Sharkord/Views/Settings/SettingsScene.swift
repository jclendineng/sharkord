import SwiftUI

#if os(macOS)
// the mac's settings window, for the server picked in the main window. a new server picked while
// it is open starts it over on that server's account
struct SettingsScene: View {
    @Environment(ServerListStore.self) private var servers

    var body: some View {
        Group {
            if let session = servers.selectedSession {
                SettingsSheet()
                    .environment(session)
                    .id(ObjectIdentifier(session))
            } else {
                ContentUnavailableView("No Server", systemImage: "server.rack", description: Text("Add a server to change your settings on it."))
            }
        }
        .environment(\.isSettingsWindow, true)
        .frame(width: 860, height: 540)
        .phoneControlStyle()
        .phoneButtons()
    }
}
#endif

extension EnvironmentValues {
    // settings in a window of their own, which closes with the window's own button rather than a
    // Close beside a page's Save
    @Entry var isSettingsWindow = false
}
