import SwiftUI
import UserNotifications

struct NotificationSettingsScreen: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(\.openURL) private var openURL

    @State private var status = UNAuthorizationStatus.notDetermined

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            String(localized: "On")
        case .denied:
            String(localized: "Off")
        case .notDetermined:
            String(localized: "Not asked yet")
        @unknown default:
            String(localized: "Unknown")
        }
    }

    var body: some View {
        SettingsForm {
            Section {
                HStack {
                    Text("Allow Notifications")
                        .foregroundStyle(Theme.header)

                    Spacer()

                    Text(statusText)
                        .foregroundStyle(Theme.muted)
                }

                Button("Open \(SystemSettings.name)", action: openSettings)
            } footer: {
                Text(Platform.isMac
                    ? "Sounds, banners and alerts are set in System Settings, under Notifications."
                    : "Sounds, banners and the lock screen are set in Settings.")
                    .wrappingFooter()
            }

            Section {
                ForEach(servers.sessions) { server in
                    ServerPushToggle(server: server)
                }
            } header: {
                Text("Push Notifications")
            } footer: {
                Text("Direct messages, mentions and replies to you. A server only offers this when its owner has set it up.")
                    .wrappingFooter()
            }
        }
        .settingsListStyle()
        .navigationTitle("Notifications")
        .inlineNavigationTitle()
        .task {
            status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    private func openSettings() {
        if let url = SystemSettings.url(for: .notifications) {
            openURL(url)
        }
    }
}

private struct ServerPushToggle: View {
    let server: SessionStore

    @State private var isOn = false

    private var isAvailable: Bool {
        server.serverInfo?.offersPush == true
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
