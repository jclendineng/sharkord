import SwiftUI

// roles.getAll, add, update, delete and setDefault
struct RolesScreen: View {
    @Environment(SessionStore.self) private var session

    @State private var roles: [AdminRole] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isReordering = false

    private let isOnMac = Platform.isMac

    // the owner's role stays on top and the default one at the bottom, as discord's do, and the
    // roles between them are what moves. the server sends them in order
    private var ownerRole: AdminRole? {
        roles.first { $0.id == 1 }
    }

    private var defaultRole: AdminRole? {
        roles.first(where: \.isDefault)
    }

    private var movableRoles: [AdminRole] {
        roles.filter { $0.id != 1 && !$0.isDefault }
    }

    var body: some View {
        SettingsForm {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.redText)
            }

            Section {
                if let ownerRole {
                    row(for: ownerRole)
                }

                ForEach(movableRoles) { role in
                    if isReordering {
                        reorderRow(for: role)
                    } else {
                        row(for: role)
                    }
                }
                .onMove(perform: move)

                if let defaultRole {
                    row(for: defaultRole)
                }
            } footer: {
                Text("A member shows as their highest role with a color, and the member list groups them under it. The default role is given to everyone who joins.")
                    .wrappingFooter()
            }
        }
        .settingsListStyle()
        // the phone drags by edit mode's handles, a mac gets arrows: there edit mode blanked the
        // rows and its handles never moved
        .editing(isReordering && !isOnMac)
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .navigationTitle("Roles")
        .inlineNavigationTitle()
        .toolbar {
            if movableRoles.count > 1 {
                ActionToolbarItem(placement: .pageAction) {
                    Button(isReordering ? "Done" : "Reorder", action: toggleReordering)
                }
            }

            ActionToolbarItem(placement: .pageAction) {
                Button("New Role", systemImage: "plus", action: addRole)
            }
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
            roles = try await session.request("roles.getAll")
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

    private func roleLabel(for role: AdminRole) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: role.color))
                .frame(width: 14, height: 14)

            Text(role.name)
                .foregroundStyle(Theme.header)

            Spacer()

            if role.isDefault {
                Text("Default")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func row(for role: AdminRole) -> some View {
        NavigationLink {
            RoleEditor(role: role, onChange: reload)
        } label: {
            roleLabel(for: role)
        }
    }

    // a plain row while reordering, a link would light up under the drag
    private func reorderRow(for role: AdminRole) -> some View {
        let index = movableRoles.firstIndex { $0.id == role.id } ?? 0

        return HStack {
            roleLabel(for: role)

            if isOnMac {
                ReorderArrows(
                    canMoveUp: index > 0,
                    canMoveDown: index < movableRoles.count - 1,
                    moveUp: { move(from: IndexSet(integer: index), to: index - 1) },
                    moveDown: { move(from: IndexSet(integer: index), to: index + 2) }
                )
            }
        }
    }

    private func toggleReordering() {
        withAnimation {
            isReordering.toggle()
        }
    }

    // the new order shows straight away, the server's comes back with the reload
    private func move(from source: IndexSet, to destination: Int) {
        var moved = movableRoles

        moved.move(fromOffsets: source, toOffset: destination)

        let previous = roles
        // copied out before the task: a var captured there would need a heap box
        let roleIds = moved.map(\.id)

        roles = [ownerRole].compactMap { $0 } + moved + [defaultRole].compactMap { $0 }
        errorMessage = nil

        struct OrderInput: Encodable {
            let roleIds: [Int]
        }

        Task {
            do {
                try await session.perform("roles.reorder", OrderInput(roleIds: roleIds))
                await load()
            } catch {
                roles = previous
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addRole() {
        Task {
            do {
                struct NoInput: Encodable {}

                let _: Int = try await session.perform("roles.add", NoInput())
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct RoleEditor: View {
    // update-role.ts limits a role name to this
    private static let nameLimit = 26

    let role: AdminRole
    let onChange: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var color = Color.white
    @State private var permissions: Set<Permission> = []
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isConfirmingDelete = false

    private var memberPermissions: [Permission] {
        Permission.allCases.filter { !$0.isAdmin }
    }

    private var adminPermissions: [Permission] {
        Permission.allCases.filter(\.isAdmin)
    }

    var body: some View {
        SettingsForm {
            Section("Name") {
                TextField("", text: $name, prompt: Text("Role name"))
                    .labelsHidden()
            }

            Section("Color") {
                ColorPicker("Role color", selection: $color, supportsOpacity: false)
            }

            Section("Member Permissions") {
                ForEach(memberPermissions, id: \.self) { permission in
                    Toggle(permission.title, isOn: binding(for: permission))
                }
            }

            Section {
                ForEach(adminPermissions, id: \.self) { permission in
                    Toggle(permission.title, isOn: binding(for: permission))
                }
            } header: {
                Text("Admin Permissions")
            } footer: {
                Text("These let the role change the server itself. Give them out carefully.")
                    .wrappingFooter()
            }

            if !role.isDefault {
                Section {
                    Button("Make Default Role", action: makeDefault)
                } footer: {
                    Text("New members get the default role when they join.")
                        .wrappingFooter()
                }
            }

            if !role.isPersistent && !role.isDefault {
                SettingsActions {
                    Button("Delete Role", role: .destructive, action: confirmDelete)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.redText)
                }
            }
        }
        .settingsListStyle()
        .navigationTitle(role.name)
        .inlineNavigationTitle()
        .toolbar {
            ActionToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name.count > Self.nameLimit)
                }
            }
        }
        .confirmationDialog("Delete \(role.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Role", role: .destructive, action: delete)
        } message: {
            Text("Everyone with this role loses it.")
        }
        .onAppear(perform: fill)
    }

    private func binding(for permission: Permission) -> Binding<Bool> {
        Binding(
            get: { permissions.contains(permission) },
            set: { isOn in
                if isOn {
                    permissions.insert(permission)
                } else {
                    permissions.remove(permission)
                }
            }
        )
    }

    private func fill() {
        name = role.name
        color = Color(hex: role.color)
        permissions = Set(role.permissions)
    }

    private func save() {
        struct RoleInput: Encodable {
            let roleId: Int
            let name: String
            let color: String
            let permissions: [String]
            let storageQuotaOverrideEnabled: Bool
            let storageSpaceQuota: Int
        }

        let input = RoleInput(
            roleId: role.id,
            name: name.trimmingCharacters(in: .whitespaces),
            color: color.hexString,
            permissions: Permission.allCases.filter(permissions.contains).map(\.rawValue) + role.unknownPermissions,
            storageQuotaOverrideEnabled: role.storageQuotaOverrideEnabled,
            storageSpaceQuota: role.storageSpaceQuota
        )

        run {
            try await session.perform("roles.update", input)
            dismiss()
        }
    }

    private func makeDefault() {
        run {
            try await session.perform("roles.setDefault", ["roleId": role.id])
        }
    }

    private func confirmDelete() {
        isConfirmingDelete = true
    }

    private func delete() {
        run {
            try await session.perform("roles.delete", ["roleId": role.id])
            dismiss()
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await work()
                onChange()
            } catch {
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }
}
