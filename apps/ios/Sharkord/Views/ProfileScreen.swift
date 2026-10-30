import SwiftUI

// discord's own profile sheet: banner, avatar over its edge, edit button, then cards
struct ProfileScreen: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    // the mac's profile is a popover over the user bar, which takes what it opens so the popover
    // can close first: a sheet shown from the popover left it open behind
    var onOpen: ((ProfileSheet) -> Void)?

    @State private var sheet: ProfileSheet?

    private var user: PublicUser? {
        session.ownUser
    }

    private var roles: [Role] {
        user?.roleIds.compactMap { session.rolesById[$0] } ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ProfileBanner(user: user)

                HStack(alignment: .bottom, spacing: 6) {
                    AvatarView(user: user, size: 92, showsStatus: true)
                        .padding(6)
                        .background(Theme.deepBackground, in: .circle)

                    // discord's thought bubble beside the avatar, the status message or a nudge
                    Button(action: setStatus) {
                        Label(
                            session.ownCustomStatus ?? "Set a status",
                            systemImage: session.ownCustomStatus == nil ? "plus.circle.fill" : "bubble.left.fill"
                        )
                        .font(.subheadline.italic())
                        .foregroundStyle(session.ownCustomStatus == nil ? Theme.muted : Theme.text)
                        .lineLimit(2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.listBackground, in: .capsule)
                        .overlay {
                            Capsule().stroke(Theme.divider, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    // clear of the banner above it, its outline included
                    .padding(.bottom, 4)
                }
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .offset(y: -50)
                .padding(.bottom, -50)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user?.name ?? "")
                            .font(.title.bold())
                            .foregroundStyle(Theme.header)

                        Text(session.displayName)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)

                        if !roles.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(roles) { role in
                                    RoleChip(role: role)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    Button(action: edit) {
                        Label("Edit Profile", systemImage: "pencil")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.blurple, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    if let bio = user?.bio, !bio.isEmpty {
                        ProfileCard(title: "About Me") {
                            Text(bio)
                                .foregroundStyle(Theme.text)
                        }
                    }

                    if let memberSince = user?.memberSince {
                        ProfileCard(title: "Member Since") {
                            Label(memberSince.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                .foregroundStyle(Theme.text)
                        }
                    }

                    Button(action: showFriends) {
                        HStack {
                            Text("Friends")
                                .font(.headline)
                                .foregroundStyle(Theme.header)

                            Spacer()

                            Text("\(session.friendLists.friends.count)")
                                .foregroundStyle(Theme.muted)

                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(16)
                        .background(Theme.listBackground, in: .rect(cornerRadius: 12))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    ProfileCard(title: "Server") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.displayName)
                                .foregroundStyle(Theme.text)

                            if let host = session.address?.baseURL.host() {
                                Text(host)
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }

                    Button(role: .destructive, action: signOut) {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .foregroundStyle(Theme.redText)
                    .background(Theme.listBackground, in: .rect(cornerRadius: 12))
                }
                .padding(16)
            }
        }
        .background(Theme.deepBackground)
        .overlay(alignment: .topLeading) {
            // a mac's popover closes with a click outside it, as the member profile beside it does
            if !Platform.isMac {
                BannerButton(title: "Close", systemImage: "xmark", weight: .bold, size: 15, action: close)
                    .padding(10)
            }
        }
        .overlay(alignment: .topTrailing) {
            BannerButton(title: "Settings", systemImage: "gearshape.fill", weight: .semibold, size: 17, action: showSettings)
                .padding(10)
        }
        .presentationDragIndicator(.visible)
        .profileSheet($sheet)
        // settings opens over this sheet, and a switch there would otherwise show here only
        // once it closed, see SettingsSheet
        .appAppearance(isSheet: true)
    }

    private func open(_ sheet: ProfileSheet) {
        if let onOpen {
            onOpen(sheet)
        } else {
            self.sheet = sheet
        }
    }

    private func showFriends() {
        open(.friends)
    }

    private func setStatus() {
        open(.status)
    }

    private func showSettings() {
        open(.settings)
    }

    private func edit() {
        open(.edit)
    }

    private func close() {
        dismiss()
    }

    private func signOut() {
        dismiss()
        servers.remove(session)
    }
}

enum ProfileSheet: Identifiable {
    case edit
    case settings
    case status
    case friends

    var id: Self {
        self
    }
}

extension View {
    func profileSheet(_ sheet: Binding<ProfileSheet?>) -> some View {
        modifier(ProfileSheetPresentation(sheet: sheet))
    }
}

private struct ProfileSheetPresentation: ViewModifier {
    @Environment(\.usesDesktopLayout) private var usesDesktopLayout

    @Binding var sheet: ProfileSheet?

    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session

    // settings take the whole window on a mac, as discord's do, the rest are sheets
    private var isFullWindow: Bool {
        usesDesktopLayout && sheet == .settings
    }

    private var sheetBinding: Binding<ProfileSheet?> {
        Binding(
            get: { isFullWindow ? nil : sheet },
            set: { sheet = $0 }
        )
    }

    private var fullWindowBinding: Binding<ProfileSheet?> {
        Binding(
            get: { isFullWindow ? sheet : nil },
            set: { sheet = $0 }
        )
    }

    // handed over by hand: on a mac a sheet's background is worked out before it inherits
    // anything, so a sheet reading a store it was not given crashed on opening
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    func body(content: Content) -> some View {
        content
            #if os(macOS)
            // a mac's settings are the settings window, opened in place of a sheet
            .onChange(of: sheet) {
                if sheet == .settings {
                    sheet = nil
                    openSettings()
                }
            }
            #endif
            .sheet(item: sheetBinding) { sheet in
                screen(for: sheet)
                    .appSheet()
            }
            .fullScreen(item: fullWindowBinding) { sheet in
                screen(for: sheet)
                    .appSheet()
            }
    }

    private func screen(for sheet: ProfileSheet) -> some View {
        Group {
            switch sheet {
            case .edit:
                EditProfileSheet()
            case .settings:
                SettingsSheet()
            case .status:
                SetStatusSheet()
            case .friends:
                AddFriendsSheet()
            }
        }
        .environment(session)
        .environment(servers)
    }
}

// a round button over the banner. the whole circle and a little around it takes the tap, not
// just the glyph, which on an ipad's sheet is easy to miss
private struct BannerButton: View {
    let title: String
    let systemImage: String
    let weight: Font.Weight
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.35), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct ProfileBanner: View {
    let user: PublicUser?

    @Environment(SessionStore.self) private var session

    var body: some View {
        Color(hex: user?.profileColor ?? "#5865F2")
            .frame(height: 130)
            .overlay {
                if let banner = user?.banner, let address = session.address {
                    CachedFileImage(file: banner, url: address.fileURL(banner)) {
                        Color.clear
                    }
                }
            }
            .clipped()
    }
}

struct ProfileCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.muted)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.listBackground, in: .rect(cornerRadius: 12))
    }
}

// the flair beside a name, a role in its own color
struct RoleChip: View {
    let role: Role

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: role.color))
                .frame(width: 9, height: 9)

            Text(role.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Theme.listBackground, in: .capsule)
    }
}
