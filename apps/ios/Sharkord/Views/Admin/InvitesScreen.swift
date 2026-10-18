import SwiftUI

// invites.getAll, add and delete. deleted invites are kept apart below, with who joined with them
struct InvitesScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @State private var invites: [AdminInvite] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isCreatePresented = false

    private var liveInvites: [AdminInvite] {
        invites
            .filter { !$0.isDeleted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var deletedInvites: [AdminInvite] {
        invites
            .filter(\.isDeleted)
            .sorted { ($0.deletedAt ?? 0) > ($1.deletedAt ?? 0) }
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.red)
            }

            Section {
                ForEach(liveInvites) { invite in
                    NavigationLink {
                        InviteDetailScreen(invite: invite, onDeleted: reload)
                    } label: {
                        InviteRow(invite: invite)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            delete(invite)
                        }
                    }
                }
            } footer: {
                Text("Tap an invite to see who joined with it, swipe to delete it.")
            }

            if !deletedInvites.isEmpty {
                Section("Deleted") {
                    ForEach(deletedInvites) { invite in
                        NavigationLink {
                            InviteDetailScreen(invite: invite, onDeleted: reload)
                        } label: {
                            InviteRow(invite: invite)
                        }
                    }
                }
            }
        }
        .settingsListStyle()
        .overlay {
            if isLoading {
                ProgressView()
            } else if liveInvites.isEmpty && deletedInvites.isEmpty && errorMessage == nil {
                ContentUnavailableView("No invites", systemImage: "link", description: Text("Create one to let people join."))
            }
        }
        .navigationTitle("Invites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Invite", systemImage: "plus", action: showCreate)
            }
        }
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .sheet(isPresented: $isCreatePresented) {
            CreateInviteSheet(onCreated: reload)
                .environment(session)
                .environment(servers)
                .appSheet()
        }
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func load() async {
        do {
            invites = try await session.request("invites.getAll")
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

    private func showCreate() {
        isCreatePresented = true
    }

    private func delete(_ invite: AdminInvite) {
        Task {
            do {
                try await session.perform("invites.delete", ["inviteId": invite.id])
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension AdminInvite {
    var usesText: String {
        if let maxUses, maxUses > 0 {
            return "\(uses)/\(maxUses) uses"
        }

        return "\(uses) \(uses == 1 ? "use" : "uses")"
    }

    var expiryText: String {
        if let deletedAt {
            return "Deleted \(Self.date(deletedAt).formatted(date: .abbreviated, time: .omitted))"
        }

        guard let expiresAt else {
            return "Never expires"
        }

        return isExpired ? "Expired" : "Expires in \(InviteExpiry.timeLeft(until: Self.date(expiresAt)))"
    }

    static func date(_ milliseconds: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }
}

private struct InviteRow: View {
    let invite: AdminInvite

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(invite.code)
                .font(.body.monospaced())
                .foregroundStyle(invite.isExpired || invite.isDeleted ? Theme.muted : Theme.header)
                .lineLimit(1)

            Text([invite.usesText, invite.expiryText, invite.creator.map { "by \($0.name)" }, invite.role.map { "gives \($0.name)" }].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }
}

private struct CreateInviteSheet: View {
    let onCreated: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var expiry = InviteExpiry.week
    @State private var maxUses = 0
    @State private var roleId: Int?
    @State private var roles: [AdminRole] = []
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                Section("Expires After") {
                    Picker("Expires After", selection: $expiry) {
                        ForEach(InviteExpiry.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Stepper(maxUses == 0 ? "No limit" : "\(maxUses) uses", value: $maxUses, in: 0...100)
                } header: {
                    Text("Max Uses")
                }

                if !roles.isEmpty {
                    Section {
                        Picker("Give Role", selection: $roleId) {
                            Text("None").tag(Int?.none)

                            ForEach(roles) { role in
                                Text(role.name).tag(Int?.some(role.id))
                            }
                        }
                    } footer: {
                        Text("People who join with this invite get the role.")
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
            .navigationTitle("New Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create", action: create)
                    }
                }
            }
            .task {
                if session.can(.manageRoles), let loaded: [AdminRole] = try? await session.request("roles.getAll") {
                    roles = loaded
                }
            }
        }
        .sheetDetents([.medium, .large])
        .presentationBackground(Theme.deepBackground)
    }

    private func create() {
        struct InviteInput: Encodable {
            let maxUses: Int
            let expiresAt: Int?
            let roleId: Int?
        }

        let expiresAt = expiry.interval.map { Int(Date.now.addingTimeInterval($0).timeIntervalSince1970 * 1000) }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                let _: Invite = try await session.perform("invites.add", InviteInput(maxUses: maxUses, expiresAt: expiresAt, roleId: roleId))
                onCreated()
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

// how long an invite lasts, for the admin list and the invite sheet alike
enum InviteExpiry: String, CaseIterable {
    case hour = "1 hour"
    case day = "1 day"
    case week = "7 days"
    case never = "Never"

    private static let timeLeftFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()

        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2

        return formatter
    }()

    // "3 days, 23 hours", where a relative date rounded the same link to 3 days in one place and
    // 4 in another
    static func timeLeft(until date: Date) -> String {
        timeLeftFormatter.string(from: .now, to: date) ?? ""
    }

    var interval: TimeInterval? {
        switch self {
        case .hour:
            3600
        case .day:
            86_400
        case .week:
            604_800
        case .never:
            nil
        }
    }
}
