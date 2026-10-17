import SwiftUI

// discord's long press sheet for a category, what the channel one does for every channel in it
struct CategoryActionsSheet: View {
    let category: ChannelCategory
    // these open from the header once this sheet has gone, a sheet over a sheet left it behind
    let onMute: () -> Void
    let onEdit: () -> Void
    let onCreateChannel: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closePointerMenu) private var closePointerMenu
    @Environment(\.isPointerMenu) private var isPointerMenu

    @State private var isNotificationsPresented = false

    private var channelIds: [Int] {
        session.channelIds(in: category.id)
    }

    private var isMuted: Bool {
        !channelIds.isEmpty && channelIds.allSatisfy(session.isMuted)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isPointerMenu ? 0 : 16) {
                if !isPointerMenu {
                    HStack(spacing: 12) {
                        ServerIcon(server: session)
                            .frame(width: 44, height: 44)
                            .clipShape(.rect(cornerRadius: 12))

                        Text(category.name)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.header)
                            .lineLimit(1)
                    }
                    .padding(.top, 20)
                }

                ActionGroup(isFirst: isPointerMenu) {
                    ActionRow(title: "Mark As Read", systemImage: "eye", action: markAsRead)

                    if isPointerMenu && !isMuted {
                        SubmenuRow(title: "Mute Category") {
                            MuteChoices(onPick: mute)
                        }
                    } else {
                        ActionRow(
                            title: isMuted ? "Unmute Category" : "Mute Category",
                            systemImage: isMuted ? "bell.fill" : "bell.slash.fill",
                            action: toggleMuted
                        )
                    }

                    if isPointerMenu {
                        SubmenuRow(
                            title: "Notification Settings",
                            subtitle: session.sharedNotificationLevel(of: channelIds).map(NotificationLevelChoices.title(for:))
                        ) {
                            NotificationLevelChoices(selected: session.sharedNotificationLevel(of: channelIds), onPick: setLevel)
                        }
                    } else {
                        ActionRow(title: "Notification Settings", systemImage: "app.badge", action: showNotifications)
                    }
                }

                if session.can(.manageCategories) || session.can(.manageChannels) {
                    ActionGroup {
                        if session.can(.manageCategories) {
                            ActionRow(title: "Edit Category", systemImage: "gearshape.fill", action: onEdit)
                        }

                        if session.can(.manageChannels) {
                            ActionRow(title: "Create Channel", systemImage: "plus", action: onCreateChannel)
                        }
                    }
                }
            }
            .padding(.horizontal, isPointerMenu ? 6 : 16)
            .fittedSheet()
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.deepBackground)
        .sheet(isPresented: $isNotificationsPresented) {
            CategoryNotificationsSheet(category: category)
                .environment(session)
                .environment(servers)
                .appSheet()
        }
    }

    private func markAsRead() {
        Task {
            for channelId in channelIds {
                await session.markAsRead(channelId)
            }
        }

        closeMenu()
    }

    private func toggleMuted() {
        guard isMuted else {
            onMute()
            return
        }

        setLevel(.mentions)
    }

    private func showNotifications() {
        isNotificationsPresented = true
    }

    private func mute(for duration: MuteDuration) {
        let channelIds = channelIds

        Task {
            for channelId in channelIds {
                await session.setNotificationLevel(.none, for: channelId, muteForMinutes: duration.minutes)
            }
        }

        closeMenu()
    }

    private func setLevel(_ level: ChannelNotificationLevel) {
        let channelIds = channelIds

        Task {
            for channelId in channelIds {
                await session.setNotificationLevel(level, for: channelId)
            }
        }

        closeMenu()
    }

    private func closeMenu() {
        if let closePointerMenu {
            closePointerMenu()
        } else {
            dismiss()
        }
    }
}

private struct CategoryNotificationsSheet: View {
    let category: ChannelCategory

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    private var channelIds: [Int] {
        session.channelIds(in: category.id)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NotificationLevelChoices(selected: session.sharedNotificationLevel(of: channelIds), onPick: setLevel)
                } footer: {
                    Text("Applies to every channel in \(category.name). Each one can still be changed on its own.")
                }
            }
            .settingsListStyle()
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
        }
        .sheetDetents([.medium])
        .presentationBackground(Theme.deepBackground)
    }

    private func setLevel(_ level: ChannelNotificationLevel) {
        let channelIds = channelIds

        Task {
            for channelId in channelIds {
                await session.setNotificationLevel(level, for: channelId)
            }
        }
    }

    private func close() {
        dismiss()
    }
}

// categories.update and delete, the name and the way out
struct CategoryEditor: View {
    let category: ChannelCategory

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isConfirmingDelete = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Name") {
                    TextField("Category name", text: $name)
                }

                Section {
                    Button("Delete Category", role: .destructive) { isConfirmingDelete = true }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.red)
                    }
                }
            }
            .settingsListStyle()
            .navigationTitle("Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .disabled(!canSave)
                    }
                }
            }
            .confirmationDialog("Delete \(category.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Category", role: .destructive, action: delete)
            } message: {
                Text("Its channels are deleted with it. This can't be undone.")
            }
            .onAppear {
                name = category.name
            }
        }
        .sheetDetents([.medium, .large])
        .presentationBackground(Theme.deepBackground)
    }

    private func save() {
        struct RenameInput: Encodable {
            let categoryId: Int
            let name: String
        }

        let input = RenameInput(categoryId: category.id, name: name.trimmingCharacters(in: .whitespaces))

        run {
            try await session.perform("categories.update", input)
        }
    }

    private func delete() {
        run {
            try await session.perform("categories.delete", ["categoryId": category.id])
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await work()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }

    private func close() {
        dismiss()
    }
}
