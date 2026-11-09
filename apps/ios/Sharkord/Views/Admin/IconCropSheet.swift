import SwiftUI

// a picked server icon is framed here and saved small: a phone photo at full size is megabytes
// for something drawn at a few dozen points
struct IconCropSheet: View {
    let image: PlatformImage
    let onUse: (Data, PlatformImage) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @GestureState private var dragTranslation = CGSize.zero
    @GestureState private var pinch: CGFloat = 1

    private static let cropSide: CGFloat = 280
    private static let outputSide: CGFloat = 512
    private static let zoomRange: ClosedRange<CGFloat> = 1...5

    private var liveZoom: CGFloat {
        min(max(zoom * pinch, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    private var liveOffset: CGSize {
        clamped(
            CGSize(width: offset.width + dragTranslation.width, height: offset.height + dragTranslation.height),
            zoom: liveZoom
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ZStack {
                    picture(scaledBy: 1, zoom: liveZoom, offset: liveOffset)

                    CropMask(side: Self.cropSide)
                        .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.cropSide + 48)
                .clipped()
                .contentShape(.rect)
                .gesture(dragGesture.simultaneously(with: pinchGesture))

                Slider(value: $zoom, in: Self.zoomRange) {
                    Text("Zoom")
                }
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.top)
            .onChange(of: zoom) { _, newZoom in
                offset = clamped(offset, zoom: newZoom)
            }
            .navigationTitle("Move and Scale")
            .toolbar {
                ActionToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }

                ActionToolbarItem(placement: .confirmationAction) {
                    Button("Use", action: use)
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                offset = clamped(
                    CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height),
                    zoom: liveZoom
                )
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                zoom = min(max(zoom * value.magnification, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
            }
    }

    // the whole picture covers the square at a zoom of one, its short side across it
    private func displayedSize(zoom: CGFloat) -> CGSize {
        let fill = Self.cropSide / min(image.size.width, image.size.height) * zoom

        return CGSize(width: image.size.width * fill, height: image.size.height * fill)
    }

    // never so far that the square shows past the picture's edge
    private func clamped(_ offset: CGSize, zoom: CGFloat) -> CGSize {
        let size = displayedSize(zoom: zoom)
        let maxX = (size.width - Self.cropSide) / 2
        let maxY = (size.height - Self.cropSide) / 2

        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func picture(scaledBy factor: CGFloat, zoom: CGFloat, offset: CGSize) -> some View {
        let size = displayedSize(zoom: zoom)

        return Image(platformImage: image)
            .resizable()
            .frame(width: size.width * factor, height: size.height * factor)
            .offset(x: offset.width * factor, y: offset.height * factor)
    }

    private func cancel() {
        dismiss()
    }

    private func use() {
        let side = Self.outputSide
        let content = picture(scaledBy: side / Self.cropSide, zoom: zoom, offset: offset)
            .frame(width: side, height: side)
            .clipped()
        let renderer = ImageRenderer(content: content)

        renderer.proposedSize = ProposedViewSize(width: side, height: side)
        renderer.scale = 1

        #if os(macOS)
        let output = renderer.nsImage
        #else
        let output = renderer.uiImage
        #endif

        guard let output, let data = output.pngData() else {
            return
        }

        onUse(data, output)
        dismiss()
    }
}

private nonisolated struct CropMask: Shape {
    let side: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)

        path.addRoundedRect(
            in: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side),
            cornerSize: CGSize(width: side * 0.22, height: side * 0.22)
        )

        return path
    }
}
