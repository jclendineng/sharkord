import PhotosUI
import SwiftUI

// others.getSettings and updateSettings, the general part, and others.changeLogo
struct GeneralSettingsScreen: View {
    // the server's bounds, zGeneralSettings in update-settings.ts
    private static let nameRange = 2...24
    private static let descriptionLimit = 128
    private static let passwordLimit = 32

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var settings: AdminServerSettings?
    @State private var saved: AdminServerSettings?
    @State private var hasPassword = false
    @State private var logoItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var isSaving = false
    // picked or removed but not saved yet, the server's icon stays until save
    @State private var pendingLogo: PendingLogo?
    @State private var isReadingLogo = false

    private enum PendingLogo {
        case replace(Data, PlatformImage)
        case remove
    }

    private var hasSettingsChanges: Bool {
        let hadPassword = !(saved?.password ?? "").isEmpty

        return settings != saved || hasPassword != hadPassword
    }

    private var showsRemoveIcon: Bool {
        switch pendingLogo {
        case .replace:
            true
        case .remove:
            false
        case nil:
            session.serverInfo?.logo != nil
        }
    }

    private var canSave: Bool {
        guard let settings else {
            return false
        }

        return !isSaving
            && !isReadingLogo
            && (hasSettingsChanges || pendingLogo != nil)
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
        .inlineNavigationTitle()
        .task {
            await load()
        }
    }

