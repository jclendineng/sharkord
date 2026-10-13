import SwiftUI

// discord's long press sheet for a channel
struct ChannelActionsSheet: View {
    let channel: Channel

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var isInvitePresented = false
    @State private var isNotificationsPresented = false

    private var isMuted: Bool {
        session.isMuted(channel.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ServerIcon(server: session)
                        .frame(width: 44, height: 44)
                        .clipShape(.rect(cornerRadius: 12))

                    Text(channel.type == .text ? "#\(channel.name)" : channel.name)
                        .font(.title3.bold())
                        .foregroundStyle(Theme.header)
                        .lineLimit(1)
                }
                .padding(.top, 20)

                ActionGroup {
                    ActionRow(title: "Invite", systemImage: "person.badge.plus", action: showInvite)
                    ActionRow(
                        title: session.isPinned(channel.id) ? "Unpin Channel" : "Pin Channel to Top",
                        systemImage: session.isPinned(channel.id) ? "pin.slash.fill" : "pin.fill",
                        action: togglePinned
                    )
                }

                ActionGroup {
                    ActionRow(title: "Mark As Read", systemImage: "eye", action: markAsRead)
                    ActionRow(
                        title: isMuted ? "Unmute Channel" : "Mute Channel",
                        systemImage: isMuted ? "bell.fill" : "bell.slash.fill",
                        action: toggleMuted
                    )
                    ActionRow(title: "Notification Settings", systemImage: "app.badge", action: showNotifications)
                }
            }
            .padding(.horizontal, 16)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.deepBackground)
        .sheet(isPresented: $isInvitePresented) {
            InviteSheet()
        }
        .sheet(isPresented: $isNotificationsPresented) {
            ChannelNotificationsSheet(channel: channel)
        }
    }

    private func showInvite() {
        isInvitePresented = true
    }

    private func togglePinned() {
        session.togglePinned(channel.id)
        dismiss()
    }

    private func markAsRead() {
        Task {
            await session.markAsRead(channel.id)
        }

        dismiss()
    }

    // muting is the "nothing" notification level, unmuting goes back to the default
    private func toggleMuted() {
        let level: ChannelNotificationLevel = isMuted ? .mentions : .none

        Task {
            await session.setNotificationLevel(level, for: channel.id)
        }

        dismiss()
    }

    private func showNotifications() {
        isNotificationsPresented = true
    }
}

private struct ChannelNotificationsSheet: View {
    let channel: Channel

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LevelRow(level: .all, title: "All Messages", channel: channel)
                    LevelRow(level: .mentions, title: "Only @mentions", channel: channel)
                    LevelRow(level: .none, title: "Nothing", channel: channel)
                } footer: {
                    Text("Replies to you count as mentions. Direct messages notify for every message unless set to nothing.")
                }
            }
            .settingsListStyle()
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.deepBackground)
    }

    private func close() {
        dismiss()
    }
}

private struct LevelRow: View {
    let level: ChannelNotificationLevel
    let title: String
    let channel: Channel

    @Environment(SessionStore.self) private var session

    private var isSelected: Bool {
        session.notificationLevel(for: channel.id) == level
    }

    var body: some View {
        Button(action: select) {
            HStack {
                Text(title)
                    .foregroundStyle(Theme.header)

                Spacer()

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Theme.blurple : Theme.muted)
            }
        }
    }

    private func select() {
        Task {
            await session.setNotificationLevel(level, for: channel.id)
        }
    }
}

struct ActionGroup<Content: View>: View {
    @ViewBuilder let content: Content

    // a hairline between rows, inset past the icons, like discord's grouped lists
    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows.indices, id: \.self) { index in
                    rows[index]

                    if index < rows.count - 1 {
                        Theme.divider.frame(height: 1)
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .background(Theme.listBackground, in: .rect(cornerRadius: 14))
    }
}

struct ActionRow: View {
    let title: String
    let systemImage: String
    var tint = Theme.header
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .frame(width: 26)

                Text(title)

                Spacer()
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
