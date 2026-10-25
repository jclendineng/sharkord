import SwiftUI
import UniformTypeIdentifiers

// soundboard.add, addFromLibrary, update and delete. the sounds come from the session, which every
// member gets on join and the soundboard events keep current. bounds from packages/shared
// statics/soundboard.ts
struct SoundboardScreen: View {
    private static let nameRange = 2...32
    private static let maxFileSize = 512 * 1024

    @Environment(SessionStore.self) private var session

    @State private var library: [SoundboardLibrarySound] = []
    @State private var isImporterPresented = false
    @State private var isUploading = false
    @State private var addingKey: String?
    @State private var errorMessage: String?
    @State private var editing: SoundboardSound?
    @State private var query = ""
    @State private var results: [FreesoundSound] = []
    @State private var hasMoreResults = false
    @State private var isSearching = false
    @State private var addingFreesoundId: Int?
    @State private var resultsPage = 1

    private var isSoundSearchEnabled: Bool {
        session.settings?.soundSearchEnabled == true
    }

    private var unpicked: [SoundboardLibrarySound] {
        let picked = Set(session.sounds.compactMap(\.libraryKey))

        return library.filter { !picked.contains($0.key) }
    }

    var body: some View {
        SettingsForm {
            Section {
                Button(action: showImporter) {
                    Label("Upload a Sound", systemImage: "folder")
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
                Text("MP3, WAV or M4A, 512 KB at most. Anyone in a call can play them for everyone there.")
                    .wrappingFooter()
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                }
            }

            Section("\(session.sounds.count) Sounds") {
                ForEach(session.sounds) { sound in
                    Button {
                        editing = sound
                    } label: {
                        SoundRow(name: sound.name, emoji: sound.emoji, detail: sound.attribution)
                            .contentShape(.rect)
                    }
                    // a row that opens the sound, not a mac form's push button the row wide
                    .buttonStyle(.plain)
                    .rowDeleteAction {
                        delete(sound)
                    }
                }
            }

            if isSoundSearchEnabled, !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Section {
                    ForEach(results) { sound in
                        FreesoundRow(
                            sound: sound,
                            isAdded: session.sounds.contains { $0.libraryKey == "freesound:\(sound.id)" },
                            isAdding: addingFreesoundId == sound.id,
                            onAdd: { add(sound) }
                        )
                    }

                    if isSearching {
                        ProgressView()
                    } else if hasMoreResults {
                        Button("Load More", action: loadMoreResults)
                    } else if results.isEmpty {
                        Text("No sounds found.")
                            .foregroundStyle(Theme.muted)
                    }
                } header: {
                    Text("Freesound")
                } footer: {
                    Text("Only sounds free to reuse are shown. A sound that asks for credit keeps it.")
                        .wrappingFooter()
                }
            }

            if !unpicked.isEmpty {
                Section {
                    ForEach(unpicked) { sound in
                        HStack(spacing: 12) {
                            Button("Preview", systemImage: "play.fill") {
                                session.previewLibrarySound(sound.key)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)

                            SoundRow(name: sound.name, emoji: sound.emoji)

                            if addingKey == sound.key {
                                ProgressView()
                            } else {
                                Button("Add") {
                                    add(sound)
                                }
                                .buttonStyle(.borderless)
                                .disabled(addingKey != nil)
                            }
                        }
                    }
                } header: {
                    Text("Library")
                } footer: {
                    Text("Free sounds that come with the server, from Kenney (kenney.nl).")
                        .wrappingFooter()
                }
            }
        }
        .settingsListStyle()
        .navigationTitle("Soundboard")
        .inlineNavigationTitle()
        .task(loadLibrary)
        .modifier(SoundSearchField(isEnabled: isSoundSearchEnabled, query: $query))
        // waits for typing to pause before searching, and a new letter cancels the search before
        .task(id: query) {
            await search(page: 1)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.mp3, .wav, .mpeg4Audio],
            allowsMultipleSelection: true,
            onCompletion: importFiles
        )
        .sheet(item: $editing) { sound in
            NavigationStack {
                SoundEditor(sound: sound)
                    .toolbar {
                        ActionToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark", action: closeEditor)
                        }
                    }
            }
            .environment(session)
            .appSheet()
        }
    }

    // named after its file to start with, padded when that is too short
    private static func soundName(_ raw: String) -> String {
        let base = raw.trimmingCharacters(in: .whitespaces)
        let padded = base.count >= nameRange.lowerBound ? base : "\(base)sound"

        return String(padded.prefix(nameRange.upperBound))
    }

    private func loadLibrary() async {
        // an older server has no library, the section stays hidden
        library = (try? await session.request("soundboard.getLibrary")) ?? []
    }

    private func search(page: Int) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        guard isSoundSearchEnabled, !trimmed.isEmpty else {
            results = []
            hasMoreResults = false

            return
        }

        if page == 1 {
            try? await Task.sleep(for: .milliseconds(400))

            guard !Task.isCancelled else {
                return
            }
        }

        struct SearchInput: Encodable {
            let query: String
            let page: Int
        }

        isSearching = true

        do {
            let found: FreesoundPage = try await session.request("soundboard.searchFreesound", SearchInput(query: trimmed, page: page))

            results = page == 1 ? found.sounds : results + found.sounds
            errorMessage = nil
            hasMoreResults = found.hasMore
            resultsPage = page
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }

        isSearching = false
    }

    private func loadMoreResults() {
        Task {
            await search(page: resultsPage + 1)
        }
    }

    private func add(_ sound: FreesoundSound) {
        addingFreesoundId = sound.id
        errorMessage = nil

        Task {
            do {
                let _: Int = try await session.perform("soundboard.addFromFreesound", ["freesoundId": sound.id])
            } catch {
                errorMessage = error.localizedDescription
            }

            addingFreesoundId = nil
        }
    }

    private func closeEditor() {
        editing = nil
    }

    private func showImporter() {
        isImporterPresented = true
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        struct NewSound: Encodable {
            let fileId: String
            let name: String
        }

        guard case .success(let urls) = result else {
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }

            return
        }

        guard let address = session.address, let token = session.token else {
            return
        }

        isUploading = true
        errorMessage = nil

        Task {
            for url in urls {
                let isScoped = url.startAccessingSecurityScopedResource()
                // the picked file is only readable while access lasts, the upload happens later
                let copy = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")

                do {
                    try FileManager.default.copyItem(at: url, to: copy)

                    if isScoped {
                        url.stopAccessingSecurityScopedResource()
                    }

                    let size = (try? copy.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

                    guard size <= Self.maxFileSize else {
                        throw AuthAPI.RequestError(message: "\(url.lastPathComponent) is over 512 KB, the most a sound can be.")
                    }

                    let file = try await UploadAPI.upload(fileAt: copy, name: url.lastPathComponent, to: address, token: token)
                    let name = Self.soundName(url.deletingPathExtension().lastPathComponent)
                    let _: Int = try await session.perform("soundboard.add", NewSound(fileId: file.id, name: name))
                } catch {
                    if isScoped {
                        url.stopAccessingSecurityScopedResource()
                    }

                    errorMessage = error.localizedDescription
                }

                try? FileManager.default.removeItem(at: copy)
            }

            isUploading = false
        }
    }

    private func add(_ sound: SoundboardLibrarySound) {
        addingKey = sound.key
        errorMessage = nil

        Task {
            do {
                let _: Int = try await session.perform("soundboard.addFromLibrary", ["key": sound.key])
            } catch {
                errorMessage = error.localizedDescription
            }

            addingKey = nil
        }
    }

    private func delete(_ sound: SoundboardSound) {
        Task {
            do {
                try await session.perform("soundboard.delete", ["soundId": sound.id])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SoundRow: View {
    let name: String
    let emoji: String?
    var detail: String?

    var body: some View {
        HStack(spacing: 10) {
            if let emoji, !emoji.isEmpty {
                EmojiView(value: emoji, size: 20)
            } else {
                Image(systemName: "waveform")
                    .foregroundStyle(Theme.muted)
                    .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(Theme.header)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
    }
}

private struct FreesoundRow: View {
    let sound: FreesoundSound
    let isAdded: Bool
    let isAdding: Bool
    let onAdd: () -> Void

    @Environment(SessionStore.self) private var session

    var body: some View {
        HStack(spacing: 12) {
            Button("Preview", systemImage: "play.fill", action: preview)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)

            SoundRow(
                name: sound.name,
                emoji: nil,
                detail: "by \(sound.username) · \(sound.license) · \(sound.duration.formatted(.number.precision(.fractionLength(1))))s"
            )

            if isAdding {
                ProgressView()
            } else if isAdded {
                Text("Added")
                    .foregroundStyle(Theme.muted)
            } else {
                Button("Add", action: onAdd)
                    .buttonStyle(.borderless)
            }
        }
    }

    private func preview() {
        if let url = URL(string: sound.previewUrl) {
            session.previewSound(at: url)
        }
    }
}

// the search field only where the server has a freesound key
private struct SoundSearchField: ViewModifier {
    let isEnabled: Bool
    @Binding var query: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.pageSearchable(text: $query, prompt: "Search Freesound")
        } else {
            content
        }
    }
}

// a sound's name, emoji and volume, previewed at the volume being set before it is saved
private struct SoundEditor: View {
    let sound: SoundboardSound

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var emoji: String
    @State private var volume: Double
    @State private var errorMessage: String?

    init(sound: SoundboardSound) {
        self.sound = sound
        _name = State(initialValue: sound.name)
        _emoji = State(initialValue: sound.emoji ?? "")
        _volume = State(initialValue: Double(sound.volume))
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("", text: $name, prompt: Text("Name"))
                    .labelsHidden()
            }

            Section("Emoji") {
                TextField("", text: $emoji, prompt: Text("Emoji"))
                    .labelsHidden()
            }

            Section("Volume") {
                HStack(spacing: 12) {
                    Slider(value: $volume, in: 0...100, step: 5)
                        .tint(Theme.blurple)

                    Text("\(Int(volume))%")
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .frame(width: 48, alignment: .trailing)
                }

                Button("Preview", systemImage: "play.fill", action: preview)
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
        .settingsListStyle()
        .sheetBarBackground()
        .navigationTitle("Edit Sound")
        .inlineNavigationTitle()
        .toolbar {
            ActionToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).count < 2)
            }
        }
    }

    private func preview() {
        session.previewSound(sound, volume: Int(volume))
    }

    private func save() {
        struct UpdateInput: Encodable {
            let soundId: Int
            let name: String
            let emoji: String
            let volume: Int
        }

        let input = UpdateInput(
            soundId: sound.id,
            name: name.trimmingCharacters(in: .whitespaces),
            emoji: emoji.trimmingCharacters(in: .whitespaces),
            volume: Int(volume)
        )

        Task {
            do {
                try await session.perform("soundboard.update", input)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
