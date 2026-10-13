import Photos
import SwiftUI
import UniformTypeIdentifiers

// discord's attachment panel, in the keyboard's place under the composer: the camera and the
// latest photos to tap straight into the message, the full pickers in a bar floating over the
// bottom. drag it up to fill the screen, down to put it away. with access to only some photos
// it says so and offers to change them
struct AttachmentPanel: View {
    static let height: CGFloat = 340

    // the one color the whole panel is, down behind the home indicator
    static let background = Color(hex: "#232428")

    let selectedIds: Set<String>
    let canAddMore: Bool
    let onToggle: (PHAsset) -> Void
    let onCamera: () -> Void
    let onPhotos: () -> Void
    let onPoll: (() -> Void)?
    let onFiles: () -> Void
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    @State private var library = PhotoLibrary()
    @State private var isManagePresented = false
    @State private var isExpanded = false
    @State private var dragOffset: CGFloat = 0

    private var isLimited: Bool {
        library.status == .limited
    }

    // the screen less the navigation bar and the composer, which stays above the panel
    private var expandedHeight: CGFloat {
        let screen = UIApplication.shared.topViewController?.view.window?.bounds.height ?? 800

        return screen * 0.72
    }

    private var height: CGFloat {
        let resting = isExpanded ? expandedHeight : Self.height

        return min(max(resting - dragOffset, Self.height * 0.6), expandedHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Theme.muted.opacity(0.5))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, isLimited ? 6 : 10)

                if isLimited {
                    HStack(spacing: 12) {
                        Text("You've given Sharkord access to a select number of photos and videos.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)

                        Spacer(minLength: 0)

                        Button("Manage", action: manage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.header)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.inputBackground, in: .rect(cornerRadius: 10))
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .gesture(resize)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: height)
        .overlay(alignment: .bottom) {
            bar
        }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                .fill(Self.background)
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
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

    // floats over the photos, which fade into the panel behind it rather than meeting an edge
    private var bar: some View {
        HStack(spacing: 0) {
            PanelButton(title: "Photos", action: onPhotos) {
                Image(systemName: "photo.fill")
            }

            if let onPoll {
                PanelButton(title: "Poll", action: onPoll) {
                    PollGlyph()
                }
            }

            PanelButton(title: "Files", action: onFiles) {
                Image(systemName: "paperclip")
                    .fontWeight(.bold)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color(hex: "#2B2C31"), in: .rect(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .padding(.horizontal, 28)
        .padding(.bottom, 6)
        .background(alignment: .bottom) {
            LinearGradient(colors: [Self.background.opacity(0), Self.background], startPoint: .top, endPoint: .center)
                .frame(height: 130)
                .allowsHitTesting(false)
        }
    }

    // the grabber drags the panel taller or shorter, a flick down from its resting size closes it
    private var resize: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let travel = value.predictedEndTranslation.height

                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    dragOffset = 0

                    if travel < -80 {
                        isExpanded = true
                    } else if travel > 80 && isExpanded {
                        isExpanded = false
                    } else if travel > 80 {
                        onClose()
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch library.status {
        case .authorized, .limited:
            grid
        case .denied, .restricted:
            NoAccessView()
        default:
            ProgressView()
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                Button(action: onCamera) {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.text)
                        }
                        .background(Theme.inputBackground, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                ForEach(library.assets, id: \.localIdentifier) { asset in
                    let isSelected = selectedIds.contains(asset.localIdentifier)

                    AssetCell(asset: asset, library: library, isSelected: isSelected) {
                        if isSelected || canAddMore {
                            onToggle(asset)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)

            if isLimited {
                VStack(spacing: 14) {
                    Text("Not what you're looking for? Browse your photo library for that perfect picture.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)

                    Button(action: onPhotos) {
                        Text("Browse Photos")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Theme.blurple, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
            }
        }
        // room to scroll the last row out from under the floating bar
        .contentMargins(.bottom, 96, for: .scrollContent)
        .scrollIndicators(.hidden)
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
    let isSelected: Bool
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
            .clipShape(.rect(cornerRadius: 10))
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Text(duration)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Theme.blurple, in: .circle)
                        .overlay {
                            Circle().stroke(.white, lineWidth: 1.5)
                        }
                        .padding(5)
                }
            }
            .contentShape(.rect)
            .onTapGesture(perform: onTap)
            .task(id: asset.localIdentifier) {
                image = await library.thumbnail(for: asset, size: CGSize(width: 100, height: 100))
            }
    }
}

private struct NoAccessView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(Theme.muted)

            Text("Sharkord can't see your photos. Allow access in Settings, or pick one with Photos below.")
                .font(.subheadline)
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
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

private struct PanelButton<Icon: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                icon
                    .font(.system(size: 24))
                    .frame(height: 28)

                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(Theme.header)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// three rounded bars of different lengths, the poll mark in discord's bar
private struct PollGlyph: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            Capsule().frame(width: 24, height: 5.5)
            Capsule().frame(width: 15, height: 5.5)
            Capsule().frame(width: 20, height: 5.5)
        }
        .frame(width: 26, height: 26)
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
