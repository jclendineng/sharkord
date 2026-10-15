import SwiftUI

// the new member lounge: this message holds the rules, and reacting to it gives a role. open the
// server's other channels to that role, and close them to everyone else, so a new member sees
// only the rules until they accept them
struct RulesSetupSheet: View {
    let messageId: Int

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var roles: [AdminRole] = []
    @State private var roleId: Int?
    @State private var givesExistingMembers = true
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Role", selection: $roleId) {
                        Text("Choose a role").tag(Int?.none)

                        ForEach(roles) { role in
                            Text(role.name).tag(Int?.some(role.id))
                        }
                    }
                } header: {
                    Text("Reacting Gives")
                } footer: {
                    Text("Then open the server's channels to this role in each channel's permissions, and hide them from everyone else. New members land here, the only channel they can see, until they react.")
                }

                Section {
                    Toggle("Give it to everyone already here", isOn: $givesExistingMembers)
                } footer: {
                    Text("Without it, members who joined before the rules lose the channels you close.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.deepBackground)
            .navigationTitle("Rules Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .disabled(roleId == nil)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.deepBackground)
        .task {
            await loadRoles()
        }
    }

    // the owner's role and the one every member starts with would gate nothing
    private func loadRoles() async {
        do {
            let loaded: [AdminRole] = try await session.request("roles.getAll")

            roles = loaded.filter { $0.id != 1 && !$0.isDefault }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let roleId else {
            return
        }

        struct OnboardingInput: Encodable {
            let messageId: Int
            let roleId: Int
            let giveExistingMembers: Bool
        }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await session.perform(
                    "others.setOnboarding",
                    OnboardingInput(messageId: messageId, roleId: roleId, giveExistingMembers: givesExistingMembers)
                )
                isSaving = false
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func close() {
        dismiss()
    }
}
