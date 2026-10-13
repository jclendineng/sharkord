import SwiftUI

// discord's user settings: account things for the selected server, then this device's own
struct SettingsSheet: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Account Settings") {
                    NavigationLink {
                        AccountSettingsScreen()
                    } label: {
                        SettingsRow(title: "Account", systemImage: "person.crop.circle.fill")
                    }

                    NavigationLink {
                        DevicesScreen()
                    } label: {
                        SettingsRow(title: "Devices", systemImage: "laptopcomputer.and.iphone")
                    }
                }

                Section("App Settings") {
                    NavigationLink {
                        VoiceVideoSettingsScreen()
                    } label: {
                        SettingsRow(title: "Voice & Video", systemImage: "mic.fill")
                    }

                    NavigationLink {
                        NotificationSettingsScreen()
                    } label: {
                        SettingsRow(title: "Notifications", systemImage: "bell.fill")
                    }
                }

                Section("Support") {
                    NavigationLink {
                        AboutScreen()
                    } label: {
                        SettingsRow(title: "About", systemImage: "info.circle.fill", value: AppInfo.version)
                    }
                }

                Section {
                    Button(role: .destructive, action: logOut) {
                        SettingsRow(title: "Log Out", systemImage: "rectangle.portrait.and.arrow.right", tint: Theme.red)
                    }
                } footer: {
                    Text("Logs out of \(session.displayName) on this device.")
                }
            }
            .settingsListStyle()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: close)
                }
            }
        }
        .presentationBackground(Theme.deepBackground)
    }

    private func close() {
        dismiss()
    }

    private func logOut() {
        dismiss()
        servers.remove(session)
    }
}

struct SettingsRow: View {
    let title: String
    let systemImage: String
    var value: String?
    var tint = Theme.header

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 28)

            Text(title)
                .foregroundStyle(tint)

            Spacer()

            if let value {
                Text(value)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 4)
    }
}

extension View {
    func settingsListStyle() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.deepBackground)
            .listRowBackground(Theme.listBackground)
            .tint(Theme.blurple)
    }
}
