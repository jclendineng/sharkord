import PhotosUI
import SwiftUI

// others.getSettings and updateSettings, the general part, and others.changeLogo
struct GeneralSettingsScreen: View {
    // the server's bounds, zGeneralSettings in update-settings.ts
    private static let nameRange = 2...24
    private static let descriptionLimit = 128
    private static let passwordLimit = 32

    @Environment(SessionStore.self) private var session

    @State private var settings: AdminServerSettings?
    @State private var saved: AdminServerSettings?
    @State private var hasPassword = false
    @State private var logoItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isUploadingLogo = false

    private var canSave: Bool {
        guard let settings else {
            return false
        }

        return !isSaving
            && Self.nameRange.contains(settings.name.trimmingCharacters(in: .whitespaces).count)
            && (settings.description ?? "").count <= Self.descriptionLimit
            && (settings.password ?? "").count <= Self.passwordLimit
            && (!hasPassword || !(settings.password ?? "").isEmpty)
    }

    var body: some View {
        Group {
            if let binding = Binding($settings) {
                form(binding)
            } else if let errorMessage {
                ContentUnavailableView("Couldn't load settings", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView()
            }
        }
        .background(Theme.deepBackground)
        .navigationTitle("Overview")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    private func form(_ settings: Binding<AdminServerSettings>) -> some View {
        List {
            Section {
                HStack(spacing: 16) {
                    ServerIcon(server: session)
                        .frame(width: 72, height: 72)
                        .clipShape(.rect(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $logoItem, matching: .images) {
                            Text("Change Icon")
                        }
                        .disabled(isUploadingLogo)

                        if session.serverInfo?.logo != nil {
                            Button("Remove Icon", role: .destructive, action: removeLogo)
                                .disabled(isUploadingLogo)
                        }

                        if isUploadingLogo {
                            ProgressView()
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section("Server Name") {
                TextField("Name", text: settings.name)
            }

            Section {
                TextField("What is this server about?", text: Binding(
                    get: { settings.wrappedValue.description ?? "" },
                    set: { settings.wrappedValue.description = $0 }
                ), axis: .vertical)
                .lineLimit(2...5)
            } header: {
                Text("Description")
            } footer: {
                Text("\((settings.wrappedValue.description ?? "").count)/\(Self.descriptionLimit)")
            }

            Section {
                Toggle("Require a Password to Join", isOn: $hasPassword)

                if hasPassword {
                    SecureField("Password", text: Binding(
                        get: { settings.wrappedValue.password ?? "" },
                        set: { settings.wrappedValue.password = $0 }
                    ))

                    Toggle("Only Ask the First Time", isOn: settings.onlyAskForPasswordOnFirstJoin)
                }
            } header: {
                Text("Access")
            }

            Section("Features") {
                Toggle("Allow New Users to Register", isOn: settings.allowNewUsers)
                Toggle("Direct Messages", isOn: settings.directMessagesEnabled)
                Toggle("Search", isOn: settings.enableSearch)
                Toggle("Plugins", isOn: settings.enablePlugins)
                Toggle("Welcome Dialog for New Members", isOn: settings.showWelcomeDialog)
                Toggle("Simulcast for Video", isOn: settings.webRtcSimulcastEnabled)
            }

            Section {
                TextField("reports@example.com", text: Binding(
                    get: { settings.wrappedValue.reportEmail ?? "" },
                    set: { settings.wrappedValue.reportEmail = $0 }
                ))
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            } header: {
                Text("Report Email")
            } footer: {
                Text("Where people send reports about this server or a message on it. Report in the apps opens an email to this address.")
            }

            Section {
                SecureField("Paste a key to turn on GIFs", text: Binding(
                    get: { settings.wrappedValue.klipyApiKey ?? "" },
                    set: { settings.wrappedValue.klipyApiKey = $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            } header: {
                Text("Klipy API Key")
            } footer: {
                Text("Turns on GIFs. Get a free key at klipy.com/developers. Searches go through this server, so the key stays private.")
            }

            if let showsContent = settings.wrappedValue.pushShowMessageContent {
                Section {
                    Toggle("Show Message Text", isOn: Binding(
                        get: { showsContent },
                        set: { settings.wrappedValue.pushShowMessageContent = $0 }
                    ))
                } header: {
                    Text("Push Notifications")
                } footer: {
                    Text("Notifications pass through Apple. Off, they only say who sent something, never what or in which channel.")
                }
            }

            if let previewsPrivate = settings.wrappedValue.linkPreviewsPrivateNetwork {
                Section {
                    Toggle("Preview Links on the Server's Network", isOn: Binding(
                        get: { previewsPrivate },
                        set: { settings.wrappedValue.linkPreviewsPrivateNetwork = $0 }
                    ))
                } header: {
                    Text("Link Previews")
                } footer: {
                    Text("Lets previews load from addresses on the server's own network, like a home server's other apps. Only with members you trust, anyone could make the server load pages only it can reach. Also previewPrivateNetwork under [links] in config.ini.")
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
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
        .onChange(of: logoItem) { _, item in
            if let item {
                uploadLogo(item)
            }
        }
    }

    private func load() async {
        do {
            let loaded: AdminServerSettings = try await session.request("others.getSettings")

            settings = loaded
            saved = loaded
            hasPassword = !(loaded.password ?? "").isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard var settings else {
            return
        }

        settings.name = settings.name.trimmingCharacters(in: .whitespaces)

        struct GeneralInput: Encodable {
            let name: String
            let description: String
            let password: String?
            let onlyAskForPasswordOnFirstJoin: Bool
            let allowNewUsers: Bool
            let directMessagesEnabled: Bool
            let enablePlugins: Bool
            let enableSearch: Bool
            let showWelcomeDialog: Bool
            let webRtcSimulcastEnabled: Bool
            let pushShowMessageContent: Bool?
            let linkPreviewsPrivateNetwork: Bool?
            let reportEmail: String?
            let klipyApiKey: String?

            // a null password clears it, which a nil optional would leave out of the json
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)

                try container.encode(name, forKey: .name)
                try container.encode(description, forKey: .description)
                try container.encode(password, forKey: .password)
                try container.encode(onlyAskForPasswordOnFirstJoin, forKey: .onlyAskForPasswordOnFirstJoin)
                try container.encode(allowNewUsers, forKey: .allowNewUsers)
                try container.encode(directMessagesEnabled, forKey: .directMessagesEnabled)
                try container.encode(enablePlugins, forKey: .enablePlugins)
                try container.encode(enableSearch, forKey: .enableSearch)
                try container.encode(showWelcomeDialog, forKey: .showWelcomeDialog)
                try container.encode(webRtcSimulcastEnabled, forKey: .webRtcSimulcastEnabled)
                try container.encodeIfPresent(pushShowMessageContent, forKey: .pushShowMessageContent)
                try container.encodeIfPresent(linkPreviewsPrivateNetwork, forKey: .linkPreviewsPrivateNetwork)
                // null clears it, an older server drops the key it doesn't know
                try container.encode(reportEmail, forKey: .reportEmail)
                try container.encode(klipyApiKey, forKey: .klipyApiKey)
            }

            private enum CodingKeys: String, CodingKey {
                case name, description, password, onlyAskForPasswordOnFirstJoin, allowNewUsers
                case directMessagesEnabled, enablePlugins, enableSearch, showWelcomeDialog, webRtcSimulcastEnabled
                case pushShowMessageContent, linkPreviewsPrivateNetwork, reportEmail, klipyApiKey
            }
        }

        let input = GeneralInput(
            name: settings.name,
            description: settings.description ?? "",
            password: hasPassword ? settings.password : nil,
            onlyAskForPasswordOnFirstJoin: settings.onlyAskForPasswordOnFirstJoin,
            allowNewUsers: settings.allowNewUsers,
            directMessagesEnabled: settings.directMessagesEnabled,
            enablePlugins: settings.enablePlugins,
            enableSearch: settings.enableSearch,
            showWelcomeDialog: settings.showWelcomeDialog,
            webRtcSimulcastEnabled: settings.webRtcSimulcastEnabled,
            pushShowMessageContent: settings.pushShowMessageContent,
            linkPreviewsPrivateNetwork: settings.linkPreviewsPrivateNetwork,
            reportEmail: trimmedOrNil(settings.reportEmail),
            klipyApiKey: trimmedOrNil(settings.klipyApiKey)
        )

        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await session.perform("others.updateSettings", input)
                await session.refreshServerInfo()
                self.saved = settings
            } catch {
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }

    private func trimmedOrNil(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespaces)

        return trimmed.isEmpty ? nil : trimmed
    }

    private func uploadLogo(_ item: PhotosPickerItem) {
        guard let address = session.address, let token = session.token else {
            return
        }

        isUploadingLogo = true
        errorMessage = nil

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw AuthAPI.RequestError(message: "Could not read that picture.")
                }

                let url = FileManager.default.temporaryDirectory.appending(path: "logo-\(UUID().uuidString).png")

                try data.write(to: url)

                defer {
                    try? FileManager.default.removeItem(at: url)
                }

                let file = try await UploadAPI.upload(fileAt: url, name: "logo.png", to: address, token: token)

                try await session.perform("others.changeLogo", ["fileId": file.id])
                await session.refreshServerInfo()
            } catch {
                errorMessage = error.localizedDescription
            }

            logoItem = nil
            isUploadingLogo = false
        }
    }

    private func removeLogo() {
        isUploadingLogo = true

        Task {
            do {
                struct NoFile: Encodable {}

                try await session.perform("others.changeLogo", NoFile())
                await session.refreshServerInfo()
            } catch {
                errorMessage = error.localizedDescription
            }

            isUploadingLogo = false
        }
    }
}
