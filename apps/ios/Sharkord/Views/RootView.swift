import SwiftUI

struct RootView: View {
    @Environment(ServerListStore.self) private var servers

    var body: some View {
        Group {
            if let session = servers.signingInSession {
                ConnectView(canCancel: !servers.sessions.isEmpty)
                    .environment(session)
            } else if let session = servers.selectedSession {
                HomeView(session: session)
            }
        }
        .tint(Theme.blurple)
        .preferredColorScheme(.dark)
    }
}
