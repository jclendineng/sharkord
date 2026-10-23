import Photos
import SwiftUI
import UniformTypeIdentifiers

// discord's attachment panel, in the keyboard's place under the composer: the camera and the
// latest photos to tap straight into the message, the full pickers in a bar floating over the
// bottom. it follows the finger, up over the composer and the conversation, which dims behind
// it, or down and away, and a swipe down on the composer or the conversation drags it the same
// way, like the keyboard. with access to only some photos it says so and offers to change them
struct AttachmentPanel: View {
    static var height: CGFloat {
        AttachPanelModel.restingHeight
    }

    static var background: Color {
        ComposerPanel<EmptyView, EmptyView>.background
    }

    let selectedIds: Set<String>
    let canAddMore: Bool
    let onToggle: (PHAsset) -> Void
    let onCamera: () -> Void
    let onPhotos: () -> Void
    let onPoll: (() -> Void)?
    let onFiles: () -> Void
    let model: AttachPanelModel

    @Environment(\.openURL) private var openURL

    @State private var library = PhotoLibrary()
    @State private var isManagePresented = false

    private var isLimited: Bool {
        library.status == .limited
    }

    var body: some View {
        ComposerPanel(model: model) {
            content
        } bar: {
            bar
        }
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
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .compositingGroup()
        .padding(.horizontal, 28)
        .padding(.bottom, 6)
        .background(alignment: .bottom) {
            LinearGradient(colors: [Self.background.opacity(0), Self.background], startPoint: .top, endPoint: .center)
                .frame(height: 130)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
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

    // its own view with plain values in, so a drag that only moves the panel never rebuilds it
    private var grid: some View {
        PhotoGrid(
            library: library,
            selectedIds: selectedIds,
            canAddMore: canAddMore,
            isScrollEnabled: model.isFullHeight,
            model: model,
            onToggle: onToggle,
            onCamera: onCamera,
            onPhotos: onPhotos,
            onManage: manage
        )
        .equatable()
    }

    private func manage() {
        isManagePresented = true
    }

    private func openSettings() {
        if let url = SystemSettings.url(for: .photos) {
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

// the camera tile and the photos, scrolling only once the panel is full height, before that a
// drag on them moves the panel. compared by its values, the closures left out, so it is not
// rebuilt on every frame of a drag
private struct PhotoGrid: View, Equatable {
    let library: PhotoLibrary
    let selectedIds: Set<String>
    let canAddMore: Bool
    let isScrollEnabled: Bool
    let model: AttachPanelModel
    let onToggle: (PHAsset) -> Void
    let onCamera: () -> Void
    let onPhotos: () -> Void
    let onManage: () -> Void

    @State private var scrollOffset: CGFloat = 0

    private var isLimited: Bool {
        library.status == .limited
    }

    static func == (lhs: PhotoGrid, rhs: PhotoGrid) -> Bool {
        lhs.library === rhs.library
            && lhs.selectedIds == rhs.selectedIds
            && lhs.canAddMore == rhs.canAddMore
            && lhs.isScrollEnabled == rhs.isScrollEnabled
    }

    var body: some View {
        ScrollView {
            if isLimited {
                limitedBanner
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 4), spacing: 3) {
                Button(action: onCamera) {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.text)
                        }
                        .background(Theme.inputBackground, in: .rect(cornerRadius: 8, style: .continuous))
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
            .padding(.horizontal, 6)

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
        // room for the grabber above the first row and the floating bar below the last
        .contentMargins(.top, 30, for: .scrollContent)
        .contentMargins(.bottom, 96, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollDisabled(!isScrollEnabled)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scrollOffset = offset
        }
        .simultaneousGesture(gridDrag)
    }

    // the banner scrolls away with the photos rather than staying pinned
    private var limitedBanner: some View {
        HStack(spacing: 12) {
            Text("You've given Sharkord access to a select number of photos and videos.")
                .font(.subheadline)
                .foregroundStyle(Theme.text)

            Spacer(minLength: 0)

            Button(action: onManage) {
                Text("Manage")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.header)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.inputBackground, in: .rect(cornerRadius: 10))
                    .contentShape(.rect(cornerRadius: 10))
            }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // on the photos: moves the panel until it is full height, then only a pull down from the
    // top of the grid does, everything else is the grid scrolling
    private var gridDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                let pullsDownFromTop = scrollOffset <= 1 && value.translation.height > 0

                if model.isDragging || !isScrollEnabled || pullsDownFromTop {
                    model.drag(value.translation.height)
                }
            }
            .onEnded { value in
                if model.isDragging {
                    model.release(predicted: value.predictedEndTranslation.height)
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

    // size is in pixels, the cell knows its screen's scale and this does not
    func thumbnail(for asset: PHAsset, size: CGSize) async -> UIImage? {
        let options = PHImageRequestOptions()

        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        // opportunistic delivery calls back twice, a quick degraded image and then the real one
        let stream = AsyncStream<UIImage?> { continuation in
            imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, info in
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

        // photos names a resource only when it has a name for it, a nameless one is named after
        // its type so the upload still has an extension
        let filename = original.filename ?? "attachment.\(UTType(original.uniformTypeIdentifier)?.preferredFilenameExtension ?? "dat")"

        if asset.mediaType == .video {
            let target = directory.appending(path: filename)
            let options = PHAssetResourceRequestOptions()

            options.isNetworkAccessAllowed = true

            try await PHAssetResourceManager.default().writeData(for: original, toFile: target, options: options)

            return target
        }

        let data = try await imageData(for: asset)
        let name = (filename as NSString).deletingPathExtension

        // heic doesn't open in most browsers, the web client has to show it too
        if let type = UTType(original.uniformTypeIdentifier), type.conforms(to: .heic) || type.conforms(to: .heif),
           let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) {
            let target = directory.appending(path: "\(name).jpg")

            try jpeg.write(to: target)

            return target
        }

        let target = directory.appending(path: filename)

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

    @Environment(\.displayScale) private var displayScale

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
            .clipShape(.rect(cornerRadius: 6, style: .continuous))
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
                image = await library.thumbnail(for: asset, size: CGSize(width: 100 * displayScale, height: 100 * displayScale))
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

            Text("Sharkord can't see your photos. Allow access in \(SystemSettings.name), or pick one with Photos below.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)

            Button(action: openSettings) {
                Label("Open \(SystemSettings.name)", systemImage: "gearshape.fill")
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
        if let url = SystemSettings.url(for: .photos) {
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

// where the attachment panel sits, shared so the panel, the composer and the conversation can
// all drag it. a drag up grows the panel, which is drawn over the conversation, so nothing else
// moves. a drag down only slides the composer and the panel together as one piece, an offset
// rather than a new layout, which is what keeps it smooth under the finger
@Observable
final class AttachPanelModel {
    // exactly the keyboard's height, so the two trade places without the composer moving
    static var restingHeight: CGFloat {
        let keyboardHeight = KeyboardMetrics.heightAboveSafeArea

        // a rotation keeps the last height, measured in the other orientation, and a portrait
        // keyboard's 300pt covered most of a landscape phone. cap it against its own window
        guard let window = UIApplication.shared.topViewController?.view.window else {
            return keyboardHeight
        }

        return min(keyboardHeight, window.bounds.height * 0.55)
    }

    // the composer has two panels in the keyboard's place, they share this one position
    enum Kind {
        case attachments
        case expressions
    }

    private(set) var isOpen = false
    private(set) var kind = Kind.attachments
    // the expression panel's tab, kept here so the mac's gif and sticker buttons open on theirs
    var expressionTab = ExpressionPanel.Tab.emoji
    // the mac's picker, a card over the chat rather than a panel in the keyboard's place, so
    // the message box never moves. here so a click on the conversation closes it with the rest
    var isPickerOpen = false
    private(set) var settledHeight = restingHeight
    private(set) var dragOffset: CGFloat = 0
    // while the keyboard and the panel trade places the conversation stops making room for the
    // keyboard: the keyboard slides over the panel, or off it, and the composer holds still
    private(set) var isHandingOff = false
    // opened from the keyboard, so closing it brings the keyboard back
    private(set) var returnsToKeyboard = false
    // the keyboard is translucent: as it slides over, the panel fades to the color the
    // keyboard always sits on, so nothing shows through and nothing changes when it goes
    private(set) var isCoveredByKeyboard = false
    // a search field in the panel has the keyboard: the panel is at full height and the
    // keyboard comes up over its bottom instead of pushing the composer and the panel up
    private(set) var isSearching = false
    // how much of the panel's bottom the keyboard covers while searching, so the content ends
    // above it
    private(set) var searchKeyboardInset: CGFloat = 0
    // bumped to have the focused search field give up the keyboard
    private(set) var searchDismissals = 0

    // all but a sliver of the conversation under the navigation bar, as discord leaves it
    var expandedHeight: CGFloat {
        let window = UIApplication.shared.topViewController?.view.window
        let height = window?.bounds.height ?? 800
        let insets = window?.safeAreaInsets ?? .zero

        return height - insets.top - insets.bottom - 110
    }

    // the panel's own height, never less than resting, a drag below that is a slide instead
    var height: CGFloat {
        min(max(settledHeight - dragOffset, Self.restingHeight), expandedHeight)
    }

    // how far the composer and the panel have been pushed down past the resting height
    var slideOffset: CGFloat {
        max(0, dragOffset - (settledHeight - Self.restingHeight))
    }

    var isDragging: Bool {
        dragOffset != 0
    }

    // the grid only scrolls once the panel is as tall as it gets, before that a drag on the
    // photos moves the panel, like a sheet
    var isFullHeight: Bool {
        settledHeight >= expandedHeight - 1 && dragOffset == 0
    }

    // how far past its resting height the panel has been pulled, for the dimming behind it
    var expansion: Double {
        Double(max(0, min(1, (height - Self.restingHeight) / (expandedHeight - Self.restingHeight))))
    }

    func open(_ kind: Kind) {
        settledHeight = Self.restingHeight
        dragOffset = 0
        returnsToKeyboard = false
        isCoveredByKeyboard = false
        isSearching = false
        self.kind = kind

        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            isOpen = true
        }
    }

    // one panel swapped for the other in place, as discord switches attachments and emoji
    func switchTo(_ kind: Kind) {
        withoutAnimation {
            self.kind = kind
            settledHeight = Self.restingHeight
            dragOffset = 0
        }
    }

    // in place under the keyboard at once, the keyboard then slides down off it
    func openUnderKeyboard(_ kind: Kind) {
        withoutAnimation {
            self.kind = kind
            settledHeight = Self.restingHeight
            dragOffset = 0
            returnsToKeyboard = true
            isHandingOff = true
            isCoveredByKeyboard = false
            isSearching = false
            isOpen = true
        }
    }

    // the keyboard is about to slide up over the panel
    func beginHandoffToKeyboard() {
        withoutAnimation {
            isHandingOff = true
        }

        withAnimation(.easeOut(duration: 0.18)) {
            isCoveredByKeyboard = true
        }
    }

    // the keyboard is fully up over the panel, which goes underneath it
    func finishHandoffToKeyboard() {
        withoutAnimation {
            isOpen = false
            dragOffset = 0
            settledHeight = Self.restingHeight
            returnsToKeyboard = false
            isHandingOff = false
            isCoveredByKeyboard = false
            isSearching = false
            searchKeyboardInset = 0
        }
    }

    // the keyboard has slid off the panel
    func finishHandoffToPanel() {
        withoutAnimation {
            isHandingOff = false
        }
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction, change)
    }

    // slides away, the composer coming down with it in the same motion
    func close() {
        isPickerOpen = false

        guard isOpen else {
            return
        }

        withAnimation(.easeOut(duration: 0.25)) {
            isOpen = false
            dragOffset = 0
            settledHeight = Self.restingHeight
            returnsToKeyboard = false
        }

        endSearch()
    }

    func beginSearch() {
        guard isOpen, !isSearching else {
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            isSearching = true
            settledHeight = expandedHeight
            dragOffset = 0
            // the keyboard may already be on its way, its notification refines this
            searchKeyboardInset = Self.restingHeight
        }
    }

    // the keyboard is gone, the panel stays where it is
    func endSearch() {
        guard isSearching else {
            return
        }

        isSearching = false
        searchKeyboardInset = 0
    }

    // follows the keyboard in its own animation, so the content's bottom moves with its top
    func keyboardWillChange(inset: CGFloat) {
        guard isSearching else {
            return
        }

        searchKeyboardInset = inset
    }

    func drag(_ translation: CGFloat) {
        guard isOpen else {
            return
        }

        // a drag on the panel puts the search keyboard away first, as discord does
        if isSearching && searchKeyboardInset > 0 {
            searchDismissals += 1
        }

        dragOffset = translation
    }

    // one swipe moves one step: from full height a swipe down lands at the resting height, from
    // the resting height it slides down and away. otherwise it settles at whichever height is
    // nearest to where the fling would have carried it
    func release(predicted translation: CGFloat) {
        guard isOpen else {
            return
        }

        let projected = settledHeight - translation
        let startedExpanded = settledHeight > Self.restingHeight
        let stops: [CGFloat] = startedExpanded ? [Self.restingHeight, expandedHeight] : [0, Self.restingHeight, expandedHeight]
        let target = stops.min { abs($0 - projected) < abs($1 - projected) } ?? Self.restingHeight

        if target == 0 {
            close()
            return
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            dragOffset = 0
            settledHeight = target
        }
    }
}
