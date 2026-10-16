import SwiftUI

struct RootView: View {
    @Environment(ServerListStore.self) private var servers

    var body: some View {
        Group {
            #if DEBUG
            if DebugLaunch.opensVoicePlayground {
                VoicePlayground()
            } else {
                app
            }
            #else
            app
            #endif
        }
        .tint(Theme.blurple)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var app: some View {
        if let session = servers.signingInSession {
            ConnectView(canCancel: !servers.sessions.isEmpty)
                .environment(session)
        } else if let session = servers.selectedSession {
            HomeView(session: session)
        }
    }
}

#if DEBUG
// see DebugLaunch.opensVoicePlayground
private struct VoicePlayground: View {
    @Environment(ServerListStore.self) private var servers

    @State private var session = SessionStore(address: nil)
    @State private var isPresented = false

    private let channel = Channel(id: 1, type: .voice, name: "General Voice", topic: nil, private: false, isDm: false, position: 0, categoryId: nil)

    var body: some View {
        ZStack {
            Theme.deepBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                ForEach(0..<8) { index in
                    Text("Channel \(index)")
                        .foregroundStyle(Theme.text)
                }

                Button("Open Voice Channel", action: open)
            }
            .padding(40)
        }
        .sheet(isPresented: $isPresented) {
            VoiceChannelSheet(channel: channel)
                .environment(session)
                .environment(servers)
                .appSheet()
        }
        .environment(session)
    }

    private func open() {
        isPresented = true
    }
}
#endif
