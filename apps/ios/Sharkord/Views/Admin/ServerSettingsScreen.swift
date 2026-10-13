import SwiftUI

// everything the web client's server settings do, so nobody has to leave the app. each
// section shows only to someone who may use it, the server checks again on every change
struct ServerSettingsScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if session.can(.manageSettings) {
                        NavigationLink {
                            GeneralSettingsScreen()
                        } label: {
                            SettingsRow(title: "Overview", systemImage: "info.circle.fill")
                        }
                    }

                    if session.can(.manageRoles) {
                        NavigationLink {
                            RolesScreen()
                        } label: {
                            SettingsRow(title: "Roles", systemImage: "shield.lefthalf.filled")
                        }
                    }

                    if session.can(.manageEmojis) {
                        NavigationLink {
                            EmojiManagerList()
                        } label: {
                            SettingsRow(title: "Emoji", systemImage: "face.smiling.inverse")
                        }
                    }
                }

                Section("Community") {
                    if session.can(.manageUsers) {
                        NavigationLink {
                            MembersScreen()
                        } label: {
                            SettingsRow(title: "Members", systemImage: "person.2.fill")
                        }
                    }

                    if session.can(.manageInvites) {
                        NavigationLink {
                            InvitesScreen()
                        } label: {
                            SettingsRow(title: "Invites", systemImage: "link")
                        }
                    }

                    if session.can(.manageChannels) || session.can(.manageCategories) || session.can(.manageChannelPermissions) {
                        NavigationLink {
                            ChannelsAdminScreen()
                        } label: {
                            SettingsRow(title: "Channels", systemImage: "number")
                        }
                    }
                }

                if session.can(.manageStorage) || session.can(.managePlugins) || session.can(.manageUpdates) {
                    Section {
                        Button(action: openWeb) {
                            SettingsRow(title: "Storage, Plugins & Updates", systemImage: "safari", value: "Web")
                        }
                    } footer: {
                        Text("These still open the web client, they come to the app next.")
                    }
                }
            }
            .settingsListStyle()
            .navigationTitle("Server Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: close)
                }
            }
        }
        .presentationBackground(Theme.deepBackground)
    }

    private func openWeb() {
        if let url = session.address?.baseURL {
            openURL(url)
        }
    }

    private func close() {
        dismiss()
    }
}
