import Photos
import SwiftUI
import UniformTypeIdentifiers

// discord's attachment panel: the latest photos in a grid to pick from right there, the full
// pickers in a floating bar below. with access to only some photos it says so and offers to
// change them, like discord does
struct AttachmentPanel: View {
    let maxSelection: Int
    let onPick: ([PHAsset]) -> Void
    let onPhotos: () -> Void
    let onFiles: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var library = PhotoLibrary()
    @State private var selected: [PHAsset] = []
    @State private var isManagePresented = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    PanelButton(title: "Photos", systemImage: "photo", action: openPhotos)
                    PanelButton(title: "Files", systemImage: "paperclip", action: openFiles)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .frame(width: 200)
                .background(Theme.inputBackground, in: .rect(cornerRadius: 22))
                .overlay {
                    RoundedRectangle(cornerRadius: 22).stroke(Theme.divider, lineWidth: 1)
                }

                if !selected.isEmpty {
                    Button(action: attach) {
                        Image(systemName: "arrow.up")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Theme.blurple, in: .circle)
                            .overlay(alignment: .topTrailing) {
                                Text("\(selected.count)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(Theme.blurple)
                                    .frame(minWidth: 20, minHeight: 20)
                                    .background(.white, in: .capsule)
                                    .offset(x: 4, y: -4)
                            }
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            .padding(.bottom, 12)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected.isEmpty)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.listBackground)
        .confirmationDialog("Photo Access", isPresented: $isManagePresented, titleVisibility: .hidden) {
            Button("Select More Photos", action: selectMore)
            Button("Allow Access to All Photos", action: openSettings)
        } message: {
            Text("Choose which photos and videos Sharkord can see, or let it see all of them.")
        }
        .task {
            await library.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch library.status {
        case .authorized:
            grid(showsManage: false)
        case .limited where !library.assets.isEmpty:
            grid(showsManage: true)
        case .limited:
            LimitedAccessView(onManage: manage)
        case .denied, .restricted:
            NoAccessView()
        default:
            ProgressView()
        }
    }

