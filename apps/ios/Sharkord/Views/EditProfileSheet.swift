import PhotosUI
import SwiftUI

// users.update for the name, bio and profile color, users.changeAvatar and changeBanner for the
// pictures, each of which can be removed again
struct EditProfileSheet: View {
    // the server's limit for a bio
    private static let bioLimit = 160

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var bio = ""
    @State private var color = Color(hex: "#5865F2")
    @State private var avatarItem: PhotosPickerItem?
    @State private var bannerItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var isSaving = false
    // saved or discarded, so closing does not ask again
    @State private var isLeaving = false
    @State private var isConfirmingDiscard = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && bio.count <= Self.bioLimit && !isSaving
    }

    // the pictures upload as soon as they are picked, only the fields wait for Save
    private var hasUnsavedChanges: Bool {
        guard let user = session.ownUser, !isLeaving else {
            return false
        }

        return name != user.name
            || bio != (user.bio ?? "")
            || color.hexString != Color(hex: user.profileColor).hexString
    }

    var body: some View {
        NavigationStack {
            SettingsForm {
                Section {
                    // discord's profile header: the banner, the avatar over its bottom edge
                    ZStack(alignment: .bottomLeading) {
                        PhotosPicker(selection: $bannerItem, matching: .images) {
                            banner
                                .frame(height: 120)
                                .frame(maxWidth: .infinity)
                                .clipShape(.rect(cornerRadius: 14))
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "photo.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(8)
                                        .background(.black.opacity(0.5), in: .circle)
                                        .padding(8)
                                }
                                .padding(.bottom, 44)
                        }
                        .accessibilityLabel("Change Banner")

                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            AvatarView(user: session.ownUser, size: 88)
                                .padding(5)
                                .background(Theme.deepBackground, in: .circle)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "camera.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(7)
                                        .background(Theme.blurple, in: .circle)
                                }
                        }
                        .accessibilityLabel("Change Avatar")
                        .padding(.leading, 16)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if session.ownUser?.avatar != nil || session.ownUser?.banner != nil {
                    Section {
                        if session.ownUser?.avatar != nil {
                            Button("Remove Avatar", role: .destructive, action: removeAvatar)
                        }

                        if session.ownUser?.banner != nil {
                            Button("Remove Banner", role: .destructive, action: removeBanner)
                        }
                    }
                }

                Section("Display Name") {
                    TextField("", text: $name, prompt: Text("Name"))
                        .labelsHidden()
                        .noAutocapitalization()
                }

                Section {
                    TextField("", text: $bio, prompt: Text("Tell people about yourself"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(3...6)
                } header: {
                    Text("About Me")
                } footer: {
                    Text("\(bio.count)/\(Self.bioLimit)")
                        .monospacedDigit()
                        .foregroundStyle(bio.count > Self.bioLimit ? Theme.red : Theme.muted)
                        .wrappingFooter()
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
            // a mac lays a plain form out in two columns with the labels right aligned. grouped
            // is a phone's own anyway
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.deepBackground)
            .navigationTitle("Edit Profile")
            .inlineNavigationTitle()
            .toolbar {
                ActionToolbarItem(placement: .cancellationAction) {
                    // on the button, which the question points at as it opens
                    Button("Cancel", action: close)
                        .confirmationDialog("Discard your changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                            Button("Discard Changes", role: .destructive, action: discard)
                        }
                }

                ActionToolbarItem(placement: .confirmationAction) {
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
                    upload(item, as: .avatar)
                }
            }
            .onChange(of: bannerItem) { _, item in
                if let item {
                    upload(item, as: .banner)
                }
            }
        }
        .presentationBackground(Theme.deepBackground)
        // edits are not dropped by a stray swipe: it springs back, and Cancel asks first. ios 27's
        // dismissalConfirmationDialog would ask on the swipe too, but never showed on 27.1
        .interactiveDismissDisabled(hasUnsavedChanges)
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
                isLeaving = true
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }

    @ViewBuilder
    private var banner: some View {
        if let file = session.ownUser?.banner, let address = session.address {
            CachedFileImage(file: file, url: address.fileURL(file)) {
                color
            }
        } else {
            color
        }
    }

    // the picker hands over data, the upload endpoint streams a file, so it goes through tmp
    private func upload(_ item: PhotosPickerItem, as kind: SessionStore.ProfileImage) {
        change(kind) {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AuthAPI.RequestError(message: "Could not read that picture.")
            }

            let fileURL = FileManager.default.temporaryDirectory.appending(path: "\(kind == .avatar ? "avatar" : "banner")-\(UUID().uuidString).jpg")

            try data.write(to: fileURL)

            return fileURL
        }
    }

    private func removeAvatar() {
        change(.avatar) { nil }
    }

    private func removeBanner() {
        change(.banner) { nil }
    }

    private func change(_ kind: SessionStore.ProfileImage, file: @escaping () async throws -> URL?) {
        isSaving = true
        errorMessage = nil

        Task {
            var fileURL: URL?

            do {
                fileURL = try await file()
                try await session.changeProfileImage(kind, fileAt: fileURL)
            } catch {
                errorMessage = error.localizedDescription
            }

            if let fileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }

            avatarItem = nil
            bannerItem = nil
            isSaving = false
        }
    }

    private func discard() {
        isLeaving = true
        dismiss()
    }

    private func close() {
        if hasUnsavedChanges {
            isConfirmingDiscard = true
            return
        }

        dismiss()
    }
}
