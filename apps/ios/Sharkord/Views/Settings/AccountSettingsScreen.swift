import SwiftUI

struct AccountSettingsScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @State private var isEditPresented = false
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var deletePassword = ""
    @State private var wipesMessages = false
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?
    @State private var isDeleting = false

    private var canDelete: Bool {
        !isDeleting && (!session.ownUserHasPassword || !deletePassword.isEmpty)
    }

    private var canChangePassword: Bool {
        currentPassword.count >= 4 && newPassword.count >= 4 && newPassword == confirmPassword && !isSaving
    }

    var body: some View {
        List {
            Section("Profile") {
                HStack(spacing: 12) {
                    AvatarView(user: session.ownUser, size: 44, showsStatus: true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.ownUser?.name ?? "")
                            .font(.headline)
                            .foregroundStyle(Theme.header)

                        Text(session.displayName)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }

                Button("Edit Profile", action: editProfile)
            }

            Section {
                SecureField("Current password", text: $currentPassword)
                    .textContentType(.password)
                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirmPassword)
                    .textContentType(.newPassword)

                if !confirmPassword.isEmpty && newPassword != confirmPassword {
                    Text("The new passwords do not match.")
                        .foregroundStyle(Theme.red)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                }

                Button(action: changePassword) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Change Password")
                    }
                }
                .disabled(!canChangePassword)
            } header: {
                Text("Password")
            } footer: {
                Text("Changing your password logs you out on every device, this one included.")
            }

            if session.ownUserHasPassword {
                TwoFactorSection()
            }

            Section {
                if session.ownUserHasPassword {
                    SecureField("Password", text: $deletePassword)
                        .textContentType(.password)
                }

                Toggle("Delete my messages too", isOn: $wipesMessages)

                if let deleteError {
                    Text(deleteError)
                        .foregroundStyle(Theme.red)
                }

                Button(role: .destructive, action: askToDelete) {
                    if isDeleting {
                        ProgressView()
                    } else {
                        Text("Delete Account")
                    }
                }
                .disabled(!canDelete)
            } header: {
                Text("Delete Account")
            } footer: {
                Text(wipesMessages
                    ? "Your account, messages, reactions and uploads are removed from this server. This can't be undone."
                    : "Your account is removed from this server and your messages stay as Deleted User. This can't be undone.")
            }
        }
        .confirmationDialog("Delete your account on this server?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive, action: deleteAccount)
        } message: {
            Text("This can't be undone.")
        }
        .settingsListStyle()
        .navigationTitle("Account")
        .inlineNavigationTitle()
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .sheet(isPresented: $isEditPresented) {
            EditProfileSheet()
                .environment(session)
                .environment(servers)
                .appSheet()
        }
    }

    private func editProfile() {
        isEditPresented = true
    }

    private func askToDelete() {
        isConfirmingDelete = true
    }

    private func deleteAccount() {
        isDeleting = true
        deleteError = nil

        Task {
            do {
                try await session.deleteOwnAccount(password: session.ownUserHasPassword ? deletePassword : nil, wipe: wipesMessages)
            } catch {
                deleteError = error.localizedDescription
            }

            isDeleting = false
        }
    }

    private func changePassword() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await session.changePassword(current: currentPassword, new: newPassword)
            } catch {
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }
}
