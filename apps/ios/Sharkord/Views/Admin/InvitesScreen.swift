import SwiftUI

// invites.getAll, add and delete
struct InvitesScreen: View {
    @Environment(SessionStore.self) private var session

    @State private var invites: [AdminInvite] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isCreatePresented = false
    @State private var copiedId: Int?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.red)
            }

            Section {
                ForEach(invites) { invite in
                    InviteRow(invite: invite, isCopied: copiedId == invite.id)
                        .contentShape(.rect)
                        .onTapGesture { copy(invite) }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(invite)
                            }
                        }
                }
            } footer: {
                Text("Tap an invite to copy its link, swipe to delete it.")
            }
        }
        .settingsListStyle()
        .overlay {
            if isLoading {
                ProgressView()
            } else if invites.isEmpty && errorMessage == nil {
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
        .sheet(isPresented: $isCreatePresented) {
            CreateInviteSheet(onCreated: reload)
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

    private func copy(_ invite: AdminInvite) {
        guard let address = session.address else {
            return
        }

        // the web client's invite link, see table-invite.tsx
        UIPasteboard.general.string = "\(address.baseURL.absoluteString)/?invite=\(invite.code)"
        copiedId = invite.id
    }

    private func delete(_ invite: AdminInvite) {
        Task {
            do {
                try await session.perform("invites.delete", ["inviteId": invite.id])
                invites.removeAll { $0.id == invite.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct InviteRow: View {
    let invite: AdminInvite
    let isCopied: Bool

    private var usesText: String {
        if let maxUses = invite.maxUses, maxUses > 0 {
            return "\(invite.uses)/\(maxUses) uses"
        }

        return "\(invite.uses) uses"
    }

    private var expiryText: String {
        guard let expiresAt = invite.expiresAt else {
            return "Never expires"
        }

        let date = Date(timeIntervalSince1970: TimeInterval(expiresAt) / 1000)

        return invite.isExpired ? "Expired" : "Expires \(date.formatted(.relative(presentation: .named)))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(invite.code)
                    .font(.body.monospaced())
                    .foregroundStyle(invite.isExpired ? Theme.muted : Theme.header)
                    .lineLimit(1)

                Spacer()

                if isCopied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(Theme.green)
                }
            }

            Text([usesText, expiryText, invite.creator.map { "by \($0.name)" }, invite.role.map { "gives \($0.name)" }].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }
}

private struct CreateInviteSheet: View {
    enum Expiry: String, CaseIterable {
        case hour = "1 hour"
        case day = "1 day"
        case week = "7 days"
        case never = "Never"

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

    let onCreated: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var expiry = Expiry.week
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
                        ForEach(Expiry.allCases, id: \.self) { option in
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
        .presentationDetents([.medium, .large])
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
