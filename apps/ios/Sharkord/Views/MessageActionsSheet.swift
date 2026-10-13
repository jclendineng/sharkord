import SwiftUI
import UIKit

struct MessageActionsSheet: View {
    let message: Message
    let canOpenThread: Bool
    let onOpenThread: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var isPickerPresented = false

    private static let quickReactions = ["+1", "heart", "joy", "open_mouth", "cry", "fire"]

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                ForEach(Self.quickReactions, id: \.self) { shortcode in
                    Button(action: { react(shortcode) }) {
                        EmojiView(value: shortcode, size: 28)
                            .frame(width: 48, height: 48)
                            .background(Theme.listBackground, in: .circle)
                    }
                    .buttonStyle(.plain)
                }

                Button("Add Reaction", systemImage: "face.smiling", action: openPicker)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 48, height: 48)
                    .background(Theme.listBackground, in: .circle)
            }

            VStack(spacing: 0) {
                if canOpenThread {
                    action("Reply in Thread", systemImage: "number.square", perform: onOpenThread)

                    Theme.divider.frame(height: 1)
                }

                action("Copy Text", systemImage: "doc.on.doc", perform: copy)
            }
            .background(Theme.listBackground, in: .rect(cornerRadius: 12))

            Spacer(minLength: 0)
        }
        .padding()
        .presentationDetents([.height(canOpenThread ? 250 : 200)])
        .presentationBackground(Theme.chatBackground)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $isPickerPresented) {
            EmojiPickerView(includesCustom: true, onPick: react)
        }
    }

    private func action(_ title: String, systemImage: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func openPicker() {
        isPickerPresented = true
    }

    private func react(_ emoji: String) {
        let messageId = message.id

        dismiss()

        Task {
            do {
                try await session.toggleReaction(messageId: messageId, emoji: emoji)
            } catch {
                session.showError(error)
            }
        }
    }

    private func copy() {
        UIPasteboard.general.string = HTMLText.plainText(from: message.content ?? "")
        dismiss()
    }
}
