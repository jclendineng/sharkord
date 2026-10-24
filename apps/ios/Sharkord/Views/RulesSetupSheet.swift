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
    @State private var closesOtherChannels = true
    @State private var removesDefaultRole = true
    @State private var defaultRoleName: String?
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
                    Text("New members land here, the only channel they can see, until they react.")
                }

                Section {
                    Toggle("Close Other Channels to New Members", isOn: $closesOtherChannels)
                } footer: {
                    Text("Makes every other public channel private, open to every role except the one new members start with. Channels already private keep their own permissions.")
                }

                if let defaultRoleName {
                    Section {
                        Toggle("Take Away \(defaultRoleName) Once They React", isOn: $removesDefaultRole)
                    } footer: {
                        Text("For a role that only means someone has not accepted the rules yet. Leave it off if \(defaultRoleName) gives permissions members need.")
                    }
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
            .listHoverHighlight()
            .background(Theme.deepBackground)
            .navigationTitle("Rules Message")
            .inlineNavigationTitle()
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
        .sheetDetents([.medium, .large])
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
            defaultRoleName = loaded.first { $0.isDefault }?.name
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
            let closeOtherChannels: Bool
            let removeDefaultRole: Bool
        }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await session.perform(
                    "others.setOnboarding",
                    OnboardingInput(
                        messageId: messageId,
                        roleId: roleId,
                        giveExistingMembers: givesExistingMembers,
                        closeOtherChannels: closesOtherChannels,
                        removeDefaultRole: removesDefaultRole && defaultRoleName != nil
                    )
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
