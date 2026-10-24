import SwiftUI

// packages/shared statics/permissions.ts
enum ChannelPermission: String, CaseIterable, Codable {
    case viewChannel = "VIEW_CHANNEL"
    case sendMessages = "SEND_MESSAGES"
    case join = "JOIN"
    case speak = "SPEAK"
    case shareScreen = "SHARE_SCREEN"
    case webcam = "WEBCAM"

    var title: String {
        switch self {
        case .viewChannel:
            "View Channel"
        case .sendMessages:
            "Send Messages"
        case .join:
            "Join Channel"
        case .speak:
            "Speak"
        case .shareScreen:
            "Share Screen"
        case .webcam:
            "Enable Webcam"
        }
    }

    var detail: String {
        switch self {
        case .viewChannel:
            "See the channel and read its messages."
        case .sendMessages:
            "Send messages in the channel."
        case .join:
            "Join the voice channel."
        case .speak:
            "Talk once they've joined."
        case .shareScreen:
            "Share their screen in the channel."
        case .webcam:
            "Turn on their camera in the channel."
        }
    }

    // a text channel has nothing to join or speak in
    static func relevant(to type: ChannelType) -> [ChannelPermission] {
        type == .voice ? allCases : [.viewChannel, .sendMessages]
    }
}

// channels.getPermissions, one row per permission for every role or member with an override
private struct ChannelPermissionRows: Decodable {
    struct RoleRow: Decodable {
        let roleId: Int
        let permission: String
        let allow: Bool
    }

    struct UserRow: Decodable {
        let userId: Int
        let permission: String
        let allow: Bool
    }

    let rolePermissions: [RoleRow]
    let userPermissions: [UserRow]
}

enum PermissionTarget: Hashable, Identifiable {
    case role(Int)
    case user(Int)

    var id: String {
        switch self {
        case .role(let id):
            "role-\(id)"
        case .user(let id):
            "user-\(id)"
        }
    }
}

// channels.getPermissions, updatePermissions and deletePermissions. the overrides only
// decide anything on a private channel, a public one lets everyone do everything
struct ChannelPermissionsScreen: View {
    let channelId: Int

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @State private var overrides: [PermissionTarget: Set<ChannelPermission>] = [:]
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isAddPresented = false
    @State private var opened: PermissionTarget?

    private var channel: Channel? {
        session.channels.first { $0.id == channelId }
    }

    private var roleTargets: [PermissionTarget] {
        overrides.keys
            .compactMap { target -> (PermissionTarget, Role)? in
                guard case .role(let id) = target, let role = session.rolesById[id] else {
                    return nil
                }

                return (target, role)
            }
            .sorted { $0.1.name.localizedCaseInsensitiveCompare($1.1.name) == .orderedAscending }
            .map(\.0)
    }

    private var userTargets: [PermissionTarget] {
        overrides.keys
            .compactMap { target -> (PermissionTarget, PublicUser)? in
                guard case .user(let id) = target, let user = session.usersById[id] else {
                    return nil
                }

                return (target, user)
            }
            .sorted { $0.1.name.localizedCaseInsensitiveCompare($1.1.name) == .orderedAscending }
            .map(\.0)
    }