    private func form(_ settings: Binding<AdminServerSettings>) -> some View {
        List {
            Section {
                HStack(spacing: 16) {
                    iconPreview
                        .frame(width: 72, height: 72)
                        .clipShape(.rect(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $logoItem, matching: .images) {
                            Text("Change Icon")
                        }
                        .disabled(isReadingLogo || isSaving)

                        if showsRemoveIcon {
                            Button("Remove Icon", role: .destructive, action: removeLogo)
                                .disabled(isReadingLogo || isSaving)
                        }

                        if isReadingLogo {
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
                .keyboard(.email)
                .textContentType(.emailAddress)
                .noAutocapitalization()
                .autocorrectionDisabled()
            } header: {
                Text("Report Email")
            } footer: {
                Text("Where people send questions and reports about this server or a message on it. The apps show it as the contact in About, and Report opens an email to it.")
            }

            Section {
                SecureField("Paste a key to turn on GIFs", text: Binding(
                    get: { settings.wrappedValue.klipyApiKey ?? "" },
                    set: { settings.wrappedValue.klipyApiKey = $0 }
                ))
                .noAutocapitalization()
                .autocorrectionDisabled()
            } header: {
                Text("Klipy API Key")
            } footer: {
                Text("Turns on GIFs. Get a free key at klipy.com/developers. Searches go through this server, so the key stays private.")
            }

            Section {
                SecureField("Paste a key to turn on sound search", text: Binding(
                    get: { settings.wrappedValue.freesoundApiKey ?? "" },
                    set: { settings.wrappedValue.freesoundApiKey = $0 }
                ))
                .noAutocapitalization()
                .autocorrectionDisabled()
            } header: {
                Text("Freesound API Key")
            } footer: {
                Text("Turns on searching Freesound for soundboard sounds. Get a free key at freesound.org/apiv2/apply, it's the client secret. Searches go through this server, so the key stays private.")
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

            if let afkTimeout = settings.wrappedValue.afkTimeoutSeconds {
                Section {
                    Picker("AFK Channel", selection: Binding(
                        get: { settings.wrappedValue.afkChannelId },
                        set: { settings.wrappedValue.afkChannelId = $0 }
                    )) {
                        Text("None").tag(Int?.none)

                        ForEach(afkChannelChoices) { channel in
                            Text(channel.name).tag(Int?.some(channel.id))
                        }
                    }

                    Picker("AFK Timeout", selection: Binding(
                        get: { afkTimeout },
                        set: { settings.wrappedValue.afkTimeoutSeconds = $0 }
                    )) {
                        ForEach(Self.afkTimeoutChoices, id: \.self) { seconds in
                            Text(seconds == 60 ? "1 minute" : "\(seconds / 60) minutes").tag(seconds)
                        }
                    }
                    .disabled(settings.wrappedValue.afkChannelId == nil)
                } header: {
                    Text("AFK")
                } footer: {
                    Text("Members silent in a call for the timeout are moved to the AFK channel.")
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
                readLogo(item)
            }
        }
    }

    // what the icon will be once saved
    @ViewBuilder
    private var iconPreview: some View {
        switch pendingLogo {
        case .replace(_, let image):
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
        case .remove:
            Text(session.initials)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.header)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.panelControl)
        case nil:
            ServerIcon(server: session)
        }
    }


    // AFK_TIMEOUT_OPTIONS_SECONDS in packages/shared
    private static let afkTimeoutChoices = [60, 300, 900, 1800, 3600]

    private var afkChannelChoices: [Channel] {
        session.channels.filter { $0.type == .voice && !$0.isDm }
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
            let freesoundApiKey: String?
            let afkChannelId: Int?
            let afkTimeoutSeconds: Int?

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
                try container.encode(freesoundApiKey, forKey: .freesoundApiKey)

                // only a server that sent the timeout knows afk, null turns the channel off
                if let afkTimeoutSeconds {
                    try container.encode(afkChannelId, forKey: .afkChannelId)
                    try container.encode(afkTimeoutSeconds, forKey: .afkTimeoutSeconds)
                }
            }

            private enum CodingKeys: String, CodingKey {
                case name, description, password, onlyAskForPasswordOnFirstJoin, allowNewUsers
                case directMessagesEnabled, enablePlugins, enableSearch, showWelcomeDialog, webRtcSimulcastEnabled
                case pushShowMessageContent, linkPreviewsPrivateNetwork, reportEmail, klipyApiKey
                case freesoundApiKey, afkChannelId, afkTimeoutSeconds
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
            klipyApiKey: trimmedOrNil(settings.klipyApiKey),
            freesoundApiKey: trimmedOrNil(settings.freesoundApiKey),
            afkChannelId: settings.afkChannelId,
            afkTimeoutSeconds: settings.afkTimeoutSeconds
        )

        isSaving = true
        errorMessage = nil

        let logo = pendingLogo
        let settingsChanged = hasSettingsChanges

        Task {
            do {
                if let logo {
                    try await saveLogo(logo)
                }

                if settingsChanged {
                    try await session.perform("others.updateSettings", input)
                }

                await session.refreshServerInfo()

                // the picked picture goes into the cache under the file the server made of it,
                // before anything draws the new icon, so it never shows the old one or downloads
                if case .replace(let data, let image) = logo, let file = session.serverInfo?.logo, let address = session.address {
                    FileImageCache.store(data, image: image, for: file, at: address.fileURL(file))
                }

                // kept until here, so the preview does not fall back to the old icon meanwhile
                pendingLogo = nil
                self.saved = settings
                isSaving = false
                // like discord, a save closes the screen, which is how you know it went through
                dismiss()
                return
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

    // read for the preview only, the upload waits for save
    private func readLogo(_ item: PhotosPickerItem) {
        isReadingLogo = true
        errorMessage = nil

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self), let image = PlatformImage(data: data) else {
                    throw AuthAPI.RequestError(message: "Could not read that picture.")
                }

                pendingLogo = .replace(data, image)
            } catch {
                errorMessage = error.localizedDescription
            }

            logoItem = nil
            isReadingLogo = false
        }
    }

    private func removeLogo() {
        pendingLogo = .remove
    }

    private func saveLogo(_ logo: PendingLogo) async throws {
        switch logo {
        case .replace(let data, _):
            guard let address = session.address, let token = session.token else {
                return
            }

            let url = FileManager.default.temporaryDirectory.appending(path: "logo-\(UUID().uuidString).png")

            try data.write(to: url)

            defer {
                try? FileManager.default.removeItem(at: url)
            }

            let file = try await UploadAPI.upload(fileAt: url, name: "logo.png", to: address, token: token)

            try await session.perform("others.changeLogo", ["fileId": file.id])
        case .remove:
            struct NoFile: Encodable {}

            try await session.perform("others.changeLogo", NoFile())
        }
    }
}
