import SwiftUI

// plugins.get, with the marketplace a push away
struct PluginsScreen: View {
    @Environment(SessionStore.self) private var session

    @State private var plugins: [AdminPlugin] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.red)
            }

            Section {
                NavigationLink {
                    MarketplaceScreen(installed: plugins, onChange: reload)
                } label: {
                    SettingsRow(title: "Browse Plugins", systemImage: "bag.fill")
                }
            }

            if !plugins.isEmpty {
                Section("Installed") {
                    ForEach(plugins) { plugin in
                        NavigationLink {
                            PluginDetailScreen(pluginId: plugin.id, plugins: $plugins, onChange: reload)
                        } label: {
                            PluginRow(plugin: plugin)
                        }
                    }
                }
            }
        }
        .settingsListStyle()
        .overlay {
            if isLoading {
                ProgressView()
            } else if plugins.isEmpty && errorMessage == nil {
                ContentUnavailableView("No plugins", systemImage: "puzzlepiece.extension", description: Text("Browse to install one."))
                    .padding(.top, 120)
            }
        }
        .navigationTitle("Plugins")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func load() async {
        struct PluginList: Decodable {
            let plugins: [AdminPlugin]
        }

        do {
            let list: PluginList = try await session.request("plugins.get")

            plugins = list.plugins.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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

struct PluginLogo: View {
    let url: String?
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Theme.inputBackground
                }
            } else {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.inputBackground)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.25))
    }
}

private struct PluginRow: View {
    let plugin: AdminPlugin

    private var subtitle: String {
        if plugin.loadError != nil {
            return "Failed to load"
        }

        return [plugin.version.map { "v\($0)" }, plugin.enabled ? "On" : "Off"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            PluginLogo(url: plugin.logo)

            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.title)
                    .foregroundStyle(Theme.header)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(plugin.loadError == nil ? Theme.muted : Theme.red)
            }
        }
    }
}

// plugins.toggle and remove, and the way into a plugin's settings, access and logs
private struct PluginDetailScreen: View {
    let pluginId: String
    @Binding var plugins: [AdminPlugin]
    let onChange: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var isConfirmingRemove = false

    private var plugin: AdminPlugin? {
        plugins.first { $0.id == pluginId }
    }

