import PhotosUI
import SwiftUI

// users.update for the name, bio and profile color, users.changeAvatar for the picture
struct EditProfileSheet: View {
    // the server's limit for a bio
    private static let bioLimit = 160

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var bio = ""
    @State private var color = Color(hex: "#5865F2")
    @State private var avatarItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && bio.count <= Self.bioLimit && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()

                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            AvatarView(user: session.ownUser, size: 88)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "camera.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(7)
                                        .background(Theme.blurple, in: .circle)
                                }
                        }

                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Display Name") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    TextField("Tell people about yourself", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("About Me")
                } footer: {
                    Text("\(bio.count)/\(Self.bioLimit)")
                        .foregroundStyle(bio.count > Self.bioLimit ? Theme.red : Theme.muted)
                }

                Section("Profile Color") {
                    ColorPicker("Banner color", selection: $color, supportsOpacity: false)
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
            .navigationTitle("Edit Profile")
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
                            .disabled(!canSave)
                    }
                }
            }
            .onAppear(perform: fill)
            .onChange(of: avatarItem) { _, item in
                if let item {
                    uploadAvatar(item)
                }
            }
        }
        .presentationBackground(Theme.deepBackground)
    }

    private func fill() {
        guard let user = session.ownUser else {
            return
        }

        name = user.name
        bio = user.bio ?? ""
        color = Color(hex: user.profileColor)
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await session.updateProfile(
                    name: name.trimmingCharacters(in: .whitespaces),
                    bio: bio,
                    profileColor: color.hexString
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }

    // the picker hands over data, the upload endpoint streams a file, so it goes through tmp
    private func uploadAvatar(_ item: PhotosPickerItem) {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw AuthAPI.RequestError(message: "Could not read that picture.")
                }

                let fileURL = FileManager.default.temporaryDirectory.appending(path: "avatar-\(UUID().uuidString).jpg")

                try data.write(to: fileURL)

                defer {
                    try? FileManager.default.removeItem(at: fileURL)
                }

                try await session.changeAvatar(fileAt: fileURL, name: "avatar.jpg")
            } catch {
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }

    private func close() {
        dismiss()
    }
}
