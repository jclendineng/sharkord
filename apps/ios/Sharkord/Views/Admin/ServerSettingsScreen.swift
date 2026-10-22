import SwiftUI

// everything the web client's server settings do, so nobody has to leave the app. each
// section shows only to someone who may use it, the server checks again on every change.
// a list of pages on a phone, discord's whole window with the pages down the side on a mac
struct ServerSettingsScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var selection: ServerSettingsPage?

    private var sections: [(title: String?, pages: [ServerSettingsPage])] {
        ServerSettingsPage.sections.compactMap { section in
            let pages = section.pages.filter { $0.isAllowed(in: session) }

            return pages.isEmpty ? nil : (section.title, pages)
        }
    }

    var body: some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            splitView
        } else {
            stackView
        }
    }

    private var stackView: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.pages) { section in
                    Section {
                        ForEach(section.pages, id: \.self) { page in
                            NavigationLink {
                                page.screen
                            } label: {
                                SettingsRow(title: page.title, systemImage: page.systemImage)
                            }
                        }
                    } header: {
                        if let title = section.title {
                            Text(title)
                        }
                    }
                }
            }
            .settingsListStyle()
            .navigationTitle("Server Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: close)
                }
            }
        }
        // a page on ipad, the same size user settings opens at, rather than a narrow card
        .presentationSizing(.page)
        .presentationBackground(Theme.deepBackground)
    }

    private var splitView: some View {
        NavigationSplitView {
            // discord's settings sidebar: plain rows with a soft rounded highlight, no cards or
            // lines between them
            List(selection: $selection) {
                ForEach(sections, id: \.pages) { section in
                    Section {
                        ForEach(section.pages, id: \.self) { page in
                            SettingsSidebarRow(title: page.title, systemImage: page.systemImage, isSelected: selection == page)
                                .tag(page)
                        }
                    } header: {
                        if let title = section.title {
                            Text(title.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            .settingsSidebarStyle()
            .navigationTitle("Server Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: close)
                }
            }
        } detail: {
            // a stack of its own per page, so a page's own links push inside it and picking
            // another page starts over
            NavigationStack {
                if let selection {
                    selection.screen
                }
            }
            .id(selection)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Theme.deepBackground)
        .onAppear(perform: selectFirstPage)
    }

    private func selectFirstPage() {
        if selection == nil {
            selection = sections.first?.pages.first
        }
    }

    private func close() {
        dismiss()
    }
}

enum ServerSettingsPage: Hashable {
    case overview
    case roles
    case emoji
    case stickers
    case soundboard
    case members
    case invites
    case channels
    case storage
    case plugins

    static let sections: [(title: String?, pages: [ServerSettingsPage])] = [
        (nil, [.overview, .roles, .emoji, .stickers, .soundboard]),
        ("Community", [.members, .invites, .channels]),
        ("Server", [.storage, .plugins])
    ]

    var title: String {
        switch self {
        case .overview:
            "Overview"
        case .roles:
            "Roles"
        case .emoji:
            "Emoji"
        case .stickers:
            "Stickers"
        case .soundboard:
            "Soundboard"
        case .members:
            "Members"
        case .invites:
            "Invites"
        case .channels:
            "Channels"
        case .storage:
            "Storage"
        case .plugins:
            "Plugins"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "info.circle.fill"
        case .roles:
            "shield.lefthalf.filled"
        case .emoji:
            "face.smiling.inverse"
        case .stickers:
            "seal.fill"
        case .soundboard:
            "waveform"
        case .members:
            "person.2.fill"
        case .invites:
            "link"
        case .channels:
            "number"
        case .storage:
            "internaldrive.fill"
        case .plugins:
            "puzzlepiece.extension.fill"
        }
    }

    func isAllowed(in session: SessionStore) -> Bool {
        switch self {
        case .overview:
            session.can(.manageSettings)
        case .roles:
            session.can(.manageRoles)
        case .emoji, .stickers:
            session.can(.manageEmojis)
        case .soundboard:
            session.can(.manageSoundboard)
        case .members:
            Permission.userModeration.contains(where: session.can)
        case .invites:
            session.can(.manageInvites)
        case .channels:
            session.can(.manageChannels) || session.can(.manageCategories) || session.can(.manageChannelPermissions)
        case .storage:
            session.can(.manageStorage)
        case .plugins:
            session.can(.managePlugins)
        }
    }

    @ViewBuilder
    var screen: some View {
        switch self {
        case .overview:
            GeneralSettingsScreen()
        case .roles:
            RolesScreen()
        case .emoji:
            EmojiManagerList()
        case .stickers:
            StickersScreen()
        case .soundboard:
            SoundboardScreen()
        case .members:
            MembersScreen()
        case .invites:
            InvitesScreen()
        case .channels:
            ChannelsAdminScreen()
        case .storage:
            StorageSettingsScreen()
        case .plugins:
            PluginsScreen()
        }
    }
}
