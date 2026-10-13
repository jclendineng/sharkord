import Photos
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
    @State private var isEmojiPickerPresented = false
    // the attachment panel takes the keyboard's place, so the two never show together
    @State private var isAttachPanelOpen = false
    @State private var isPhotoPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var isCameraPresented = false
    @State private var isPollCreatorPresented = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @FocusState private var isFieldFocused: Bool
    @State private var recorder = VoiceMessageRecorder()

    @Environment(ServerListStore.self) private var servers

    private var uploadedFiles: [TemporaryFile] {
        attachments.compactMap(\.uploaded)
    }

    private var selectedAssetIds: Set<String> {
        Set(attachments.compactMap(\.assetId))
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
        VStack(spacing: 0) {
            composer

            if isAttachPanelOpen {
                attachmentPanel
            }
        }
        .animation(.snappy(duration: 0.25), value: isAttachPanelOpen)
        // runs on behind the keyboard, whose rounded top corners would otherwise show the
        // window's black
        .background(Theme.chatBackground.ignoresSafeArea())
        .sheet(isPresented: $isEmojiPickerPresented) {
            EmojiPickerView(includesCustom: false, onPick: insertEmoji)
        }
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
        .sheet(isPresented: $isPollCreatorPresented) {
            PollCreatorSheet(channelId: store.channelId)
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker(onCapture: importCapture)
                .ignoresSafeArea()
        }
        .onChange(of: photoSelection) { _, items in
            importPhotos(items)
        }
        .onChange(of: isFieldFocused) { _, isFocused in
            if isFocused {
                isAttachPanelOpen = false
            }
        }
        .onChange(of: store.editing) { _, message in
            if let message {
                text = HTMLText.plainText(from: message.content ?? "")
            }
        }
        .onChange(of: store.pendingInsert) { _, insert in
            guard let insert else {
                return
            }

            text += insert
            store.pendingInsert = nil
        }
    }

    // a poll is a message of its own, so not one inside a thread
    private var pollAction: (() -> Void)? {
        guard store.scope == .channel else {
            return nil
        }

        return openPollCreator
    }

    private var attachmentPanel: some View {
        AttachmentPanel(
            selectedIds: selectedAssetIds,
            canAddMore: attachments.count < maxFiles,
            onToggle: toggleAsset,
            onCamera: openCamera,
            onPhotos: openPhotoPicker,
            onPoll: pollAction,
            onFiles: openFileImporter,
            onClose: closeAttachPanel
        )
        .transition(.move(edge: .bottom))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.red)
            }

            if let mode = modeTitle {
                ModeBar(title: mode, onCancel: cancelMode)
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

            if recorder.isRecording {
                RecordingBar(recorder: recorder, onCancel: cancelRecording, onSend: sendRecording)
            } else {
                inputRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.chatBackground)
    }

    private var modeTitle: String? {
        if store.editing != nil {
            return "Editing message"
        }

        if let reply = store.replyingTo {
            let name = reply.userId.flatMap { session.usersById[$0]?.name } ?? "a message"

            return "Replying to \(name)"
        }

        return nil
    }

    // discord's row: attach, the field with emoji and the mic inside, send once there is text
    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if canUpload && store.editing == nil {
                // one plus turned into an x, a swapped symbol animates apart from the row as
                // it slides with the panel
                Button(action: toggleAttachPanel) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .rotationEffect(.degrees(isAttachPanelOpen ? 45 : 0))
                        .foregroundStyle(Theme.text)
                        .frame(width: 38, height: 38)
                        .background(Theme.inputBackground, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isAttachPanelOpen ? "Close Attachments" : "Attach")
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .focused($isFieldFocused)
                    .lineLimit(1...6)
                    .foregroundStyle(Theme.text)
                    .padding(.vertical, 9)

                Button("Emoji", systemImage: "face.smiling.inverse", action: openEmojiPicker)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(Theme.muted)
                    .padding(.bottom, 7)

                if canRecord {
                    Button("Voice Message", systemImage: "mic.fill", action: startRecording)
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 7)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .background(Theme.inputBackground, in: .rect(cornerRadius: 20))

            if canSend {
                Button("Send", systemImage: store.editing == nil ? "paperplane.fill" : "checkmark", action: send)
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

    // a voice message is a file, so it needs uploads, and there is nothing to record over text
    private var canRecord: Bool {
        canUpload && !hasText && attachments.isEmpty && store.editing == nil
    }

    private func openEmojiPicker() {
        isEmojiPickerPresented = true
    }

    private func insertEmoji(_ shortcode: String) {
        let entry = EmojiCatalog.find(shortcode)

        text += entry?.emoji ?? ":\(shortcode):"
    }

    private func toggleAttachPanel() {
        if isAttachPanelOpen {
            isAttachPanelOpen = false
            isFieldFocused = true
        } else {
            isFieldFocused = false
            isAttachPanelOpen = true
        }
    }

    private func closeAttachPanel() {
        isAttachPanelOpen = false
    }

    // the panel stays behind the sheet, so backing out of a poll lands back on it
    private func openPollCreator() {
        isPollCreatorPresented = true
    }

    private func openPhotoPicker() {
        isPhotoPickerPresented = true
    }

    private func openFileImporter() {
        isFileImporterPresented = true
    }

    private func openCamera() {
        guard attachments.count < maxFiles else {
            return
        }

        isCameraPresented = true
    }

    private func cancelMode() {
        if store.editing != nil {
            text = ""
        }

        store.editing = nil
        store.replyingTo = nil
    }

    // the call already holds the microphone
    private func startRecording() {
        guard servers.voiceSession == nil else {
            errorMessage = "Leave the voice channel to record a voice message."
            return
        }

        errorMessage = nil

        Task {
            do {
                try await recorder.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelRecording() {
        recorder.cancel()
    }

    // sent straight away like discord's, it goes up as an ordinary audio file
    private func sendRecording() {
        guard let url = recorder.finish() else {
            return
        }

        guard let address = session.address, let token = session.token else {
            return
        }

        isSending = true

        Task {
            do {
                let file = try await UploadAPI.upload(fileAt: url, name: "voice-message.m4a", to: address, token: token)

                try await store.send("", files: [file])
            } catch {
                errorMessage = error.localizedDescription
            }

            try? FileManager.default.removeItem(at: url)
            isSending = false
        }
    }

    private func send() {
        let draft = text
        let files = uploadedFiles

        isSending = true
        errorMessage = nil

        Task {
            do {
                if let editing = store.editing {
                    try await store.edit(editing, to: draft)
                } else {
                    try await store.send(draft, files: files)
                }

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

    // tapping a photo in the panel adds it to the message, tapping it again takes it back out
    private func toggleAsset(_ asset: PHAsset) {
        if let attachment = attachments.first(where: { $0.assetId == asset.localIdentifier }) {
            remove(attachment)
            return
        }

        var attachment = PendingAttachment(name: asset.mediaType == .video ? "Video" : "Photo")

        attachment.assetId = asset.localIdentifier
        attachments.append(attachment)

        Task {
            do {
                let url = try await PhotoLibrary.export(asset)

                await upload(attachment.id, fileURL: url)
            } catch {
                fail(attachment.id, error)
            }
        }
    }

    private func importCapture(_ url: URL) {
        let attachment = PendingAttachment(name: url.lastPathComponent)

        attachments.append(attachment)

        Task {
            await upload(attachment.id, fileURL: url)
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
    // the library photo it came from, so the panel can show it picked
    var assetId: String?

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

// what the composer is doing besides a new message, replying or editing, with a way out
private struct ModeBar: View {
    let title: String
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)

            Spacer()

            Button("Cancel", systemImage: "xmark.circle.fill", action: onCancel)
                .labelStyle(.iconOnly)
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 4)
    }
}

private struct RecordingBar: View {
    let recorder: VoiceMessageRecorder
    let onCancel: () -> Void
    let onSend: () -> Void

    private var elapsedText: String {
        let seconds = Int(recorder.elapsed)

        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button("Cancel", systemImage: "trash.fill", action: onCancel)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(Theme.red)
                .frame(width: 38, height: 38)

            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.red)
                    .frame(width: 8, height: 8)

                Text(elapsedText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.header)

                HStack(alignment: .center, spacing: 2) {
                    ForEach(Array(recorder.levels.enumerated()), id: \.offset) { _, level in
                        Capsule()
                            .fill(Theme.blurple)
                            .frame(width: 3, height: max(3, CGFloat(level) * 26))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 28, alignment: .trailing)
                .clipped()
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Theme.inputBackground, in: .rect(cornerRadius: 20))

            Button("Send Voice Message", systemImage: "arrow.up", action: onSend)
                .labelStyle(.iconOnly)
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Theme.blurple, in: .circle)
        }
    }
}