    private func makePrivate() {
        struct PrivateInput: Encodable {
            let channelId: Int
            let `private`: Bool
        }

        errorMessage = nil

        Task {
            do {
                try await session.perform("channels.update", PrivateInput(channelId: channelId, private: true))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    var body: some View {
        List {
            // overrides on a public channel are saved but do nothing, which read as a bug when it
            // was a grey line, so it warns and offers the fix in place
            if let channel, !channel.private {
                Section {
                    Label("This channel is public, so everyone can see and use it and nothing below applies. Make it private for these to take effect.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.yellow)

                    if session.can(.manageChannels) {
                        Button("Make Private", action: makePrivate)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                }
            }

            if !roleTargets.isEmpty {
                Section("Roles") {
                    ForEach(roleTargets) { target in
                        row(for: target)
                    }
                }
            }

            if !userTargets.isEmpty {
                Section {
                    ForEach(userTargets) { target in
                        row(for: target)
                    }
                } header: {
                    Text("Members")
                } footer: {
                    Text("A member's own settings win over their roles.")
                }
            }
        }
        .settingsListStyle()
        .overlay {
            if isLoading {
                ProgressView()
            } else if overrides.isEmpty && errorMessage == nil {
                ContentUnavailableView(
                    "Nobody added yet",
                    systemImage: "lock",
                    description: Text("Add roles or members to choose who can see and use this channel.")
                )
            }
        }
        .navigationTitle("Permissions")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .barTrailing) {
                Button("Add Roles or Members", systemImage: "plus", action: showAdd)
            }
        }
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .sheet(isPresented: $isAddPresented) {
            AddPermissionTargetSheet(taken: Set(overrides.keys), onPick: add)
                .environment(session)
                .environment(servers)
                .appSheet()
        }
        .navigationDestination(item: $opened) { target in
            PermissionOverrideEditor(
                channelId: channelId,
                type: channel?.type ?? .text,
                target: target,
                allowed: overrides[target] ?? [],
                onChange: { overrides[target] = $0 },
                onRemove: { overrides[target] = nil }
            )
        }
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func row(for target: PermissionTarget) -> some View {
        Button {
            opened = target
        } label: {
            HStack(spacing: 12) {
                PermissionTargetLabel(target: target)

                Spacer()

                Text(summary(of: overrides[target] ?? []))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("Remove", systemImage: "trash", role: .destructive) {
                remove(target)
            }
        }
    }

    private func summary(of allowed: Set<ChannelPermission>) -> String {
        guard allowed.contains(.viewChannel) else {
            return "No access"
        }

        let relevant = ChannelPermission.relevant(to: channel?.type ?? .text)

        if relevant.allSatisfy(allowed.contains) {
            return "Full access"
        }

        return "\(relevant.filter(allowed.contains).count) of \(relevant.count)"
    }

    private func load() async {
        do {
            let rows: ChannelPermissionRows = try await session.request("channels.getPermissions", ["channelId": channelId])
            var loaded: [PermissionTarget: Set<ChannelPermission>] = [:]

            for row in rows.rolePermissions {
                add(row.permission, allow: row.allow, to: .role(row.roleId), in: &loaded)
            }

            for row in rows.userPermissions {
                add(row.permission, allow: row.allow, to: .user(row.userId), in: &loaded)
            }

            overrides = loaded
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func add(_ raw: String, allow: Bool, to target: PermissionTarget, in loaded: inout [PermissionTarget: Set<ChannelPermission>]) {
        var allowed = loaded[target] ?? []

        if allow, let permission = ChannelPermission(rawValue: raw) {
            allowed.insert(permission)
        }

        loaded[target] = allowed
    }

    private func showAdd() {
        isAddPresented = true
    }

    // a new override starts with the channel visible, which is why anyone gets added
    private func add(_ target: PermissionTarget) {
        let allowed = Set(ChannelPermission.relevant(to: channel?.type ?? .text))

        errorMessage = nil

        Task {
            do {
                try await session.perform("channels.updatePermissions", PermissionInput(channelId: channelId, target: target, permissions: allowed))
                overrides[target] = allowed
                opened = target
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ target: PermissionTarget) {
        errorMessage = nil

        Task {
            do {
                try await session.perform("channels.deletePermissions", PermissionInput(channelId: channelId, target: target, permissions: nil))
                overrides[target] = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// updatePermissions and deletePermissions take a role or a user, never both
private struct PermissionInput: Encodable {
    let channelId: Int
    let target: PermissionTarget
    let permissions: Set<ChannelPermission>?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(channelId, forKey: .channelId)

        switch target {
        case .role(let id):
            try container.encode(id, forKey: .roleId)
        case .user(let id):
            try container.encode(id, forKey: .userId)
        }

        if let permissions {
            try container.encode(permissions.map(\.rawValue).sorted(), forKey: .permissions)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case channelId, roleId, userId, permissions
    }
}

private struct PermissionTargetLabel: View {
    let target: PermissionTarget

    @Environment(SessionStore.self) private var session

    var body: some View {
        switch target {
        case .role(let id):
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: session.rolesById[id]?.color ?? "#99aab5"))
                    .frame(width: 12, height: 12)
                    .frame(width: 28)

                Text(session.rolesById[id]?.name ?? "Role")
                    .foregroundStyle(Theme.header)
            }
        case .user(let id):
            HStack(spacing: 10) {
                AvatarView(user: session.usersById[id], size: 28, showsStatus: false)

                Text(session.usersById[id]?.name ?? "Member")
                    .foregroundStyle(Theme.header)
            }
        }
    }
}

// a toggle per permission, each one saved as it changes
private struct PermissionOverrideEditor: View {
    let channelId: Int
    let type: ChannelType
    let target: PermissionTarget
    let onChange: (Set<ChannelPermission>) -> Void
    let onRemove: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var allowed: Set<ChannelPermission>
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(
        channelId: Int,
        type: ChannelType,
        target: PermissionTarget,
        allowed: Set<ChannelPermission>,
        onChange: @escaping (Set<ChannelPermission>) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.channelId = channelId
        self.type = type
        self.target = target
        self.onChange = onChange
        self.onRemove = onRemove
        _allowed = State(initialValue: allowed)
    }

    private var title: String {
        switch target {
        case .role(let id):
            session.rolesById[id]?.name ?? "Role"
        case .user(let id):
            session.usersById[id]?.name ?? "Member"
        }
    }

    var body: some View {
        List {
            Section {
                PermissionTargetLabel(target: target)
            }

            Section {
                ForEach(ChannelPermission.relevant(to: type), id: \.self) { permission in
                    Toggle(isOn: binding(for: permission)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(permission.title)
                                .foregroundStyle(Theme.header)

                            Text(permission.detail)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .disabled(isSaving || (permission != .viewChannel && !allowed.contains(.viewChannel)))
                }
            } footer: {
                Text("Without View Channel nothing else applies, the channel stays hidden.")
            }

            Section {
                Button("Remove", role: .destructive, action: remove)
                    .disabled(isSaving)
            } footer: {
                Text("Removing them leaves only what their roles allow.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                }
            }
        }
        .settingsListStyle()
        .navigationTitle(title)
        .inlineNavigationTitle()
    }

    private func binding(for permission: ChannelPermission) -> Binding<Bool> {
        Binding(
            get: { allowed.contains(permission) },
            set: { isOn in
                set(permission, isOn: isOn)
            }
        )
    }

    private func set(_ permission: ChannelPermission, isOn: Bool) {
        let previous = allowed

        if isOn {
            allowed.insert(permission)
        } else {
            allowed.remove(permission)
        }

        let next = allowed

        run(onFailure: { allowed = previous }) {
            try await session.perform("channels.updatePermissions", PermissionInput(channelId: channelId, target: target, permissions: next))
            onChange(next)
        }
    }

    private func remove() {
        run {
            try await session.perform("channels.deletePermissions", PermissionInput(channelId: channelId, target: target, permissions: nil))
            onRemove()
            dismiss()
        }
    }

    private func run(onFailure: @escaping () -> Void = {}, _ work: @escaping () async throws -> Void) {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await work()
            } catch {
                onFailure()
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }
}

// the roles and members that have no override on the channel yet
private struct AddPermissionTargetSheet: View {
    let taken: Set<PermissionTarget>
    let onPick: (PermissionTarget) -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    private var roles: [Role] {
        session.rolesById.values
            .filter { !taken.contains(.role($0.id)) && matches($0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var users: [PublicUser] {
        session.usersById.values
            .filter { !$0.isDeleted && !taken.contains(.user($0.id)) && matches($0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if !roles.isEmpty {
                    Section("Roles") {
                        ForEach(roles) { role in
                            pickButton(.role(role.id))
                        }
                    }
                }

                if !users.isEmpty {
                    Section("Members") {
                        ForEach(users) { user in
                            pickButton(.user(user.id))
                        }
                    }
                }
            }
            .settingsListStyle()
            .searchable(text: $query, placement: .alwaysShown, prompt: "Search roles and members")
            .navigationTitle("Add Roles or Members")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }
            }
        }
        .presentationBackground(Theme.deepBackground)
    }

    private func matches(_ name: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }

    private func pickButton(_ target: PermissionTarget) -> some View {
        Button {
            dismiss()
            onPick(target)
        } label: {
            PermissionTargetLabel(target: target)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func close() {
        dismiss()
    }
}
