import SwiftUI

// a fresh link each time, like discord's invite sheet, with its expire after and max uses.
// invites.add needs MANAGE_INVITES, anyone without it sees the server's refusal
struct InviteSheet: View {
    private static let maxUsesChoices = [0, 1, 5, 10, 25, 50, 100]

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var expiry = InviteExpiry.week
    @State private var maxUses = 0
    @State private var invite: Invite?
    @State private var inviteURL: URL?
    @State private var errorMessage: String?
    @State private var isCopied = false

    private var settingsKey: String {
        "\(expiry.rawValue)-\(maxUses)"
    }

    private var summary: String {
        let expires = expiry == .never ? "never expires" : "expires in \(expiry.rawValue)"
        let uses = maxUses == 0 ? "" : ", good for \(maxUses) \(maxUses == 1 ? "use" : "uses")"

        return "Send a server invite link to a friend. It \(expires)\(uses)."
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(summary)
                    .foregroundStyle(Theme.muted)

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
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                VStack(spacing: 0) {
                    settingRow("Expire After") {
                        Picker("Expire After", selection: $expiry) {
                            ForEach(InviteExpiry.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    }

                    Divider()
                        .overlay(Theme.divider)

                    settingRow("Max Uses") {
                        Picker("Max Uses", selection: $maxUses) {
                            ForEach(Self.maxUsesChoices, id: \.self) { count in
                                Text(count == 0 ? "No limit" : "\(count) \(count == 1 ? "use" : "uses")").tag(count)
                            }
                        }
                    }
                }
                .background(Theme.deepBackground, in: .rect(cornerRadius: 10))

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
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.listBackground)
        .task(id: settingsKey) {
            await createInvite()
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

    // a change of settings replaces the link, and the one it replaces is deleted so unused
    // invites do not pile up in the server's list
    private func createInvite() async {
        guard let client = session.client, let address = session.address else {
            return
        }

        struct InviteInput: Encodable {
            let expiresAt: Int?
            let maxUses: Int
        }

        let expiresAt = expiry.interval.map { Int(Date.now.addingTimeInterval($0).timeIntervalSince1970 * 1000) }
        let previous = invite

        inviteURL = nil
        errorMessage = nil
        isCopied = false

        do {
            let created: Invite = try await client.mutation("invites.add", input: InviteInput(expiresAt: expiresAt, maxUses: maxUses))
            let code = created.code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? created.code

            invite = created
            // the web client's invite link, see table-invite.tsx
            inviteURL = URL(string: "\(address.baseURL.absoluteString)/?invite=\(code)")

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
