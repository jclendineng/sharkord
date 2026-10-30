import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// stickers.add, update and delete. the list itself comes from the session, which every member
// gets on join and the sticker events keep current. bounds from packages/shared statics/stickers.ts
struct StickersScreen: View {
    private static let nameRange = 2...30
    private static let maxFileSize = 512 * 1024

    @Environment(SessionStore.self) private var session

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isImporterPresented = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var editing: Sticker?
    @State private var newName = ""
    @State private var newDescription = ""

    var body: some View {
        SettingsForm {
            Section {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                    Label("Add from Photos", systemImage: "photo.on.rectangle")
                }
                .disabled(isUploading)

                Button(action: showImporter) {
                    Label("Add from Files", systemImage: "folder")
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
                Text("PNG, APNG, GIF or WebP, 512 KB at most. Everyone on the server can send them.")
                    .wrappingFooter()
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.redText)
                }
            }

            if !session.stickers.isEmpty {
                Section("\(session.stickers.count) Stickers") {
                    ForEach(session.stickers) { sticker in
                        Button {
                            startEditing(sticker)
                        } label: {
                            StickerRow(sticker: sticker)
                        }
                        // the whole row, where a mac form's push button drew a box inside it
                        .buttonStyle(.plain)
                        .rowDeleteAction {
                            delete(sticker)
                        }
                    }
                }
            }
        }
        .settingsListStyle()
        .navigationTitle("Stickers")
        .inlineNavigationTitle()
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.png, .gif, .webP],
            allowsMultipleSelection: true,
            onCompletion: importFiles
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else {
                return
            }

            importPhotos(items)
        }
        .alert("Edit Sticker", isPresented: isEditing) {
            TextField("Name", text: $newName)
            TextField("Description", text: $newDescription)
            Button("Save", action: saveEdit)
            Button("Cancel", role: .cancel) {}
        }
    }

    private var isEditing: Binding<Bool> {
        Binding(
            get: { editing != nil },
            set: { if !$0 { editing = nil } }
        )
    }

    // named after its file to start with, padded when that is too short
    private static func stickerName(_ raw: String) -> String {
        let base = raw.trimmingCharacters(in: .whitespaces)
        let padded = base.count >= nameRange.lowerBound ? base : "\(base)sticker"

        return String(padded.prefix(nameRange.upperBound))
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

                    return (copy, Self.stickerName(url.deletingPathExtension().lastPathComponent))
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
                files.append((url, "sticker_\(index + 1)"))
            }

            return files
        }
    }

    private func upload(_ collect: @escaping () async throws -> [(URL, String)]) {
        struct NewSticker: Encodable {
            let fileId: String
            let name: String
        }

        guard let address = session.address, let token = session.token else {
            return
        }

        isUploading = true
        errorMessage = nil

        Task {
            var files: [(URL, String)] = []

            do {
                files = try await collect()

                for (url, name) in files {
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

                    guard size <= Self.maxFileSize else {
                        throw AuthAPI.RequestError(message: "\(url.lastPathComponent) is over 512 KB, the most a sticker can be.")
                    }

                    let file = try await UploadAPI.upload(fileAt: url, name: url.lastPathComponent, to: address, token: token)
                    let _: Int = try await session.perform("stickers.add", NewSticker(fileId: file.id, name: name))
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            for (url, _) in files {
                try? FileManager.default.removeItem(at: url)
            }

            isUploading = false
        }
    }

    private func startEditing(_ sticker: Sticker) {
        newName = sticker.name
        newDescription = sticker.description ?? ""
        editing = sticker
    }

    private func saveEdit() {
        struct UpdateInput: Encodable {
            let stickerId: Int
            let name: String
            let description: String
        }

        guard let sticker = editing else {
            return
        }

        let input = UpdateInput(
            stickerId: sticker.id,
            name: newName.trimmingCharacters(in: .whitespaces),
            description: newDescription.trimmingCharacters(in: .whitespaces)
        )

        Task {
            do {
                try await session.perform("stickers.update", input)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ sticker: Sticker) {
        Task {
            do {
                try await session.perform("stickers.delete", ["stickerId": sticker.id])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct StickerRow: View {
    let sticker: Sticker

    @Environment(SessionStore.self) private var session

    var body: some View {
        HStack(spacing: 12) {
            AnimatedImage(url: session.address?.fileURL(sticker.file), maxPointSize: 56, contentMode: .fit)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(sticker.name)
                    .foregroundStyle(Theme.header)

                if let description = sticker.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .contentShape(.rect)
    }
}
