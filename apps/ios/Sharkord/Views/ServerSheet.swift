import SwiftUI

// discord's server sheet, opened from the server name above the channels
struct ServerSheet: View {
    let onInvite: () -> Void

    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var isInboxPresented = false
    @State private var isNotificationsPresented = false
    @State private var isEditProfilePresented = false
    @State private var isAddressCopied = false
    @State private var isReportUnavailable = false
    @State private var isEmojiManagerPresented = false
    @State private var isSettingsPresented = false

    @Environment(\.openURL) private var openURL

    private var hideMutedChannels: Binding<Bool> {
        Binding(
            get: { session.hidesMutedChannels },
            set: { session.setHidesMutedChannels($0) }
        )
    }

    private var allowDirectMessages: Binding<Bool> {
        Binding(
            get: { session.allowsDirectMessages },
            set: { allows in
                Task {
                    await session.setAllowsDirectMessages(allows)
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ServerIcon(server: session)
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 6) {
                    Text(session.displayName)
                        .font(.title2.bold())
                        .foregroundStyle(Theme.header)

                    HStack(spacing: 12) {
                        CountLabel(count: session.onlineCount, label: "Online", color: Theme.green)
                        CountLabel(count: session.members.count, label: "Members", color: Theme.muted)
                    }
                }

                HStack(spacing: 0) {
                    SheetAction(title: "Invite", systemImage: "person.badge.plus", action: invite)
                    SheetAction(title: "Notifications", systemImage: "bell.fill", action: showNotifications)
                    SheetAction(title: "Inbox", systemImage: "tray.fill", action: showInbox)
                    if session.canManageServer {
                        SheetAction(title: "Settings", systemImage: "gearshape.fill", action: openSettings)
                    }
                }

                ActionGroup {
                    ActionRow(title: "Mark As Read", systemImage: "envelope.open", action: markAllAsRead)
                }

                ActionGroup {
                    ActionRow(title: "Edit Server Profile", systemImage: "person.crop.circle", action: editProfile)

                    Toggle(isOn: hideMutedChannels) {
                        Label("Hide Muted Channels", systemImage: "bell.slash")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Toggle(isOn: allowDirectMessages) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Allow Direct Messages", systemImage: "bubble.left.and.bubble.right")

                            Text("Anyone on the server can start a conversation with you")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    ActionRow(title: "Report Server", systemImage: "flag", tint: Theme.red, action: report)
                }
                .tint(Theme.blurple)
                .foregroundStyle(Theme.header)

                ServerEmojiGrid(onManage: manageEmoji)

                ActionGroup {
                    if let host = session.address?.baseURL.absoluteString {
                        ActionRow(title: isAddressCopied ? "Copied" : "Copy Server Address", systemImage: "link", action: { copy(host) })
                    }

                    ActionRow(title: "Log Out", systemImage: "rectangle.portrait.and.arrow.right", tint: Theme.red, action: logOut)
                }
            }
            .padding(20)
        }
        // like discord's, it rises to just below the server name and stays there, the
        // contents scroll inside and a swipe down closes it
        .presentationDetents([.fraction(0.86)])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.deepBackground)
        .sheet(isPresented: $isInboxPresented) {
            InboxSheet()
        }
        .sheet(isPresented: $isNotificationsPresented) {
            NavigationStack {
                NotificationSettingsScreen()
            }
        }
        .sheet(isPresented: $isEditProfilePresented) {
            EditProfileSheet()
        }
        .sheet(isPresented: $isEmojiManagerPresented) {
            EmojiManagerScreen()
        }
        .sheet(isPresented: $isSettingsPresented) {
            ServerSettingsScreen()
        }
        .alert("Reporting isn't set up", isPresented: $isReportUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This server's admins haven't added an address for reports yet. They can add one in Server Settings, under Overview.")
        }
    }

    private func invite() {
        dismiss()
        onInvite()
    }

    private func markAllAsRead() {
        Task {
            await session.markAllAsRead()
        }

        dismiss()
    }

    private func showInbox() {
        isInboxPresented = true
    }

    private func manageEmoji() {
        isEmojiManagerPresented = true
    }

    private func showNotifications() {
        isNotificationsPresented = true
    }

    private func editProfile() {
        isEditProfilePresented = true
    }

    private func openSettings() {
        isSettingsPresented = true
    }

    // the report goes by email to the address the server's admins set
    private func report() {
        guard
            let reportEmail = session.reportEmail,
            var components = URLComponents(string: "mailto:\(reportEmail)")
        else {
            isReportUnavailable = true
            return
        }

        components.queryItems = [
            URLQueryItem(name: "subject", value: "Report: \(session.displayName)"),
            URLQueryItem(
                name: "body",
                value: "Server: \(session.displayName)\nAddress: \(session.address?.baseURL.absoluteString ?? "")\nServer id: \(session.serverId ?? "")\n\nWhat happened:\n"
            )
        ]

        if let url = components.url {
            openURL(url)
        }
    }

    private func copy(_ host: String) {
        UIPasteboard.general.string = host
        isAddressCopied = true
    }

    private func logOut() {
        dismiss()
        servers.remove(session)
    }
}

private struct CountLabel: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text("\(count) \(label)")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
    }
}

private struct SheetAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.header)
                    .frame(width: 60, height: 60)
                    .background(Theme.listBackground, in: .rect(cornerRadius: 18))

                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// the server's own emoji, the first few rows and a count of the rest
private struct ServerEmojiGrid: View {
    private static let shown = 32

    let onManage: () -> Void

    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Server Emoji")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)

                Spacer()

                Button("Manage", action: onManage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.link)
            }

            if session.customEmojis.isEmpty {
                Text("No emoji yet. Add some, or a whole pack, from Manage.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.listBackground, in: .rect(cornerRadius: 14))
            } else {
                emojiGrid
            }
        }
    }

    private var emojiGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 8) {
                ForEach(session.customEmojis.prefix(Self.shown)) { emoji in
                    if let address = session.address {
                        AsyncImage(url: address.fileURL(emoji.file)) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Color.clear
                        }
                        .frame(width: 28, height: 28)
                        .accessibilityLabel(":\(emoji.name):")
                    }
                }

                if session.customEmojis.count > Self.shown {
                    Text("+\(session.customEmojis.count - Self.shown)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(14)
            .background(Theme.listBackground, in: .rect(cornerRadius: 14))
        }
    }
}
