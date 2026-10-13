import SwiftUI

struct AttachmentView: View {
    let file: SharkordFile

    @Environment(SessionStore.self) private var session

    @State private var isViewerPresented = false

    var body: some View {
        if let address = session.address {
            let url = address.fileURL(file)

            if file.isImage {
                Button(action: openViewer) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        Theme.listBackground
                            .frame(width: 240, height: 160)
                    }
                    .frame(maxWidth: 300, maxHeight: 300, alignment: .leading)
                    .clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .fullScreenCover(isPresented: $isViewerPresented) {
                    ImageViewer(url: url)
                }
            } else {
                FileCard(file: file, url: url)
            }
        }
    }

    private func openViewer() {
        isViewerPresented = true
    }
}

private struct FileCard: View {
    let file: SharkordFile
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(.title)
                    .foregroundStyle(Theme.blurple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.originalName)
                        .foregroundStyle(Theme.link)
                        .lineLimit(1)

                    Text(file.size.formatted(.byteCount(style: .file)))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Theme.muted)
            }
            .padding(12)
            .frame(maxWidth: 320)
            .background(Theme.listBackground, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.deepBackground)
            }
        }
    }
}

private struct ImageViewer: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in scale = max(1, value.magnification) }
                            .onEnded { _ in withAnimation { scale = 1 } }
                    )
            } placeholder: {
                ProgressView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                }

                Button("Close", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .padding()
        }
    }

    private func close() {
        dismiss()
    }
}
