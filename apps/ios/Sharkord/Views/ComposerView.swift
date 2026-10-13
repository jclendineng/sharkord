import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    let placeholder: String
    let canUpload: Bool
    let store: ChannelMessagesStore

    @Environment(SessionStore.self) private var session

    @State private var text = ""
    @State private var attachments: [PendingAttachment] = []
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isPhotoPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var isEmojiPickerPresented = false

    private var uploadedFiles: [TemporaryFile] {
        attachments.compactMap(\.uploaded)
    }

    private var isUploading: Bool {
        attachments.contains { $0.state == .uploading }
    }

    private var maxFiles: Int {
        session.settings?.storageMaxFilesPerMessage ?? 0
    }

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        !isSending && !isUploading && (hasText || !uploadedFiles.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.red)
            }

            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            AttachmentChip(attachment: attachment, onRemove: { remove(attachment) })
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                if canUpload {
                    attachMenu
                }

                HStack(alignment: .bottom, spacing: 4) {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(1...6)
                        .foregroundStyle(Theme.text)
                        .padding(.vertical, 9)

                    Button("Emoji", systemImage: "face.smiling.inverse", action: openEmojiPicker)
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 7)
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .background(Theme.inputBackground, in: .rect(cornerRadius: 20))

                if canSend {
                    Button("Send", systemImage: "paperplane.fill", action: send)
                        .labelStyle(.iconOnly)
                        .font(.body)
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Theme.blurple, in: .circle)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.2), value: canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.chatBackground)
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $photoSelection,
            maxSelectionCount: max(1, maxFiles - attachments.count),
            matching: .any(of: [.images, .videos])
        )
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: importFiles
        )
        .sheet(isPresented: $isEmojiPickerPresented) {
            EmojiPickerView(includesCustom: false, onPick: insertEmoji)
        }
        .onChange(of: photoSelection) { _, items in
            importPhotos(items)
        }
    }

    private var attachMenu: some View {
        Menu {
            Button("Photo Library", systemImage: "photo.on.rectangle", action: openPhotoPicker)
            Button("Files", systemImage: "folder", action: openFileImporter)
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 38, height: 38)
                .background(Theme.inputBackground, in: .circle)
        }
        .disabled(attachments.count >= maxFiles)
    }

    private func openPhotoPicker() {
        isPhotoPickerPresented = true
    }

    private func openFileImporter() {
        isFileImporterPresented = true
    }

    private func openEmojiPicker() {
        isEmojiPickerPresented = true
    }

    private func insertEmoji(_ shortcode: String) {
        let entry = EmojiCatalog.find(shortcode)

        text += entry?.emoji ?? ":\(shortcode):"
    }

    private func send() {
        let draft = text
        let files = uploadedFiles

        isSending = true
        errorMessage = nil

        Task {
            do {
                try await store.send(draft, files: files)
                text = ""
                attachments = []
            } catch {
                errorMessage = error.localizedDescription
            }

            isSending = false
        }
    }

    private func remove(_ attachment: PendingAttachment) {
        attachments.removeAll { $0.id == attachment.id }

        if let uploaded = attachment.uploaded {
            Task { await session.deleteTemporaryFile(uploaded) }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else {
            return
        }

        photoSelection = []

        for item in items {
            let attachment = PendingAttachment(name: "Photo")

            attachments.append(attachment)

            Task {
                do {
                    guard let picked = try await item.loadTransferable(type: PickedMedia.self) else {
                        throw AuthAPI.RequestError(message: "That item could not be loaded.")
                    }

                    await upload(attachment.id, fileURL: picked.url)
                } catch {
                    fail(attachment.id, error)
                }
            }
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            return
        }

        for url in urls.prefix(max(0, maxFiles - attachments.count)) {
            let attachment = PendingAttachment(name: url.lastPathComponent)

            attachments.append(attachment)

            // files from the picker live outside the sandbox, so copy them while access is granted
            let accessing = url.startAccessingSecurityScopedResource()
            let copy = try? TemporaryCopy.make(of: url)

            if accessing {
                url.stopAccessingSecurityScopedResource()
            }

            Task {
                if let copy {
                    await upload(attachment.id, fileURL: copy)
                } else {
                    fail(attachment.id, AuthAPI.RequestError(message: "That file could not be read."))
                }
            }
        }
    }

    private func upload(_ id: UUID, fileURL: URL) async {
        guard let address = session.address, let token = session.token else {
            return
        }

        let name = fileURL.lastPathComponent

        update(id) { $0.name = name }

        do {
            let uploaded = try await UploadAPI.upload(fileAt: fileURL, name: name, to: address, token: token)

            update(id) { $0.state = .uploaded(uploaded) }
        } catch {
            fail(id, error)
        }

        try? FileManager.default.removeItem(at: fileURL)
    }

    private func fail(_ id: UUID, _ error: Error) {
        update(id) { $0.state = .failed }
        errorMessage = error.localizedDescription
    }

    private func update(_ id: UUID, _ change: (inout PendingAttachment) -> Void) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else {
            return
        }

        change(&attachments[index])
    }
}

struct PendingAttachment: Identifiable, Equatable {
    enum State: Equatable {
        case uploading
        case uploaded(TemporaryFile)
        case failed
    }

    let id = UUID()
    var name: String
    var state: State = .uploading

    var uploaded: TemporaryFile? {
        if case .uploaded(let file) = state {
            return file
        }

        return nil
    }
}

private struct AttachmentChip: View {
    let attachment: PendingAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            switch attachment.state {
            case .uploading:
                ProgressView()
                    .controlSize(.small)
            case .uploaded:
                Image(systemName: "doc.fill")
                    .foregroundStyle(Theme.blurple)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.red)
            }

            Text(attachment.name)
                .font(.caption)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .frame(maxWidth: 140)

            Button("Remove", systemImage: "xmark.circle.fill", action: onRemove)
                .labelStyle(.iconOnly)
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.listBackground, in: .rect(cornerRadius: 8))
    }
}

// photos come out of the picker as a file that is deleted when the import closure returns
private nonisolated struct PickedMedia: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            PickedMedia(url: try TemporaryCopy.make(of: received.file))
        }

        FileRepresentation(importedContentType: .image) { received in
            PickedMedia(url: try TemporaryCopy.make(of: received.file))
        }
    }
}

private nonisolated enum TemporaryCopy {
    static func make(of url: URL) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let target = directory.appending(path: url.lastPathComponent)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: target)

        return target
    }
}
