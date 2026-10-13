import SwiftUI

// roles.getAll, add, update, delete and setDefault
struct RolesScreen: View {
    @Environment(SessionStore.self) private var session

    @State private var roles: [AdminRole] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.red)
            }

            Section {
                ForEach(roles) { role in
                    NavigationLink {
                        RoleEditor(role: role, onChange: reload)
                    } label: {
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
                }
            } footer: {
                Text("The default role is given to everyone who joins.")
            }
        }
        .settingsListStyle()
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .navigationTitle("Roles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
        List {
            Section("Name") {
                TextField("Role name", text: $name)
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
            }

            if !role.isDefault {
                Section {
                    Button("Make Default Role", action: makeDefault)
                } footer: {
                    Text("New members get the default role when they join.")
                }
            }

            if !role.isPersistent && !role.isDefault {
                Section {
                    Button("Delete Role", role: .destructive, action: confirmDelete)
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
        .navigationTitle(role.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
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
            let permissions: [Permission]
            let storageQuotaOverrideEnabled: Bool
            let storageSpaceQuota: Int
        }

        let input = RoleInput(
            roleId: role.id,
            name: name.trimmingCharacters(in: .whitespaces),
            color: color.hexString,
            permissions: Permission.allCases.filter(permissions.contains),
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
