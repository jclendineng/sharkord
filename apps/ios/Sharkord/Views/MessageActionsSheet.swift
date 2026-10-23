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
    // the mac's menu hands forward and the rules setup to the list, a sheet shown from the menu
    // left it open behind
    var onShowSheet: ((MessageMenuSheet) -> Void)?

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closePointerMenu) private var closePointerMenu
    @Environment(\.openURL) private var openURL
    @Environment(\.isPointerMenu) private var isPointerMenu

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
            VStack(spacing: isPointerMenu ? 0 : 16) {
                VStack(spacing: 10) {
                    HStack(spacing: isPointerMenu ? 6 : 10) {
                        ForEach(rowReactions, id: \.self) { shortcode in
                            Button(action: { react(shortcode) }) {
                                EmojiView(value: shortcode, size: isPointerMenu ? 20 : 28)
                                    .frame(maxWidth: .infinity, minHeight: isPointerMenu ? 34 : 52)
                                    .background(Theme.listBackground, in: .rect(cornerRadius: isPointerMenu ? 17 : 14))
                                    .hoverBrighten(cornerRadius: isPointerMenu ? 17 : 14)
                            }
                            .buttonStyle(.plain)
                            .pointerTooltip(":\(shortcode):")
                        }

                        Button(action: openPicker) {
                            Label("Add Reaction", systemImage: "face.smiling")
                                .labelStyle(.iconOnly)
                                .font(isPointerMenu ? .body : .title2)
                                .foregroundStyle(Theme.text)
                                .frame(maxWidth: .infinity, minHeight: isPointerMenu ? 34 : 52)
                                .background(Theme.listBackground, in: .rect(cornerRadius: isPointerMenu ? 17 : 14))
                                .contentShape(.rect(cornerRadius: isPointerMenu ? 17 : 14))
                        }
                            .hoverBrighten(cornerRadius: isPointerMenu ? 17 : 14)
                    }

                    // a mac has no double tap
                    if !isPointerMenu {
                        doubleTapHint
                    }
                }
                .padding(.top, isPointerMenu ? 6 : 20)

                ActionGroup {
                    if isPointerMenu {
                        SubmenuRow(title: "Add Reaction") {
                            ForEach(FrequentExpressions.emoji.prefix(10), id: \.self) { shortcode in
                                EmojiChoiceRow(shortcode: shortcode) {
                                    react(shortcode)
                                }
                            }

                            ActionRow(title: "View More", systemImage: "face.smiling", action: openPicker)
                        }
                    }

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

                    if session.canPin(in: message.channelId) {
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
            .padding(.horizontal, isPointerMenu ? 6 : 16)
            .fittedSheet()
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.deepBackground)
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .sheet(isPresented: $isPickerPresented) {
            EmojiPickerView(includesCustom: true, onPick: react)
                .environment(session)
                .environment(servers)
                .appSheet(addsClose: true)
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
                .environment(session)
                .environment(servers)
                .appSheet(addsClose: true)
        }
        .sheet(isPresented: $isForwardPresented, onDismiss: close) {
            ForwardSheet(message: message)
                .environment(session)
                .environment(servers)
                .appSheet()
        }
        .sheet(isPresented: $isRulesSetupPresented, onDismiss: close) {
            RulesSetupSheet(messageId: message.id)
                .environment(session)
                .environment(servers)
                .appSheet()
        }
        .alert("Reporting isn't set up", isPresented: $isReportUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This server's admins haven't added an address for reports yet. They can add one in Server Settings, under Overview.")
        }
    }

    // the mac's menu leads with what you react with most, like discord's. the phone's sheet keeps
    // its set, which the double tap hint below it goes with
    private var rowReactions: [String] {
        isPointerMenu ? Array(FrequentExpressions.emoji.prefix(4)) : Self.quickReactions
    }

    private var doubleTapHint: some View {
        HStack(spacing: 4) {
            Text("Double tap a message to")

            EmojiView(value: AppSettings.shared.doubleTapReaction, size: 16)

            Button("Edit", action: openDoubleTapPicker)
                .foregroundStyle(Theme.link)
        }
        .font(.subheadline)
        .foregroundStyle(Theme.muted)
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

        closeMenu()

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
        closeMenu()
    }

    private func reply() {
        store.editing = nil
        store.replyingTo = message
        closeMenu()
    }

    private func forward() {
        guard !showFromList(.forward(message)) else {
            return
        }

        isForwardPresented = true
    }

    private func copy() {
        UIPasteboard.general.string = HTMLText.plainText(from: message.content ?? "")
        closeMenu()
    }

    private func markUnread() {
        let message = message

        closeMenu()

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
        guard !showFromList(.rulesSetup(messageId: message.id)) else {
            return
        }

        isRulesSetupPresented = true
    }

    private func showFromList(_ sheet: MessageMenuSheet) -> Bool {
        guard isPointerMenu, let onShowSheet else {
            return false
        }

        closeMenu()
        onShowSheet(sheet)

        return true
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

        closeMenu()

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

        closeMenu()

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

        closeMenu()
    }

    private func delete() {
        closeMenu()
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
        closeMenu()
    }

    // a sheet on a touch screen, the pointer menu on a mac, where dismiss has nothing to close
    private func closeMenu() {
        if let closePointerMenu {
            closePointerMenu()
        } else {
            dismiss()
        }
    }
}

enum MessageMenuSheet: Identifiable {
    case forward(Message)
    case rulesSetup(messageId: Int)

    var id: String {
        switch self {
        case .forward(let message):
            return "forward-\(message.id)"
        case .rulesSetup(let messageId):
            return "rules-\(messageId)"
        }
    }
}

// a reaction in the mac menu's add reaction list: the emoji and its name, as discord lists them
private struct EmojiChoiceRow: View {
    let shortcode: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                EmojiView(value: shortcode, size: 16)
                    .frame(width: 18)

                Text(":\(shortcode):")
                    .font(.subheadline.weight(.medium))

                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.header)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isHovered ? Theme.hover : .clear, in: .rect(cornerRadius: 4))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover(perform: setHovered)
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }
}
