import SwiftUI

// what a link is made with, the sheet's two pickers
private struct InviteSettings: Equatable {
    var expiry = InviteExpiry.week
    var maxUses = 0
}

// your last link while it still works, with its expire after and max uses. a new one only when a
// setting changes or one is asked for, after asking once the link has been used, since someone
// may be holding it. invites.add and getAll need MANAGE_INVITES, anyone without it sees the
// server's refusal
struct InviteSheet: View {
    private static let maxUsesChoices = [0, 1, 5, 10, 25, 50, 100]

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var settings = InviteSettings()
    @State private var invite: Invite?
    // when the shown link runs out, nil for never
    @State private var expiresAt: Date?
    @State private var uses = 0
    // the link's own limit, which a link made elsewhere may have outside the picker's choices
    @State private var usesLimit = 0
    // the settings the shown link was made with: the pickers set from a reused link must not
    // count as asking for a new one, and a cancelled replace puts them back
    @State private var shownSettings: InviteSettings?
    @State private var inviteURL: URL?
    @State private var errorMessage: String?
    @State private var isCopied = false
    @State private var isReplaceConfirmPresented = false

    private var usesText: String {
        if usesLimit > 0 {
            return "Used \(uses) of \(usesLimit) times"
        }

        if uses == 0 {
            return "Not used yet"
        }

        return "Used \(uses) \(uses == 1 ? "time" : "times")"
    }

    private var summary: String {
        var expires = "never expires"

        if let expiresAt {
            expires = "expires in \(InviteExpiry.timeLeft(until: expiresAt))"
        }

        return "Your invite link. \(usesText), \(expires)."
    }

    private var replaceMessage: String {
        if uses == 0 {
            return "Your current link will stop working."
        }

        return "Your current link will stop working for anyone you sent it to. \(usesText)."
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(summary)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let inviteURL {
                    Text(inviteURL.absoluteString)
                        .font(.callout.monospaced())
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.deepBackground, in: .rect(cornerRadius: 10))

                    HStack(spacing: 12) {
                        ShareLink(item: inviteURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: copy) {
                            Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.large)

                    Button("Replace Link", systemImage: "arrow.clockwise", action: confirmReplace)
                        .font(.subheadline)
                        .tint(Theme.link)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                VStack(spacing: 0) {
                    settingRow("Expire After") {
                        Picker("Expire After", selection: $settings.expiry) {
                            ForEach(InviteExpiry.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    }

                    Divider()
                        .overlay(Theme.divider)

                    settingRow("Max Uses") {
                        Picker("Max Uses", selection: $settings.maxUses) {
                            ForEach(Self.maxUsesChoices, id: \.self) { count in
                                Text(count == 0 ? "No limit" : "\(count) \(count == 1 ? "use" : "uses")").tag(count)
                            }
                        }
                    }
                }
                .background(Theme.deepBackground, in: .rect(cornerRadius: 10))

                if session.can(.manageInvites) {
                    NavigationLink {
                        InvitesScreen()
                            .environment(session)
                            .environment(servers)
                    } label: {
                        Label("Manage All Invites", systemImage: "list.bullet")
                            .font(.subheadline)
                    }
                    .tint(Theme.link)
                }

                Spacer()
            }
            .padding(20)
            .background(Theme.listBackground)
            .navigationTitle("Invite to \(session.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
        }
        .sheetDetents([.medium, .large])
        .presentationBackground(Theme.listBackground)
        .alert("Replace this link?", isPresented: $isReplaceConfirmPresented) {
            Button("Replace Link", role: .destructive, action: regenerate)
            Button("Cancel", role: .cancel, action: restoreSettings)
        } message: {
            Text(replaceMessage)
        }
        .task {
            await loadInvite()
        }
        .onChange(of: settings) { _, changed in
            guard let shownSettings, changed != shownSettings else {
                return
            }

            if uses == 0 {
                regenerate()
            } else {
                isReplaceConfirmPresented = true
            }
        }
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.header)

            Spacer()

            content()
                .tint(Theme.muted)
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(minHeight: 48)
    }

    // the newest of your own links that still works, a role's invite left to the admin list. none,
    // and a link is made
    private func loadInvite() async {
        let all: [AdminInvite]? = try? await session.request("invites.getAll")
        let usable = (all ?? []).filter { candidate in
            let hasUsesLeft = (candidate.maxUses ?? 0) == 0 || candidate.uses < (candidate.maxUses ?? 0)

            return candidate.creator?.id == session.ownUserId && candidate.role == nil && !candidate.isExpired && !candidate.isDeleted && hasUsesLeft
        }

        guard let reused = usable.max(by: { $0.createdAt < $1.createdAt }), let address = session.address else {
            await createInvite()
            return
        }

        invite = Invite(id: reused.id, code: reused.code)
        inviteURL = Self.link(for: reused.code, address: address)
        expiresAt = reused.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        uses = reused.uses
        usesLimit = reused.maxUses ?? 0
        settings.maxUses = Self.maxUsesChoices.contains(usesLimit) ? usesLimit : 0
        // the lifetime it was made with, which is one of the picker's
        let lifetime = reused.expiresAt.map { TimeInterval($0 - reused.createdAt) / 1000 }

        settings.expiry = InviteExpiry.allCases.first { $0.interval.map { abs($0 - (lifetime ?? 0)) < 60 } ?? (lifetime == nil) } ?? .week
        shownSettings = settings
    }

    private func confirmReplace() {
        isReplaceConfirmPresented = true
    }

    // a cancelled replace, or one dismissed by tapping outside the dialog
    private func restoreSettings() {
        if let shownSettings {
            settings = shownSettings
        }
    }

    private func regenerate() {
        Task {
            await createInvite()
        }
    }

    // the web client's invite link, see table-invite.tsx
    private static func link(for code: String, address: ServerAddress) -> URL? {
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code

        return URL(string: "\(address.baseURL.absoluteString)/?invite=\(encoded)")
    }

    // a new link replaces the shown one, which is deleted so unused invites do not pile up in the
    // server's list
    private func createInvite() async {
        guard let client = session.client, let address = session.address else {
            return
        }

        struct InviteInput: Encodable {
            let expiresAt: Int?
            let maxUses: Int
        }

        let expiresAt = settings.expiry.interval.map { Int(Date.now.addingTimeInterval($0).timeIntervalSince1970 * 1000) }
        let previous = invite

        shownSettings = settings
        inviteURL = nil
        errorMessage = nil
        isCopied = false

        do {
            let created: Invite = try await client.mutation("invites.add", input: InviteInput(expiresAt: expiresAt, maxUses: settings.maxUses))

            invite = created
            uses = 0
            usesLimit = settings.maxUses
            inviteURL = Self.link(for: created.code, address: address)
            self.expiresAt = expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }

            if let previous {
                try? await client.mutation("invites.delete", input: ["inviteId": previous.id])
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copy() {
        UIPasteboard.general.url = inviteURL
        isCopied = true
    }

    private func close() {
        dismiss()
    }
}
