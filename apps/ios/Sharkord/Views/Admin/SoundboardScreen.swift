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

    private var unpicked: [SoundboardLibrarySound] {
        let picked = Set(session.sounds.compactMap(\.libraryKey))

        return library.filter { !picked.contains($0.key) }
    }

    var body: some View {
        List {
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
                        SoundRow(name: sound.name, emoji: sound.emoji)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            delete(sound)
                        }
                    }
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
                }
            }
        }
        .settingsListStyle()
        .navigationTitle("Soundboard")
        .navigationBarTitleDisplayMode(.inline)
        .task(loadLibrary)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.mp3, .wav, .mpeg4Audio],
            allowsMultipleSelection: true,
            onCompletion: importFiles
        )
        .sheet(item: $editing) { sound in
            NavigationStack {
                SoundEditor(sound: sound)
            }
            .environment(session)
            .appSheet(addsClose: true)
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

    var body: some View {
        HStack(spacing: 10) {
            if let emoji, !emoji.isEmpty {
                EmojiView(value: emoji, size: 20)
            } else {
                Image(systemName: "waveform")
                    .foregroundStyle(Theme.muted)
                    .frame(width: 20)
            }

            Text(name)
                .foregroundStyle(Theme.header)

            Spacer()
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
                TextField("Name", text: $name)
            }

            Section("Emoji") {
                TextField("Emoji", text: $emoji)
            }

            Section("Volume") {
                HStack(spacing: 12) {
                    Slider(value: $volume, in: 0...100, step: 5)

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
        .settingsListStyle()
        .navigationTitle("Edit Sound")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
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
