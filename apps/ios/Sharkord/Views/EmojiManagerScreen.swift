import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// the server's custom emoji: add some from photos, a whole pack from files, rename or delete
// them. the server refuses anyone without permission to manage emoji
// the sheet from the server sheet's emoji section
struct EmojiManagerScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EmojiManagerList()
                .toolbar {
                    ActionToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: close)
                    }
                }
        }
        .presentationBackground(Theme.deepBackground)
    }

    private func close() {
        dismiss()
    }
}

// also pushed from server settings
struct EmojiManagerList: View {
    // emojis.add and emojis.update accept up to this many characters
    private static let nameLimit = 32

    @Environment(SessionStore.self) private var session

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isImporterPresented = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var renaming: CustomEmoji?
    @State private var newName = ""

    var body: some View {
        SettingsForm {
            Section {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 50, matching: .images) {
                    Label("Add from Photos", systemImage: "photo.on.rectangle")
                }
                .disabled(isUploading)

                Button(action: showImporter) {
                    Label("Add Emoji Pack from Files", systemImage: "folder")
                }
                .disabled(isUploading)

                if isUploading {
                    HStack(spacing: 10) {
                        ProgressView()

                        Text("Uploading…")
                            .foregroundStyle(Theme.muted)
                    }
                }
            } footer: {
                Text("A pack is a set of images picked together, each named after its file. Square PNGs look best.")
                    .wrappingFooter()
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.redText)
                }
            }

            if !session.customEmojis.isEmpty {
                Section("\(session.customEmojis.count) Emoji") {
                    ForEach(session.customEmojis) { emoji in
                        Button(action: { startRenaming(emoji) }) {
                            EmojiRow(emoji: emoji)
                        }
                        // the whole row, where a mac form's push button drew a box inside it
                        .buttonStyle(.plain)
                        .rowDeleteAction {
                            delete(emoji)
                        }
                    }
                }
            }
        }
        .settingsListStyle()
        .navigationTitle("Server Emoji")
        .inlineNavigationTitle()
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.png, .jpeg, .gif, .webP, .image],
            allowsMultipleSelection: true,
            onCompletion: importFiles
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else {
                return
            }

            importPhotos(items)
        }
        .alert("Rename Emoji", isPresented: isRenaming) {
            TextField("Name", text: $newName)
                .noAutocapitalization()
                .autocorrectionDisabled()

            Button("Save", action: saveRename)
            Button("Cancel", role: .cancel) {}
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )
    }

    // the same rules emoji shortcodes follow everywhere: letters, digits and underscores
    private static func emojiName(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "[^A-Za-z0-9_]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        return String((cleaned.isEmpty ? "emoji" : cleaned).prefix(nameLimit))
    }

    private func showImporter() {
        isImporterPresented = true
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            upload {
                try urls.map { url in
                    let isScoped = url.startAccessingSecurityScopedResource()

                    defer {
                        if isScoped {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }

                    // the picked file is only readable while access lasts, the upload happens later
                    let copy = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")

                    try FileManager.default.copyItem(at: url, to: copy)

                    return (copy, Self.emojiName(url.deletingPathExtension().lastPathComponent))
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        photoItems = []

        upload {
            var files: [(URL, String)] = []

            for (index, item) in items.enumerated() {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }

                let type = item.supportedContentTypes.first { $0.conforms(to: .image) }
                let fileExtension = type?.preferredFilenameExtension ?? "png"
                let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).\(fileExtension)")

                try data.write(to: url)
                files.append((url, "emoji_\(index + 1)"))
            }

            return files
        }
    }

    private func upload(_ collect: @escaping () async throws -> [(URL, String)]) {
        isUploading = true
        errorMessage = nil

        Task {
            var files: [(URL, String)] = []

            do {
                files = try await collect()
                try await session.addEmojis(files.map { (fileURL: $0.0, name: $0.1) })
            } catch {
                errorMessage = error.localizedDescription
            }

            for (url, _) in files {
                try? FileManager.default.removeItem(at: url)
            }

            isUploading = false
        }
    }

    private func startRenaming(_ emoji: CustomEmoji) {
        newName = emoji.name
        renaming = emoji
    }

    private func saveRename() {
        guard let emoji = renaming else {
            return
        }

        let name = Self.emojiName(newName)

        Task {
            do {
                try await session.renameEmoji(emoji.id, to: name)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ emoji: CustomEmoji) {
        Task {
            do {
                try await session.deleteEmoji(emoji.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

}

private struct EmojiRow: View {
    let emoji: CustomEmoji

    @Environment(SessionStore.self) private var session

    var body: some View {
        HStack(spacing: 12) {
            if let address = session.address {
                CachedFileImage(file: emoji.file, url: address.fileURL(emoji.file), contentMode: .fit) {
                    Color.clear
                }
                .frame(width: 32, height: 32)
            }

            Text(":\(emoji.name):")
                .foregroundStyle(Theme.header)

            Spacer()
        }
        .contentShape(.rect)
    }
}
