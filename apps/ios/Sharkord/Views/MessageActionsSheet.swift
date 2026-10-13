import SwiftUI
import UIKit

// discord's long press sheet for a message: quick reactions, then what can be done with it.
// your own messages can be edited and deleted, anyone else's mentioned or reported
struct MessageActionsSheet: View {
    // shortcodes, the first is what a double tap on a message adds
    static let quickReactions = ["heart", "100", "+1", "joy", "fire"]

    let message: Message
    let store: ChannelMessagesStore
    let canOpenThread: Bool
    let onOpenThread: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isPickerPresented = false
    @State private var isForwardPresented = false
    @State private var isConfirmingDelete = false
    @State private var isReportUnavailable = false

    private var isOwn: Bool {
        message.userId != nil && message.userId == session.ownUserId
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(Self.quickReactions, id: \.self) { shortcode in
                            Button(action: { react(shortcode) }) {
                                EmojiView(value: shortcode, size: 28)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(Theme.listBackground, in: .rect(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }

                        Button("Add Reaction", systemImage: "face.smiling", action: openPicker)
                            .labelStyle(.iconOnly)
                            .font(.title2)
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.listBackground, in: .rect(cornerRadius: 14))
                    }

                    HStack(spacing: 4) {
                        Text("Double tap a message to")

                        EmojiView(value: Self.quickReactions[0], size: 16)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                }
                .padding(.top, 20)

                ActionGroup {
                    if isOwn && message.content?.isEmpty == false {
                        ActionRow(title: "Edit Message", systemImage: "pencil", action: edit)
                    }

                    ActionRow(title: "Reply", systemImage: "arrowshape.turn.up.left", action: reply)
                    ActionRow(title: "Forward", systemImage: "arrowshape.turn.up.right", action: forward)

                    if canOpenThread {
                        ActionRow(
                            title: (message.replyCount ?? 0) > 0 ? "Open Thread" : "Create Thread",
                            systemImage: "number.square",
                            action: onOpenThread
                        )
                    }
                }

                ActionGroup {
                    ActionRow(title: "Copy Text", systemImage: "doc.on.doc", action: copy)

                    if store.scope == .channel {
                        ActionRow(title: "Mark Unread", systemImage: "envelope.badge", action: markUnread)
                    }

                    if !isOwn, message.userId != nil {
                        ActionRow(title: "Mention", systemImage: "at", action: mention)
                    }
                }

                ActionGroup {
                    if isOwn {
                        ActionRow(title: "Delete Message", systemImage: "trash", tint: Theme.red, action: confirmDelete)
                    } else {
                        ActionRow(title: "Report", systemImage: "flag.fill", tint: Theme.red, action: report)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.deepBackground)
        .sheet(isPresented: $isPickerPresented) {
            EmojiPickerView(includesCustom: true, onPick: react)
        }
        .sheet(isPresented: $isForwardPresented, onDismiss: close) {
            ForwardSheet(message: message)
        }
        .confirmationDialog("Delete this message?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        }
        .alert("Reporting isn't set up yet", isPresented: $isReportUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A contact address for reports will be added in a later version.")
        }
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

    private func edit() {
        store.replyingTo = nil
        store.editing = message
        dismiss()
    }

    private func reply() {
        store.editing = nil
        store.replyingTo = message
        dismiss()
    }

    private func forward() {
        isForwardPresented = true
    }

    private func copy() {
        UIPasteboard.general.string = HTMLText.plainText(from: message.content ?? "")
        dismiss()
    }

    private func markUnread() {
        let message = message

        dismiss()

        Task {
            do {
                try await store.markUnread(from: message)
            } catch {
                session.showError(error)
            }
        }
    }

    private func mention() {
        if let name = message.userId.flatMap({ session.usersById[$0]?.name }) {
            store.pendingInsert = "@\(name) "
        }

        dismiss()
    }

    private func confirmDelete() {
        isConfirmingDelete = true
    }

    private func delete() {
        let message = message

        dismiss()

        Task {
            do {
                try await store.delete(message)
            } catch {
                session.showError(error)
            }
        }
    }

    // by email, like reporting a server, AppInfo.reportEmail
    private func report() {
        guard
            !AppInfo.reportEmail.isEmpty,
            var components = URLComponents(string: "mailto:\(AppInfo.reportEmail)")
        else {
            isReportUnavailable = true
            return
        }

        let author = message.userId.flatMap { session.usersById[$0]?.name } ?? "Unknown"

        components.queryItems = [
            URLQueryItem(name: "subject", value: "Report: message on \(session.displayName)"),
            URLQueryItem(
                name: "body",
                value: "Server: \(session.displayName) (\(session.address?.baseURL.absoluteString ?? ""))\nChannel id: \(message.channelId)\nMessage id: \(message.id)\nAuthor: \(author)\n\nMessage:\n\(HTMLText.plainText(from: message.content ?? ""))\n\nWhat happened:\n"
            )
        ]

        if let url = components.url {
            openURL(url)
        }
    }

    private func close() {
        dismiss()
    }
}