    var body: some View {
        List {
            if let plugin {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        PluginLogo(url: plugin.logo, size: 56)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(plugin.title)
                                .font(.title3.bold())
                                .foregroundStyle(Theme.header)

                            Text([plugin.author.flatMap { $0.isEmpty ? nil : "by \($0)" }, plugin.version.flatMap { $0.isEmpty ? nil : "v\($0)" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                    }

                    if let description = plugin.description, !description.isEmpty {
                        Text(description)
                            .foregroundStyle(Theme.text)
                    }

                    if let homepage = plugin.homepage, let url = URL(string: homepage) {
                        Button("Homepage", systemImage: "safari") { openURL(url) }
                    }
                }

                if let loadError = plugin.loadError {
                    Section("Load Error") {
                        Text(loadError)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.red)
                    }
                }

                Section {
                    Toggle("Enabled", isOn: Binding(get: { plugin.enabled }, set: toggle))
                        .disabled(isWorking)
                }

                Section {
                    NavigationLink {
                        PluginSettingsScreen(pluginId: pluginId)
                    } label: {
                        SettingsRow(title: "Settings", systemImage: "slider.horizontal.3")
                    }

                    if session.can(.managePluginPermissions) {
                        NavigationLink {
                            PluginAccessScreen(pluginId: pluginId)
                        } label: {
                            SettingsRow(title: "Who Can Use It", systemImage: "person.badge.key.fill")
                        }
                    }

                    NavigationLink {
                        PluginLogsScreen(pluginId: pluginId)
                    } label: {
                        SettingsRow(title: "Logs", systemImage: "text.alignleft")
                    }
                }

                Section {
                    Button("Remove Plugin", role: .destructive) { isConfirmingRemove = true }
                        .disabled(isWorking)
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
        .navigationTitle(plugin?.title ?? "Plugin")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove \(plugin?.title ?? "plugin")?", isPresented: $isConfirmingRemove, titleVisibility: .visible) {
            Button("Remove Plugin", role: .destructive, action: remove)
        } message: {
            Text("Its files are deleted from the server. Anything it stored stays until you reinstall or clear it.")
        }
    }

    private func toggle(_ enabled: Bool) {
        struct ToggleInput: Encodable {
            let pluginId: String
            let enabled: Bool
        }

        run {
            try await session.perform("plugins.toggle", ToggleInput(pluginId: pluginId, enabled: enabled))
            onChange()
        }
    }

    private func remove() {
        run {
            try await session.perform("plugins.remove", ["pluginId": pluginId])
            onChange()
            dismiss()
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil

        Task {
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }

            isWorking = false
        }
    }
}

// plugins.getSettings and updateSetting, the server wide settings a plugin registered
private struct PluginSettingsScreen: View {
    let pluginId: String

    @Environment(SessionStore.self) private var session

    @State private var definitions: [AdminPluginSettings.Definition] = []
    @State private var values: [String: PluginSettingValue] = [:]
    @State private var saved: [String: PluginSettingValue] = [:]
    @State private var secretsSet: Set<String> = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isSaving = false

    private var changedKeys: [String] {
        definitions.map(\.key).filter { values[$0] != saved[$0] }
    }

    var body: some View {
        List {
            ForEach(definitions) { definition in
                Section {
                    field(for: definition)
                } footer: {
                    if let description = definition.description, !description.isEmpty {
                        Text(description)
                    }
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
        .overlay {
            if isLoading {
                ProgressView()
            } else if definitions.isEmpty && errorMessage == nil {
                ContentUnavailableView("No settings", systemImage: "slider.horizontal.3", description: Text("This plugin has nothing to configure."))
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save", action: save)
                        .disabled(changedKeys.isEmpty)
                }
            }
        }
        .task {
            await load()
        }
    }

    @ViewBuilder
    private func field(for definition: AdminPluginSettings.Definition) -> some View {
        switch definition.type {
        case "boolean":
            Toggle(definition.name, isOn: Binding(
                get: {
                    if case .bool(let value) = values[definition.key] {
                        return value
                    }

                    return false
                },
                set: { values[definition.key] = .bool($0) }
            ))
        case "enum":
            Picker(definition.name, selection: Binding(
                get: { text(values[definition.key]) },
                set: { values[definition.key] = .string($0) }
            )) {
                ForEach(definition.options ?? [], id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
        case "number":
            LabeledContent(definition.name) {
                TextField("0", text: Binding(
                    get: { text(values[definition.key]) },
                    set: { values[definition.key] = Double($0).map(PluginSettingValue.number) ?? values[definition.key] }
                ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            }
        case "secret":
            VStack(alignment: .leading, spacing: 4) {
                Text(definition.name)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)

                SecureField(secretsSet.contains(definition.key) ? "Saved, type to replace" : "Not set", text: Binding(
                    get: { text(values[definition.key]) },
                    set: { values[definition.key] = .string($0) }
                ))
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(definition.name)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)

                TextField(definition.name, text: Binding(
                    get: { text(values[definition.key]) },
                    set: { values[definition.key] = .string($0) }
                ), axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
        }
    }

    private func text(_ value: PluginSettingValue?) -> String {
        switch value {
        case .string(let string):
            string
        case .number(let number):
            number.rounded() == number ? String(Int(number)) : String(number)
        case .bool(let bool):
            String(bool)
        case nil:
            ""
        }
    }

    private func load() async {
        do {
            let loaded: AdminPluginSettings = try await session.request("plugins.getSettings", ["pluginId": pluginId])
            var current: [String: PluginSettingValue] = [:]

            for definition in loaded.definitions {
                // a secret never comes back, an empty field leaves the saved one alone
                if definition.type == "secret" {
                    current[definition.key] = .string("")
                } else {
                    current[definition.key] = (loaded.values[definition.key] ?? nil) ?? definition.defaultValue
                }
            }

            definitions = loaded.definitions
            values = current
            saved = current
            secretsSet = Set(loaded.secretsSet)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func save() {
        struct SettingInput: Encodable {
            let pluginId: String
            let key: String
            let value: PluginSettingValue
        }

        let changes = changedKeys.compactMap { key in values[key].map { (key, $0) } }

        isSaving = true
        errorMessage = nil

        Task {
            for (key, value) in changes {
                do {
                    try await session.perform("plugins.updateSetting", SettingInput(pluginId: pluginId, key: key, value: value))

                    saved[key] = value

                    if let definition = definitions.first(where: { $0.key == key }), definition.type == "secret" {
                        secretsSet.insert(key)
                        values[key] = .string("")
                        saved[key] = .string("")
                    }
                } catch {
                    let name = definitions.first { $0.key == key }?.name ?? key

                    errorMessage = "\(name): \(error.localizedDescription)"
                }
            }

            isSaving = false
        }
    }
}

// plugins.getLogs, newest first
private struct PluginLogsScreen: View {
    let pluginId: String

    @Environment(SessionStore.self) private var session

    @State private var logs: [AdminPluginLog] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.red)
            }

            ForEach(Array(logs.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.type.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(color(for: entry.type))

                        Text(Date(timeIntervalSince1970: TimeInterval(entry.timestamp) / 1000).formatted(date: .abbreviated, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }

                    Text(entry.message)
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                }
            }
        }
        .settingsListStyle()
        .overlay {
            if isLoading {
                ProgressView()
            } else if logs.isEmpty && errorMessage == nil {
                ContentUnavailableView("No logs", systemImage: "text.alignleft")
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func color(for type: String) -> Color {
        switch type {
        case "error":
            Theme.red
        case "debug":
            Theme.muted
        default:
            Theme.blurple
        }
    }

    private func load() async {
        do {
            let loaded: [AdminPluginLog] = try await session.request("plugins.getLogs", ["pluginId": pluginId])

            logs = loaded.sorted { $0.timestamp > $1.timestamp }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
