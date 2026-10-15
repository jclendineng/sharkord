import SwiftUI
import UIKit

// discord's long press sheet for a message: quick reactions, then what can be done with it.
// your own messages can be edited and deleted, anyone else's mentioned or reported
struct MessageActionsSheet: View {
    // shortcodes
    static let quickReactions = ["heart", "100", "+1", "joy", "fire"]

    let message: Message
    let store: ChannelMessagesStore
    let canOpenThread: Bool
    let onOpenThread: () -> Void
    // the list asks for confirmation once this sheet is gone, like discord
    let onDelete: (Message) -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isPickerPresented = false
    @State private var isDoubleTapPickerPresented = false
    @State private var isForwardPresented = false
    @State private var isReportUnavailable = false
    @State private var isRulesSetupPresented = false

    private var isOwn: Bool {
        message.userId != nil && message.userId == session.ownUserId
    }

    // the author, or anyone who can manage messages, as on the web
    private var canDelete: Bool {
        isOwn || session.can(.manageMessages)
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

                        EmojiView(value: AppSettings.shared.doubleTapReaction, size: 16)

                        Button("Edit", action: openDoubleTapPicker)
                            .foregroundStyle(Theme.link)
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

                    if session.can(.pinMessages) {
                        ActionRow(
                            title: message.pinned == true ? "Unpin Message" : "Pin Message",
                            systemImage: message.pinned == true ? "pin.slash" : "pin",
                            action: togglePin
                        )
                    }

                    if !isOwn, message.userId != nil {
                        ActionRow(title: "Mention", systemImage: "at", action: mention)
                    }

                    if canSetRules {
                        if isRulesMessage {
                            ActionRow(title: "Stop Using as Rules", systemImage: "checkmark.seal", action: stopUsingAsRules)
                        } else {
                            ActionRow(title: "Use as Rules Message", systemImage: "checkmark.seal", action: openRulesSetup)
                        }
                    }
                }

                ActionGroup {
                    if canDelete {
                        ActionRow(title: "Delete Message", systemImage: "trash", tint: Theme.red, action: delete)
                    }

                    if !isOwn {
                        ActionRow(title: "Report", systemImage: "flag.fill", tint: Theme.red, action: report)
                    }
                }
            }
            .padding(.horizontal, 16)
            .fittedSheet()
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.deepBackground)
        .sheet(isPresented: $isPickerPresented) {
            EmojiPickerView(includesCustom: true, onPick: react)
        }
        .sheet(isPresented: $isDoubleTapPickerPresented) {
            EmojiPickerView(
                includesCustom: true,
                title: "Edit default",
                subtitle: "Choose double tap emoji",
                // straight to full height, the whole list scrolls without a drag up first
                detents: [.large],
                onPick: setDoubleTapReaction
            )
        }
        .sheet(isPresented: $isForwardPresented, onDismiss: close) {
            ForwardSheet(message: message)
        }
        .sheet(isPresented: $isRulesSetupPresented, onDismiss: close) {
            RulesSetupSheet(messageId: message.id)
        }
        .alert("Reporting isn't set up", isPresented: $isReportUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This server's admins haven't added an address for reports yet. They can add one in Server Settings, under Overview.")
        }
    }

    private func openPicker() {
        isPickerPresented = true
    }

    private func openDoubleTapPicker() {
        isDoubleTapPickerPresented = true
    }

    private func setDoubleTapReaction(_ emoji: String) {
        AppSettings.shared.doubleTapReaction = emoji
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

    // the new member lounge's rules, a message in a channel rather than a direct message
    private var canSetRules: Bool {
        store.scope == .channel && session.can(.manageSettings) && session.channel(message.channelId)?.isDm == false
    }

    private var isRulesMessage: Bool {
        session.settings?.onboardingMessageId == message.id
    }

    private func openRulesSetup() {
        isRulesSetupPresented = true
    }

    private func stopUsingAsRules() {
        struct ClearInput: Encodable {
            let messageId: Int?
            let roleId: Int?

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)

                try container.encode(messageId, forKey: .messageId)
                try container.encode(roleId, forKey: .roleId)
            }

            private enum CodingKeys: String, CodingKey {
                case messageId, roleId
            }
        }

        dismiss()

        Task {
            do {
                try await session.perform("others.setOnboarding", ClearInput(messageId: nil, roleId: nil))
            } catch {
                session.showError(error)
            }
        }
    }

    private func togglePin() {
        let messageId = message.id

        dismiss()

        Task {
            do {
                try await session.perform("messages.togglePin", ["messageId": messageId])
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

    private func delete() {
        dismiss()
        onDelete(message)
    }

    // by email to the address the server's admins set, like reporting the server
    private func report() {
        guard
            let reportEmail = session.reportEmail,
            var components = URLComponents(string: "mailto:\(reportEmail)")
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
