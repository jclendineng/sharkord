import QuickLook
import QuickLookThumbnailing
import SwiftUI

// files open on the phone in quick look rather than in safari: pdfs, office and iwork documents,
// text, video and audio, with quick look's own share and save. each is downloaded once into the
// caches folder under its original name, which is how quick look tells what kind it is
enum FileDownloads {
    static func localURL(for file: SharkordFile, from url: URL) async throws -> URL {
        // ids are only unique on one server and the app can be signed in to several
        let directory = URL.cachesDirectory.appending(path: "files/\(url.host() ?? "server")/\(file.id)", directoryHint: .isDirectory)
        let name = (file.originalName as NSString).lastPathComponent
        let target = directory.appending(path: name.isEmpty ? file.name : name)

        if FileManager.default.fileExists(atPath: target.path()) {
            return target
        }

        let (downloaded, response) = try await URLSession.shared.download(from: url)

        // an expired signed link or a deleted file answers with a json error, not the file
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            try? FileManager.default.removeItem(at: downloaded)

            throw AuthAPI.RequestError(message: "This file could not be downloaded.")
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: downloaded, to: target)

        return target
    }
}

// the first page of a document, drawn by quick look from the copy FileDownloads keeps, so opening
// it afterwards is instant. only files small enough that fetching one just to draw it is cheap
enum FileThumbnails {
    private static let maxSize = 10 * 1024 * 1024
    private static let cache = NSCache<NSString, UIImage>()

    static func thumbnail(for file: SharkordFile, from url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: file.cacheKey(at: url)) {
            return cached
        }

        guard file.size <= maxSize, let local = try? await FileDownloads.localURL(for: file, from: url) else {
            return nil
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: local,
            size: CGSize(width: 320, height: 200),
            scale: UITraitCollection.current.displayScale,
            representationTypes: .thumbnail
        )

        // a kind quick look cannot draw, like an archive, has no thumbnail and keeps its icon
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }

        let image = representation.uiImage

        cache.setObject(image, forKey: file.cacheKey(at: url))

        return image
    }
}

extension EnvironmentValues {
    // the message menu is up, see MessageListView
    @Entry var isShowingMessageActions = false
}

// a button that downloads the file and shows it in quick look, its label told whether it is loading
struct OpenFileButton<Label: View>: View {
    let file: SharkordFile
    @ViewBuilder let label: (_ isLoading: Bool) -> Label

    @Environment(SessionStore.self) private var session
    @Environment(\.isShowingMessageActions) private var isShowingMessageActions

    @State private var previewURL: URL?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Button(action: open) {
            label(isLoading)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .quickLookPreview($previewURL)
        .alert("Couldn't Open File", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func open() {
        guard !isShowingMessageActions, let address = session.address else {
            return
        }

        isLoading = true

        Task {
            do {
                previewURL = try await FileDownloads.localURL(for: file, from: address.fileURL(file))
            } catch {
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }
    }
}

extension SharkordFile {
    var isVideo: Bool {
        mimeType.hasPrefix("video/")
    }

    var symbol: String {
        if isImage {
            return "photo.fill"
        }

        if isVideo {
            return "film.fill"
        }

        if isAudio {
            return "waveform"
        }

        if mimeType == "application/pdf" {
            return "doc.richtext.fill"
        }

        if mimeType.hasPrefix("text/") {
            return "doc.text.fill"
        }

        if mimeType.contains("zip") || mimeType.contains("compressed") {
            return "doc.zipper"
        }

        return "doc.fill"
    }
}
