import SwiftUI

// discord's delete confirmation: the message itself in a card, then yes or no
struct DeleteMessageConfirmation: View {
    let message: Message
    let onConfirm: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // a long message is cut off here and fades out, a short one takes only its own height
    private static let previewLimit: CGFloat = 140

    @State private var isShown = false
    @State private var contentHeight: CGFloat = 0

    private var previewMask: LinearGradient {
        let fades = contentHeight > Self.previewLimit

        return LinearGradient(colors: [.black, .black, fades ? .clear : .black], startPoint: .top, endPoint: .bottom)
    }

    private var author: PublicUser? {
        message.userId.flatMap { session.usersById[$0] }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(isShown ? 0.6 : 0)
                .ignoresSafeArea()
                .onTapGesture(perform: cancel)

            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text("Delete Message")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.header)

                    Text("Are you sure you want to delete this message?")
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                }

                HStack(alignment: .top, spacing: 12) {
                    AvatarView(user: author, size: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(author?.name ?? message.pluginId ?? "Unknown")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(hex: session.roleColor(for: author) ?? "#F2F3F5"))

                            Text(MessageDate.timestamp(message.createdDate))
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                        }

                        if let content = message.content, !content.isEmpty {
                            MessageContentView(html: content)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
                                .frame(height: min(contentHeight, Self.previewLimit), alignment: .top)
                                .clipped()
                                .mask(previewMask)
                        } else if let poll = message.poll {
                            Label {
                                Text(poll.question)
                                    .lineLimit(3)
                            } icon: {
                                Image(systemName: "text.alignleft")
                            }
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                        } else if !message.files.isEmpty {
                            Label("\(message.files.count) attachment\(message.files.count == 1 ? "" : "s")", systemImage: "paperclip")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .allowsHitTesting(false)

                VStack(spacing: 10) {
                    Button(action: confirm) {
                        Text("Yes")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Theme.blurple, in: .rect(cornerRadius: 10))
                    }

                    Button(action: cancel) {
                        Text("No")
                            .font(.headline)
                            .foregroundStyle(Theme.header)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Theme.inputBackground, in: .rect(cornerRadius: 10))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .background(Theme.listBackground, in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24).stroke(Theme.divider, lineWidth: 1)
            }
            .padding(.horizontal, 20)
            .scaleEffect(isShown || reduceMotion ? 1 : 0.92)
            .opacity(isShown ? 1 : 0)
        }
        .onAppear(perform: show)
    }

    private func show() {
        withAnimation(.spring(response: 0.25, dampingFraction: 1)) {
            isShown = true
        }
    }

    private func confirm() {
        onConfirm()
        close()
    }

    private func cancel() {
        close()
    }

    private func close() {
        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            dismiss()
        }
    }
}
