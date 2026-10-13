import SwiftUI
import UserNotifications

struct NotificationSettingsScreen: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(\.openURL) private var openURL

    @State private var status = UNAuthorizationStatus.notDetermined

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            "On"
        case .denied:
            "Off"
        case .notDetermined:
            "Not asked yet"
        @unknown default:
            "Unknown"
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Allow Notifications")
                        .foregroundStyle(Theme.header)

                    Spacer()

                    Text(statusText)
                        .foregroundStyle(Theme.muted)
                }

                Button("Open iOS Settings", action: openSettings)
            } footer: {
                Text("Sounds, banners and the lock screen are set in iOS Settings.")
            }

            Section {
                ForEach(servers.sessions) { server in
                    ServerPushToggle(server: server)
                }
            } header: {
                Text("Push Notifications")
            } footer: {
                Text("Direct messages, mentions and replies to you. A server only offers this when its owner has set it up.")
            }
        }
        .settingsListStyle()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            openURL(url)
        }
    }
}

private struct ServerPushToggle: View {
    let server: SessionStore

    @State private var isOn = false

    private var isAvailable: Bool {
        server.serverInfo?.pushEnabled == true
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName)
                    .foregroundStyle(Theme.header)

                if !isAvailable {
                    Text("Not set up on this server")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .disabled(!isAvailable)
        .onAppear {
            isOn = server.isPushEnabled
        }
        .onChange(of: isOn) { _, enabled in
            guard enabled != server.isPushEnabled else {
                return
            }

            Task {
                await server.setPushEnabled(enabled)
            }
        }
    }
}
