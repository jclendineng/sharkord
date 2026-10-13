import SwiftUI

// users.getAll, addRole, removeRole, kick, ban, unban and delete
struct MembersScreen: View {
    @Environment(SessionStore.self) private var session

    @State private var users: [AdminUser] = []
    @State private var roles: [AdminRole] = []
    @State private var query = ""
    @State private var errorMessage: String?
    @State private var isLoading = true

    private var shown: [AdminUser] {
        users
            .filter { !$0.isDeletedPlaceholder }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || ($0.identity ?? "").localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.red)
            }

            Section("\(shown.count) Members") {
                ForEach(shown) { user in
                    NavigationLink {
                        MemberDetail(user: user, roles: roles, onChange: reload)
                    } label: {
                        MemberRow(user: user, roles: roles)
                    }
                }
            }
        }
        .settingsListStyle()
        .searchable(text: $query, prompt: "Search members")
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func load() async {
        do {
            async let loadedUsers: [AdminUser] = session.request("users.getAll")
            async let loadedRoles: [AdminRole] = session.request("roles.getAll")

            users = try await loadedUsers
            roles = try await loadedRoles
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func reload() {
        Task {
            await load()
        }
    }
}

private struct MemberRow: View {
    let user: AdminUser
    let roles: [AdminRole]

    @Environment(SessionStore.self) private var session

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(user: session.usersById[user.id], size: 36, showsStatus: true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.name)
                        .foregroundStyle(user.banned ? Theme.muted : Theme.header)

                    if user.banned {
                        Text("BANNED")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.red, in: .rect(cornerRadius: 4))
                    }
                }

                Text(roles.filter { user.roleIds.contains($0.id) }.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
    }
}

private struct MemberDetail: View {
    enum Action: Identifiable {
        case kick
        case ban
        case delete

        var id: Self { self }
    }

    let user: AdminUser
    let roles: [AdminRole]
    let onChange: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var roleIds: Set<Int> = []
    @State private var pending: Action?
    @State private var reason = ""
    @State private var wipe = false
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var isSelf: Bool {
        user.id == session.ownUserId
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AvatarView(user: session.usersById[user.id], size: 56, showsStatus: true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.name)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.header)

                        if let identity = user.identity {
                            Text(identity)
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }

                        Text("Joined \(Date(timeIntervalSince1970: TimeInterval(user.createdAt) / 1000).formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }

            Section("Roles") {
                ForEach(roles) { role in
                    Toggle(isOn: binding(for: role)) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: role.color))
                                .frame(width: 10, height: 10)

                            Text(role.name)
                        }
                    }
                    .disabled(isWorking)
                }
            }

            if !isSelf {
                Section {
                    if user.banned {
                        if let banReason = user.banReason, !banReason.isEmpty {
                            LabeledContent("Ban Reason", value: banReason)
                        }

                        Button("Unban", action: unban)
                    } else {
                        Button("Kick", role: .destructive) { pending = .kick }
                        Button("Ban", role: .destructive) { pending = .ban }
                    }

                    Button("Delete Account", role: .destructive) { pending = .delete }
                } header: {
                    Text("Moderation")
                } footer: {
                    Text("Kicking disconnects them, they can join again. A ban keeps them out until unbanned.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                }
            }
        }
        .settingsListStyle()
        .navigationTitle(user.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pending) { action in
            ConfirmModeration(action: action, name: user.name, reason: $reason, wipe: $wipe) {
                perform(action)
            }
        }
        .onAppear {
            roleIds = Set(user.roleIds)
        }
    }

    private func binding(for role: AdminRole) -> Binding<Bool> {
        Binding(
            get: { roleIds.contains(role.id) },
            set: { isOn in
                setRole(role, isOn: isOn)
            }
        )
    }

    private func setRole(_ role: AdminRole, isOn: Bool) {
        struct RoleInput: Encodable {
            let userId: Int
            let roleId: Int
        }

        let previous = roleIds

        if isOn {
            roleIds.insert(role.id)
        } else {
            roleIds.remove(role.id)
        }

        run(onFailure: { roleIds = previous }) {
            try await session.perform(isOn ? "users.addRole" : "users.removeRole", RoleInput(userId: user.id, roleId: role.id))
        }
    }

    private func unban() {
        run {
            try await session.perform("users.unban", ["userId": user.id])
            dismiss()
        }
    }

    private func perform(_ action: Action) {
        struct ReasonInput: Encodable {
            let userId: Int
            let reason: String?
        }

        struct DeleteInput: Encodable {
            let userId: Int
            let wipe: Bool
        }

        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = ReasonInput(userId: user.id, reason: trimmed.isEmpty ? nil : trimmed)

        run {
            switch action {
            case .kick:
                try await session.perform("users.kick", input)
            case .ban:
                try await session.perform("users.ban", input)
            case .delete:
                try await session.perform("users.delete", DeleteInput(userId: user.id, wipe: wipe))
            }

            dismiss()
        }
    }

    private func run(onFailure: @escaping () -> Void = {}, _ work: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil

        Task {
            do {
                try await work()
                onChange()
            } catch {
                onFailure()
                errorMessage = error.localizedDescription
            }

            isWorking = false
        }
    }
}

// a kick, ban or delete is confirmed with what will happen spelled out, and a reason
private struct ConfirmModeration: View {
    let action: MemberDetail.Action
    let name: String
    @Binding var reason: String
    @Binding var wipe: Bool
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch action {
        case .kick:
            "Kick \(name)"
        case .ban:
            "Ban \(name)"
        case .delete:
            "Delete \(name)'s Account"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if action == .delete {
                    Section {
                        Toggle("Also Delete Their Messages", isOn: $wipe)
                    } footer: {
                        Text("Otherwise their messages stay, shown as from a deleted user. This can't be undone.")
                    }
                } else {
                    Section("Reason (optional)") {
                        TextField("Why?", text: $reason, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }

                Section {
                    Button(role: .destructive, action: confirm) {
                        Text(title)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .settingsListStyle()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.deepBackground)
    }

    private func confirm() {
        dismiss()
        onConfirm()
    }

    private func close() {
        dismiss()
    }
}
