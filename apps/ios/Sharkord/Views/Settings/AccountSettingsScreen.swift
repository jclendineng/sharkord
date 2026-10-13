import SwiftUI

struct AccountSettingsScreen: View {
    @Environment(SessionStore.self) private var session

    @State private var isEditPresented = false
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

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
        }
        .settingsListStyle()
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditPresented) {
            EditProfileSheet()
        }
    }

    private func editProfile() {
        isEditPresented = true
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
