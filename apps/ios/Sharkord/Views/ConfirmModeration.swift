import SwiftUI

enum ModerationAction: Identifiable {
    case kick
    case ban
    case delete

    var id: Self { self }
}

// a kick, ban or delete is confirmed with what will happen spelled out, and a reason
struct ConfirmModeration: View {
    let action: ModerationAction
    let name: String
    @Binding var reason: String
    @Binding var wipe: Bool
    @Binding var banIps: Bool
    let onConfirm: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch action {
        case .kick:
            String(localized: "Kick \(name)")
        case .ban:
            String(localized: "Ban \(name)")
        case .delete:
            String(localized: "Delete \(name)'s Account")
        }
    }

    var body: some View {
        NavigationStack {
            SettingsForm {
                if action == .delete {
                    Section {
                        Toggle("Also Delete Their Messages", isOn: $wipe)
                    } footer: {
                        Text("Otherwise their messages stay, shown as from a deleted user. This can't be undone.")
                            .wrappingFooter()
                    }
                } else {
                    Section("Reason (optional)") {
                        TextField("", text: $reason, prompt: Text("Why?"), axis: .vertical)
                            .labelsHidden()
                            .lineLimit(2...4)
                    }
                }

                if action == .ban, session.supports(.ipBans) {
                    Section {
                        Toggle("Also Ban Their IP Addresses", isOn: $banIps)
                    } footer: {
                        Text("Blocks the public addresses they signed in from, so a new account from there is refused. Anyone else on those networks, like a household, is locked out too. Unbanning lifts it.")
                            .wrappingFooter()
                    }
                }

                Section {
                    Button(role: .destructive, action: confirm) {
                        Text(title)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .settingsListStyle()
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ActionToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }
            }
        }
        .sheetDetents([.medium])
        .presentationBackground(Theme.deepBackground)
    }

    private func confirm() {
        dismiss()
        onConfirm()
    }

    private func close() {
        dismiss()
    }
}

struct PendingModeration: Identifiable {
    let user: PublicUser
    let action: ModerationAction

    var id: String {
        "\(user.id)-\(action)"
    }
}
