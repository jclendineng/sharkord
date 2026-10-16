import SwiftUI

// the plugin registry the web client's marketplace reads, installed and updated through
// plugins.install and plugins.update, which download and check the version server side
struct MarketplaceScreen: View {
    let installed: [AdminPlugin]
    let onChange: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @State private var entries: [MarketplaceEntry] = []
    @State private var query = ""
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var busyId: String?
    @State private var confirming: MarketplaceEntry?
    @State private var installedVersions: [String: String] = [:]

    private var shown: [MarketplaceEntry] {
        guard !query.isEmpty else {
            return entries
        }

        return entries.filter { entry in
            let plugin = entry.plugin

            return plugin.name.localizedCaseInsensitiveContains(query)
                || plugin.description.localizedCaseInsensitiveContains(query)
                || plugin.author.localizedCaseInsensitiveContains(query)
                || (plugin.tags ?? []).contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.red)
            }

            ForEach(shown) { entry in
                MarketplaceRow(
                    entry: entry,
                    installedVersion: installedVersions[entry.id],
                    isBusy: busyId == entry.id,
                    onInstall: { confirming = entry }
                )
            }
        }
        .settingsListStyle()
        .searchable(text: $query, prompt: "Search plugins")
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .navigationTitle("Browse Plugins")
        .navigationBarTitleDisplayMode(.inline)
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .sheet(item: $confirming) { entry in
            InstallWarningSheet(entry: entry, isUpdate: installedVersions[entry.id] != nil) {
                install(entry)
            }
                .environment(session)
                .environment(servers)
                .appSheet()
        }
        .task {
            installedVersions = Dictionary(installed.map { ($0.id, $0.version ?? "") }, uniquingKeysWith: { first, _ in first })
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func load() async {
        do {
            let (data, response) = try await URLSession.shared.data(from: MarketplaceEntry.registryURL)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            // the registry is read row by row, so one malformed plugin doesn't hide the rest
            let rows = try JSONDecoder().decode([LenientEntry].self, from: data)

            entries = rows
                .compactMap(\.entry)
                .sorted { ($0.versions.map(\.timestamp).max() ?? 0) > ($1.versions.map(\.timestamp).max() ?? 0) }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load the plugin list. \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func install(_ entry: MarketplaceEntry) {
        guard let version = entry.latestCompatible else {
            return
        }

        struct InstallInput: Encodable {
            let pluginId: String
            let version: String
        }

        let isUpdate = installedVersions[entry.id] != nil

        busyId = entry.id
        errorMessage = nil

        Task {
            do {
                try await session.perform(isUpdate ? "plugins.update" : "plugins.install", InstallInput(pluginId: entry.id, version: version.version))
                installedVersions[entry.id] = version.version
                onChange()
            } catch {
                errorMessage = "\(entry.plugin.name): \(error.localizedDescription)"
            }

            busyId = nil
        }
    }
}

private struct LenientEntry: Decodable {
    let entry: MarketplaceEntry?

    init(from decoder: Decoder) throws {
        entry = try? MarketplaceEntry(from: decoder)
    }
}

private struct MarketplaceRow: View {
    let entry: MarketplaceEntry
    let installedVersion: String?
    let isBusy: Bool
    let onInstall: () -> Void

    private var hasUpdate: Bool {
        guard let installedVersion, let latest = entry.latestCompatible else {
            return false
        }

        return latest.version.compare(installedVersion, options: .numeric) == .orderedDescending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                PluginLogo(url: entry.plugin.logo, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.plugin.name)
                            .font(.headline)
                            .foregroundStyle(Theme.header)

                        if entry.plugin.verified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.blurple)
                        }
                    }

                    Text([entry.plugin.author, entry.latestCompatible.map { "v\($0.version)" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                Spacer()

                action
            }

            Text(entry.plugin.description)
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var action: some View {
        if isBusy {
            ProgressView()
        } else if entry.latestCompatible == nil {
            Text("Not compatible")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        } else if hasUpdate {
            Button("Update", action: onInstall)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        } else if installedVersion != nil {
            Label("Installed", systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(Theme.green)
        } else {
            Button("Install", action: onInstall)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}

// the web client's warning before a plugin goes on the server, plugin-install-confirm
private struct InstallWarningSheet: View {
    // the web client holds the button back as long, so the warning gets read
    private static let countdown = 5

    let entry: MarketplaceEntry
    let isUpdate: Bool
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var remaining = countdown

    private var buttonTitle: String {
        if remaining > 0 {
            return "Wait (\(remaining)s)"
        }

        return isUpdate ? "Update Plugin" : "Install Plugin"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Plugins are a powerful way to extend Sharkord, and they carry real risk. A plugin runs inside the server with nothing around it.")
                        .foregroundStyle(Theme.text)
                }

                Section {
                    warning("Can read, change or delete all server data", systemImage: "externaldrive.fill")
                    warning("Can run any code on the server", systemImage: "terminal.fill")
                    warning("A malicious one can take over accounts, steal data or damage the server", systemImage: "exclamationmark.shield.fill")
                } footer: {
                    Text("Running Sharkord in Docker keeps the damage contained. Only install plugins you trust.")
                }

                Section {
                    Button(action: confirm) {
                        Text(buttonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(remaining > 0)
                }
            }
            .settingsListStyle()
            .navigationTitle(isUpdate ? "Update \(entry.plugin.name)?" : "Install \(entry.plugin.name)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }
            }
            .task {
                while remaining > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    remaining -= 1
                }
            }
        }
        .sheetDetents([.medium, .large])
        .presentationBackground(Theme.deepBackground)
    }

    private func warning(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
                .foregroundStyle(Theme.header)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.red)
        }
    }

    private func confirm() {
        dismiss()
        onConfirm()
    }

    private func close() {
        dismiss()
    }
}