    private func grid(showsManage: Bool) -> some View {
        ScrollView {
            if showsManage {
                HStack(spacing: 12) {
                    Text("Sharkord can see only the photos you picked.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)

                    Spacer(minLength: 0)

                    Button("Manage", action: manage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.link)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(library.assets, id: \.localIdentifier) { asset in
                    AssetCell(
                        asset: asset,
                        library: library,
                        number: selected.firstIndex(of: asset).map { $0 + 1 },
                        onTap: { toggle(asset) }
                    )
                }
            }
            .padding(.top, showsManage ? 8 : 24)
            // room to scroll the last row out from under the floating bar
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
    }

    private func toggle(_ asset: PHAsset) {
        if let index = selected.firstIndex(of: asset) {
            selected.remove(at: index)
        } else if selected.count < maxSelection {
            selected.append(asset)
        }
    }

    private func attach() {
        let assets = selected

        dismiss()
        onPick(assets)
    }

    private func openPhotos() {
        dismiss()
        onPhotos()
    }

    private func openFiles() {
        dismiss()
        onFiles()
    }

    private func manage() {
        isManagePresented = true
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    // apple's own picker for which photos a limited library shares, adding or removing them
    private func selectMore() {
        guard let presenter = UIApplication.shared.topViewController else {
            return
        }

        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { _ in
            Task {
                await library.load()
            }
        }
    }
}

// the latest photos and videos, newest first, and thumbnails for them
@Observable
final class PhotoLibrary {
    // enough to scroll back a while, the photos button is there for anything older
    private static let limit = 300

    private(set) var status = PHAuthorizationStatus.notDetermined
    private(set) var assets: [PHAsset] = []

    @ObservationIgnored private let imageManager = PHCachingImageManager()

    func load() async {
        var current = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        if current == .notDetermined {
            current = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }

        status = current

        // a limited library fetches just the photos it shares
        guard current == .authorized || current == .limited else {
            return
        }

        let options = PHFetchOptions()

        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d || mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        options.fetchLimit = Self.limit

        let result = PHAsset.fetchAssets(with: options)
        var fetched: [PHAsset] = []

        result.enumerateObjects { asset, _, _ in
            fetched.append(asset)
        }

        assets = fetched
    }

    func thumbnail(for asset: PHAsset, size: CGSize) async -> UIImage? {
        let options = PHImageRequestOptions()

        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        let scale = UIScreen.main.scale
        let target = CGSize(width: size.width * scale, height: size.height * scale)

        // opportunistic delivery calls back twice, a quick degraded image and then the real one
        let stream = AsyncStream<UIImage?> { continuation in
            imageManager.requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: options) { image, info in
                continuation.yield(image)

                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false

                if !isDegraded {
                    continuation.finish()
                }
            }
        }

        var latest: UIImage?

        for await image in stream {
            latest = image ?? latest
        }

        return latest
    }

    // a picked photo or video as a file the upload can read, removed again after the upload
    nonisolated static func export(_ asset: PHAsset) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let resources = PHAssetResource.assetResources(for: asset)
        let original = resources.first { $0.type == .video || $0.type == .photo } ?? resources.first

        guard let original else {
            throw AuthAPI.RequestError(message: "That item could not be loaded.")
        }

        if asset.mediaType == .video {
            let target = directory.appending(path: original.originalFilename)
            let options = PHAssetResourceRequestOptions()

            options.isNetworkAccessAllowed = true

            try await PHAssetResourceManager.default().writeData(for: original, toFile: target, options: options)

            return target
        }

        let data = try await imageData(for: asset)
        let name = (original.originalFilename as NSString).deletingPathExtension

        // heic doesn't open in most browsers, the web client has to show it too
        if let type = UTType(original.uniformTypeIdentifier), type.conforms(to: .heic) || type.conforms(to: .heif),
           let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) {
            let target = directory.appending(path: "\(name).jpg")

            try jpeg.write(to: target)

            return target
        }

        let target = directory.appending(path: original.originalFilename)

        try data.write(to: target)

        return target
    }

    private nonisolated static func imageData(for asset: PHAsset) async throws -> Data {
        let options = PHImageRequestOptions()

        options.isNetworkAccessAllowed = true
        options.version = .current
        options.deliveryMode = .highQualityFormat

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: AuthAPI.RequestError(message: "That photo could not be loaded."))
                }
            }
        }
    }
}

private struct AssetCell: View {
    let asset: PHAsset
    let library: PhotoLibrary
    let number: Int?
    let onTap: () -> Void

    @State private var image: UIImage?

    private var duration: String {
        let seconds = Int(asset.duration.rounded())

        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Theme.inputBackground
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Text(duration)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                SelectionBadge(number: number)
                    .padding(6)
            }
            .overlay {
                if number != nil {
                    Rectangle()
                        .stroke(Theme.blurple, lineWidth: 3)
                }
            }
            .contentShape(.rect)
            .onTapGesture(perform: onTap)
            .task(id: asset.localIdentifier) {
                image = await library.thumbnail(for: asset, size: CGSize(width: 140, height: 140))
            }
    }
}

private struct SelectionBadge: View {
    let number: Int?

    var body: some View {
        ZStack {
            Circle()
                .fill(number == nil ? Color.black.opacity(0.25) : Theme.blurple)

            Circle()
                .stroke(.white, lineWidth: 1.5)

            if let number {
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
    }
}

private struct LimitedAccessView: View {
    let onManage: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(Theme.muted)

            Text("You've given Sharkord access to a select number of photos and videos.")
                .font(.headline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)

            Button(action: onManage) {
                Label("Manage", systemImage: "gearshape.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Theme.blurple, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 100)
    }
}

private struct NoAccessView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(Theme.muted)

            Text("Sharkord can't see your photos. Allow access in Settings, or pick one with Photos below.")
                .font(.headline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)

            Button(action: openSettings) {
                Label("Open Settings", systemImage: "gearshape.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Theme.blurple, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 100)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

private struct PanelButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 26))

                Text(title)
                    .font(.subheadline)
            }
            .foregroundStyle(Theme.header)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

extension UIApplication {
    // what a uikit only api like the limited library picker has to present from
    var topViewController: UIViewController? {
        let scene = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = scene?.windows.first { $0.isKeyWindow }
        var top = window?.rootViewController

        while let presented = top?.presentedViewController {
            top = presented
        }

        return top
    }
}
