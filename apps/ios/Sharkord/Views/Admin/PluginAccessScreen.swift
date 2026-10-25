import SwiftUI

// plugins.getCapabilities, setCapabilityAccess and resetCapabilityAccess: who may use each
// command, action, route and component a plugin offers
struct PluginAccessScreen: View {
    let pluginId: String

    @Environment(SessionStore.self) private var session

    @State private var capabilities: [AdminPluginCapability] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    // PluginCapabilityType in packages/shared plugins/capabilities.ts
    private static let groups: [(type: String, title: String)] = [
        ("command", "Commands"),
        ("action", "Actions"),
        ("component", "Components"),
        ("http_route", "Web Routes")
    ]

    var body: some View {
        SettingsForm {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.red)
            }

            ForEach(Self.groups, id: \.type) { group in
                let items = capabilities.filter { $0.type == group.type }

                if !items.isEmpty {
                    Section(group.title) {
                        ForEach(items) { capability in
                            NavigationLink {
                                CapabilityAccessEditor(pluginId: pluginId, capability: capability, onChange: reload)
                            } label: {
                                CapabilityRow(capability: capability)
                            }
                        }
                    }
                }
            }
        }
        .settingsListStyle()
        .overlay {
            if isLoading {
                ProgressView()
            } else if capabilities.isEmpty && errorMessage == nil {
                ContentUnavailableView("Nothing to restrict", systemImage: "person.badge.key", description: Text("This plugin doesn't offer anything people use directly."))
            }
        }
        .navigationTitle("Who Can Use It")
        .inlineNavigationTitle()
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func load() async {
        struct CapabilityList: Decodable {
            let capabilities: [AdminPluginCapability]
        }

        do {
            let list: CapabilityList = try await session.request("plugins.getCapabilities", ["pluginId": pluginId])

            capabilities = list.capabilities
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

private struct CapabilityRow: View {
    let capability: AdminPluginCapability

    @Environment(SessionStore.self) private var session

    private var access: String {
        guard capability.mode == "restricted" else {
            return "Everyone"
        }

        let names = capability.roleIds.compactMap { session.rolesById[$0]?.name }

        return names.isEmpty ? "Owner only" : names.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(capability.type == "command" ? "/\(capability.name)" : capability.name)
                .font(.body.monospaced())
                .foregroundStyle(Theme.header)

            Text(capability.configured ? access : "\(access) (default)")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
    }
}

private struct CapabilityAccessEditor: View {
    let pluginId: String
    let capability: AdminPluginCapability
    let onChange: () -> Void

    @Environment(SessionStore.self) private var session

    @State private var isRestricted = false
    @State private var roleIds: Set<Int> = []
    @State private var isConfigured = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    // OWNER_ROLE_ID can use everything, so it isn't offered
    private var roles: [Role] {
        session.rolesById.values
            .filter { $0.id != 1 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        SettingsForm {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(capability.type == "command" ? "/\(capability.name)" : capability.name)
                        .font(.headline.monospaced())
                        .foregroundStyle(Theme.header)

                    if let description = capability.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }

            Section {
                Picker("Who", selection: Binding(get: { isRestricted }, set: setRestricted)) {
                    Text("Everyone").tag(false)
                    Text("Only Some Roles").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(isSaving)
            } footer: {
                if let requires = capability.requires {
                    Text("By default only roles with \(Permission(rawValue: requires)?.title ?? requires) can use it.")
                        .wrappingFooter()
                }
            }

            if isRestricted {
                Section {
                    ForEach(roles) { role in
                        Toggle(isOn: Binding(get: { roleIds.contains(role.id) }, set: { setRole(role.id, isOn: $0) })) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: role.color))
                                    .frame(width: 10, height: 10)

                                Text(role.name)
                            }
                        }
                        .disabled(isSaving)
                    }
                } header: {
                    Text("Roles")
                } footer: {
                    Text("The server owner can always use it.")
                        .wrappingFooter()
                }
            }

            if isConfigured {
                Section {
                    Button("Reset to Default", action: reset)
                        .disabled(isSaving)
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
        .navigationTitle(capability.name)
        .inlineNavigationTitle()
        .onAppear {
            isRestricted = capability.mode == "restricted"
            roleIds = Set(capability.roleIds)
            isConfigured = capability.configured
        }
    }

    private func setRestricted(_ restricted: Bool) {
        let previous = (isRestricted, roleIds)

        isRestricted = restricted
        save(onFailure: { (isRestricted, roleIds) = previous })
    }

    private func setRole(_ id: Int, isOn: Bool) {
        let previous = roleIds

        if isOn {
            roleIds.insert(id)
        } else {
            roleIds.remove(id)
        }

        save(onFailure: { roleIds = previous })
    }

    private func save(onFailure: @escaping () -> Void) {
        struct AccessInput: Encodable {
            let pluginId: String
            let type: String
            let name: String
            let mode: String
            let roleIds: [Int]
        }

        let input = AccessInput(
            pluginId: pluginId,
            type: capability.type,
            name: capability.name,
            mode: isRestricted ? "restricted" : "public",
            roleIds: isRestricted ? roleIds.sorted() : []
        )

        run(onFailure: onFailure) {
            try await session.perform("plugins.setCapabilityAccess", input)
            isConfigured = true
        }
    }

    private func reset() {
        struct ResetInput: Encodable {
            let pluginId: String
            let type: String
            let name: String
        }

        run {
            try await session.perform("plugins.resetCapabilityAccess", ResetInput(pluginId: pluginId, type: capability.type, name: capability.name))
            isRestricted = capability.defaultAccess.mode == "restricted"
            roleIds = Set(capability.defaultAccess.roleIds)
            isConfigured = false
        }
    }

    private func run(onFailure: @escaping () -> Void = {}, _ work: @escaping () async throws -> Void) {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await work()
                onChange()
            } catch {
                onFailure()
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }
}
