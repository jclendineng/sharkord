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
    // the attachment panel takes the keyboard's place, so the two never show together
    @State private var isPhotoPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var isCameraPresented = false
    @State private var isPollCreatorPresented = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @FocusState private var isFieldFocused: Bool
    @State private var recorder = VoiceMessageRecorder()

    @Environment(ServerListStore.self) private var servers
    @Environment(\.expandChat) private var expandChat

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
        // the composer rides on the panel the way it rides on the keyboard
        VStack(spacing: 0) {
            // ahead of the buttons once the finger moves, so a swipe across the emoji or the
            // mic button drags the panel instead of pressing them, taps still reach them
            composer
                .highPriorityGesture(panelDrag, including: store.attachPanel.isOpen ? .all : .subviews)
                // sits over the bottom of the messages, so it coming and going moves nothing
                .overlay(alignment: .top) {
                    TypingIndicator(place: store.typingPlace)
                        .alignmentGuide(.top) { $0[.bottom] }
                        .allowsHitTesting(false)
                }

            // laid out right under the composer so the two move as one, whatever the panel
            // grows to past its resting height is drawn up over the composer
            if store.attachPanel.isOpen {
                openPanel
                    .frame(height: AttachPanelModel.restingHeight, alignment: .bottom)
                    .transition(.move(edge: .bottom))
                    // escape puts it away on a mac, as it does a menu
                    .background {
                        Button("Close Panel", action: closePanel)
                            .keyboardShortcut(.cancelAction)
                            .hidden()
                    }
            }
        }
        // the mac's picker rises over the conversation above the box, its bottom at the box's top
        .overlay(alignment: .topTrailing) {
            if store.attachPanel.isPickerOpen {
                ExpressionPicker(
                    model: store.attachPanel,
                    onEmoji: insertEmoji,
                    onBackspace: deleteBackward,
                    onGif: sendGif,
                    onSticker: sendSticker
                )
                .padding(.trailing, 12)
                // its own height and a little more up from the box's top, so it sits just above
                .offset(y: -(ExpressionPicker.height + 6))
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
                // escape puts it away, as it does discord's
                .background {
                    Button("Close Picker", action: closePicker)
                        .keyboardShortcut(.cancelAction)
                        .hidden()
                }
            }
        }
        .animation(.snappy(duration: 0.18), value: store.attachPanel.isPickerOpen)
        .modifier(PanelSlide(model: store.attachPanel))
        // runs on behind the keyboard, whose rounded top corners would otherwise show the
        // window's black
        .background(Theme.chatBackground.ignoresSafeArea())
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
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .sheet(isPresented: $isPollCreatorPresented) {
            PollCreatorSheet(channelId: store.channelId)
                .environment(session)
                .environment(servers)
                .appSheet()
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker(onCapture: importCapture)
                .ignoresSafeArea()
                .environment(session)
                .environment(servers)
        }
        .onChange(of: photoSelection) { _, items in
            importPhotos(items)
        }
        // leaving for another screen, the channel's own among them, drops the field's focus, or
        // swiftui gives it back on the way back and the keyboard comes up unasked
        .onDisappear(perform: unfocusField)
        // a tap on the field while the panel is up hands over to the keyboard
        .onChange(of: isFieldFocused) { _, isFocused in
            // on an ipad the keyboard wants the whole width, the list beside the chat gives way
            if isFocused, let expandChat {
                expandChat()
            }

            if isFocused && store.attachPanel.isOpen && !store.attachPanel.isHandingOff {
                store.attachPanel.beginHandoffToKeyboard()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            if store.attachPanel.isHandingOff && store.attachPanel.isOpen {
                store.attachPanel.finishHandoffToKeyboard()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            if store.attachPanel.isHandingOff && store.attachPanel.isOpen {
                store.attachPanel.finishHandoffToPanel()
            }

            store.attachPanel.endSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification), perform: keyboardWillChange)
        // typing more than was there, not the field being cleared or a draft being loaded
        .onChange(of: text) { old, new in
            if new.count > old.count && store.editing == nil {
                session.signalTyping(channelId: store.channelId, parentMessageId: store.typingPlace.parentMessageId)
            }
        }
        .onChange(of: store.editing) { _, message in
            if let message {
                text = HTMLText.markdown(from: message.content ?? "")
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

    private var areAttachmentsOpen: Bool {
        store.attachPanel.isOpen && store.attachPanel.kind == .attachments
    }

    private var areExpressionsOpen: Bool {
        store.attachPanel.isOpen && store.attachPanel.kind == .expressions
    }

    // the buttons turn back the moment the keyboard starts sliding up over the panel, not once
    // the handoff has finished and the panel has actually closed under it
    private var isPanelShown: Bool {
        store.attachPanel.isOpen && !store.attachPanel.isCoveredByKeyboard
    }

    private var showsCloseAttachments: Bool {
        isPanelShown && store.attachPanel.kind == .attachments
    }

    private var showsKeyboardButton: Bool {
        isPanelShown && store.attachPanel.kind == .expressions
    }

    @ViewBuilder
    private var openPanel: some View {
        switch store.attachPanel.kind {
        case .attachments:
            attachmentPanel
        case .expressions:
            ExpressionPanel(
                model: store.attachPanel,
                onEmoji: insertEmoji,
                onBackspace: deleteBackward,
                onGif: sendGif,
                onSticker: sendSticker
            )
        }
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
            model: store.attachPanel
        )
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
            if canUpload && store.editing == nil && ProcessInfo.processInfo.isiOSAppOnMac {
                // discord's mac: a short menu by the plus, not the phone's panel of photos
                Menu {
                    Button("Upload a File", systemImage: "doc", action: openFileImporter)
                    Button("Photos", systemImage: "photo.on.rectangle", action: openPhotoPicker)

                    if let pollAction {
                        Button("Create Poll", systemImage: "chart.bar.xaxis", action: pollAction)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 38, height: 38)
                        .background(Theme.inputBackground, in: .circle)
                        .hoverPop()
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("Attach")
            } else if canUpload && store.editing == nil {
                // one plus turned into an x, a swapped symbol animates apart from the row as
                // it slides with the panel
                Button(action: toggleAttachPanel) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .rotationEffect(.degrees(showsCloseAttachments ? 45 : 0))
                        .foregroundStyle(Theme.text)
                        .frame(width: 38, height: 38)
                        .background(Theme.inputBackground, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsCloseAttachments ? "Close Attachments" : "Attach")
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .focused($isFieldFocused)
                    .lineLimit(1...6)
                    .foregroundStyle(Theme.text)
                    .padding(.vertical, 9)

                if ProcessInfo.processInfo.isiOSAppOnMac {
                    // discord's mac: gifs, stickers and emoji each a button in the box
                    HStack(spacing: 12) {
                        ExpressionButton(title: "GIFs", action: openGifs) {
                            Text("GIF")
                                .font(.system(size: 10, weight: .heavy))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(lineWidth: 1.6)
                                }
                        }

                        ExpressionButton(title: "Stickers", action: openStickers) {
                            Image(systemName: "note.text")
                                .font(.system(size: 18, weight: .semibold))
                        }

                        FunEmojiButton(action: openEmoji)
                    }
                    .padding(.bottom, 8)
                } else {
                    // discord's emoji button turns into a keyboard one while the panel is up
                    Button(
                        showsKeyboardButton ? "Keyboard" : "Emoji",
                        systemImage: showsKeyboardButton ? "keyboard" : "face.smiling.inverse",
                        action: toggleExpressions
                    )
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 7)
                }

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

    // while searching the panel's content ends at the keyboard's top, moving with it in the
    // keyboard's own animation
    private func keyboardWillChange(_ notification: Notification) {
        guard
            store.attachPanel.isSearching,
            let info = notification.userInfo,
            let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let window = UIApplication.shared.topViewController?.view.window
        else {
            return
        }

        let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let covered = max(0, window.bounds.height - frame.minY - window.safeAreaInsets.bottom)

        withAnimation(.easeOut(duration: duration)) {
            store.attachPanel.keyboardWillChange(inset: covered)
        }
    }

    // the expression panel in the keyboard's place, or the keyboard back in the panel's
    private func toggleExpressions() {
        if areExpressionsOpen {
            store.attachPanel.beginHandoffToKeyboard()
            isFieldFocused = true
        } else if areAttachmentsOpen {
            store.attachPanel.switchTo(.expressions)
        } else if isFieldFocused {
            store.attachPanel.openUnderKeyboard(.expressions)
            isFieldFocused = false
        } else {
            store.attachPanel.open(.expressions)
        }
    }

    private func closePanel() {
        store.attachPanel.close()
    }

    private func openGifs() {
        openExpressions(on: .gifs)
    }

    private func openStickers() {
        openExpressions(on: .stickers)
    }

    private func openEmoji() {
        openExpressions(on: .emoji)
    }

    // the mac's buttons: one opens the picker on its own tab, again on the same tab closes it
    private func openExpressions(on tab: ExpressionPanel.Tab) {
        let panel = store.attachPanel

        if panel.isPickerOpen && panel.expressionTab == tab {
            panel.isPickerOpen = false
            return
        }

        panel.expressionTab = tab
        panel.isPickerOpen = true
    }

    private func closePicker() {
        store.attachPanel.isPickerOpen = false
    }

    private func unfocusField() {
        isFieldFocused = false
    }

    private func deleteBackward() {
        if !text.isEmpty {
            text.removeLast()
        }
    }

    private func sendGif(_ gif: Gif) {
        sendExpression(content: gif.url, stickerId: nil)
    }

    private func sendSticker(_ sticker: Sticker) {
        sendExpression(content: "", stickerId: sticker.id)
    }

    private func sendExpression(content: String, stickerId: Int?) {
        errorMessage = nil
        // sent, the mac's picker goes, as discord's does
        store.attachPanel.isPickerOpen = false

        Task {
            do {
                try await store.sendExpression(content: content, stickerId: stickerId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func insertEmoji(_ shortcode: String) {
        let entry = EmojiCatalog.find(shortcode)

        text += entry?.emoji ?? ":\(shortcode):"
    }

    private func toggleAttachPanel() {
        // with the keyboard up the panel takes its place and the x gives it back, each sliding
        // over the other at the same height so the composer holds still. otherwise the panel
        // slides in and out on its own, the composer riding on it
        if areExpressionsOpen {
            store.attachPanel.switchTo(.attachments)
        } else if store.attachPanel.isOpen {
            if store.attachPanel.returnsToKeyboard {
                store.attachPanel.beginHandoffToKeyboard()
                isFieldFocused = true
            } else {
                store.attachPanel.close()
            }
        } else if isFieldFocused {
            store.attachPanel.openUnderKeyboard(.attachments)
            isFieldFocused = false
        } else {
            store.attachPanel.open(.attachments)
        }
    }

    // a swipe down on the composer drags an open panel down with it, like the keyboard
    private var panelDrag: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                if value.translation.height > 0 {
                    store.attachPanel.drag(value.translation.height)
                }
            }
            .onEnded { value in
                if store.attachPanel.isDragging {
                    store.attachPanel.release(predicted: value.predictedEndTranslation.height)
                }
            }
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
                    session.typing.resetSignal(in: store.typingPlace)
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


// the composer and the panel pushed down together while a drag carries them, read here so only
// this offset updates under the finger, not the composer
private struct PanelSlide: ViewModifier {
    let model: AttachPanelModel

    func body(content: Content) -> some View {
        content.offset(y: model.slideOffset)
    }
}

// discord's "someone is typing…" with its three dots, just above the message box
private struct TypingIndicator: View {
    let place: TypingTracker.Place

    @Environment(SessionStore.self) private var session

    private var names: [String] {
        session.typing.userIds(in: place).compactMap { session.usersById[$0]?.name }
    }

    private var text: AttributedString? {
        let names = names

        func bold(_ name: String) -> AttributedString {
            var part = AttributedString(name)

            part.font = .caption.bold()
            part.foregroundColor = Theme.header

            return part
        }

        switch names.count {
        case 0:
            return nil
        case 1:
            return bold(names[0]) + AttributedString(" is typing…")
        case 2:
            return bold(names[0]) + AttributedString(" and ") + bold(names[1]) + AttributedString(" are typing…")
        case 3:
            return bold(names[0]) + AttributedString(", ") + bold(names[1]) + AttributedString(" and ") + bold(names[2]) + AttributedString(" are typing…")
        default:
            return AttributedString("Several people are typing…")
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if let text {
                HStack(spacing: 6) {
                    TypingDots()

                    Text(text)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    LinearGradient(
                        colors: [Theme.chatBackground.opacity(0), Theme.chatBackground],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: text == nil)
    }
}

private struct TypingDots: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            HStack(spacing: 3) {
                ForEach(0..<3) { index in
                    // each dot rises and fades a third of a beat after the one before
                    let phase = (sin((time * 2 * .pi / 1.2) - Double(index) * 0.9) + 1) / 2

                    Circle()
                        .fill(Theme.header)
                        .frame(width: 5, height: 5)
                        .opacity(0.35 + 0.65 * phase)
                        .offset(y: -2 * phase)
                }
            }
        }
        .frame(height: 10)
    }
}

// an icon in the mac's message box, brightening and bouncing up a little under the pointer
private struct ExpressionButton<Label: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let label: Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(isHovered ? Theme.header : Theme.muted)
                .frame(width: 26, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverPop(scale: 1.18)
        .onHover(perform: setHovered)
        .accessibilityLabel(title)
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }
}

// discord's emoji button: a grey face that turns to colour, grows and tips under the pointer, a
// different face each time it is pointed at
private struct FunEmojiButton: View {
    private static let faces = ["😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "😉", "😊", "😇", "🥰", "😍", "🤩", "😋", "😛", "😜", "🤪", "🤗", "🤭", "🤔", "😎", "🥳", "😏", "😺"]

    let action: () -> Void

    @State private var isHovered = false
    @State private var face = "😀"

    var body: some View {
        Button(action: action) {
            Text(face)
                .font(.system(size: 19))
                .grayscale(isHovered ? 0 : 1)
                .opacity(isHovered ? 1 : 0.55)
                .scaleEffect(isHovered ? 1.22 : 1)
                .rotationEffect(.degrees(isHovered ? -10 : 0))
                .frame(width: 26, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isHovered)
        .onHover(perform: setHovered)
        .accessibilityLabel("Emoji")
    }

    private func setHovered(_ hovered: Bool) {
        if hovered {
            face = Self.faces.randomElement() ?? face
        }

        isHovered = hovered
    }
}
