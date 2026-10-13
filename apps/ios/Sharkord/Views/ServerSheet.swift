import SwiftUI

// discord's server sheet, opened from the server name above the channels
struct ServerSheet: View {
    let onInvite: () -> Void

    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var isInboxPresented = false
    @State private var isAddressCopied = false

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
                    SheetAction(title: "Mark Read", systemImage: "checkmark.circle", action: markAllAsRead)
                    SheetAction(title: "Notifications", systemImage: "bell.fill", action: showInbox)
                }

                VStack(spacing: 0) {
                    if let host = session.address?.baseURL.absoluteString {
                        SheetRow(title: isAddressCopied ? "Copied" : "Copy Server Address", action: { copy(host) })
                    }
                }
                .background(Theme.listBackground, in: .rect(cornerRadius: 12))

                Button(action: logOut) {
                    Text("Log Out")
                        .foregroundStyle(Theme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Theme.listBackground, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.deepBackground)
        .sheet(isPresented: $isInboxPresented) {
            InboxSheet()
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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.header)
                    .frame(width: 52, height: 52)
                    .background(Theme.listBackground, in: .circle)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct SheetRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
