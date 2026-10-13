import SwiftUI

// a fresh link each time, like discord's invite sheet. invites.add needs MANAGE_INVITES,
// anyone without it sees the server's refusal
struct InviteSheet: View {
    private static let lifetime: TimeInterval = 7 * 24 * 60 * 60

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var inviteURL: URL?
    @State private var errorMessage: String?
    @State private var isCopied = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Send a server invite link to a friend. It expires in 7 days.")
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
        .presentationDetents([.medium])
        .presentationBackground(Theme.listBackground)
        .task {
            await createInvite()
        }
    }

    private func createInvite() async {
        guard let client = session.client, let address = session.address else {
            return
        }

        struct InviteInput: Encodable {
            let expiresAt: Int
        }

        let expiresAt = Int(Date.now.addingTimeInterval(Self.lifetime).timeIntervalSince1970 * 1000)

        do {
            let invite: Invite = try await client.mutation("invites.add", input: InviteInput(expiresAt: expiresAt))
            let code = invite.code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? invite.code

            // the web client's invite link, see table-invite.tsx
            inviteURL = URL(string: "\(address.baseURL.absoluteString)/?invite=\(code)")
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
