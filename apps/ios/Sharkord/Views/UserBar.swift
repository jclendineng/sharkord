import SwiftUI

struct UserBar: View {
    // the ipad's, sized to sit under the channel list like discord's rather than fill a phone
    var isCompact = false

    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session

    @State private var isProfilePresented = false
    @State private var isUnreadsPresented = false
    // what the mac's profile popover opened, shown here once the popover has closed
    @State private var profileSheet: ProfileSheet?

    // the message when there is one, like discord, otherwise what was picked
    private var statusText: String {
        if let customStatus = session.ownCustomStatus, !customStatus.isEmpty {
            return customStatus
        }

        return session.ownPresence.title
    }

    private var hasUnread: Bool {
        servers.sessions.contains { !$0.unreadChannels.isEmpty }
    }

    private var cornerRadius: CGFloat {
        isCompact ? 22 : 28
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: showProfile) {
                HStack(spacing: isCompact ? 10 : 12) {
                    AvatarView(user: session.ownUser, size: isCompact ? 36 : 44, showsStatus: true)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(session.ownUser?.name ?? session.displayName)
                                .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                                .foregroundStyle(Theme.header)
                                .lineLimit(1)

                            Image(systemName: "chevron.down")
                                .font(.caption.bold())
                                .foregroundStyle(Theme.muted)
                        }

                        Text(statusText)
                            .font(isCompact ? .caption : .subheadline)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(4)
                .hoverHighlight(cornerRadius: 10)
                .padding(-4)
            }
            .buttonStyle(.plain)

            if ProcessInfo.processInfo.isiOSAppOnMac {
                // discord's mac: mute, deafen and settings at hand, the inbox up in the top bar
                UserBarButton(
                    title: session.micMuted ? "Unmute" : "Mute",
                    systemImage: session.micMuted ? "mic.slash.fill" : "mic.fill",
                    isOff: session.micMuted,
                    action: toggleMic
                )

                UserBarButton(
                    title: session.soundMuted ? "Undeafen" : "Deafen",
                    systemImage: session.soundMuted ? "headphones.slash" : "headphones",
                    isOff: session.soundMuted,
                    action: toggleSound
                )

                UserBarButton(title: "User Settings", systemImage: "gearshape.fill", isOff: false, action: openSettings)
            } else {
                unreadsButton
            }
        }
        .padding(.horizontal, isCompact ? 10 : 12)
        .padding(.vertical, isCompact ? 7 : 10)
        .background(Color(hex: "#202125"), in: .rect(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .modifier(ProfilePresentation(isPresented: $isProfilePresented) {
            ProfileScreen(onOpen: profileOpener)
                .environment(session)
                .environment(servers)
        })
        .profileSheet($profileSheet)
    }

    private var unreadsButton: some View {
        Button("Unreads", systemImage: "bell.fill", action: showUnreads)
            .labelStyle(.iconOnly)
            .font(isCompact ? .body : .title3)
            .foregroundStyle(Theme.muted)
            .frame(width: isCompact ? 36 : 44, height: isCompact ? 36 : 44)
            .hoverHighlight(cornerRadius: 10)
            .overlay(alignment: .topTrailing) {
                if hasUnread {
                    Circle()
                        .fill(Theme.red)
                        .frame(width: 10, height: 10)
                        .offset(x: -8, y: 8)
                }
            }
            // hangs off the bell on a wide screen, a phone gets a sheet. handed the stores
            // by hand: on a mac a presentation is worked out before it inherits anything
            .popover(isPresented: $isUnreadsPresented) {
                InboxSheet()
                    .frame(idealWidth: 420, idealHeight: 560)
                    .macPopover()
                    .environment(servers)
                    .environment(session)
            }
    }

    private func toggleMic() {
        Task { await session.toggleMicMuted() }
    }

    private func toggleSound() {
        Task { await session.toggleSoundMuted() }
    }

    private func openSettings() {
        profileSheet = .settings
    }

    // only the mac's popover hands them over, a phone or ipad's profile sheet shows its own
    private var profileOpener: ((ProfileSheet) -> Void)? {
        guard ProcessInfo.processInfo.isiOSAppOnMac else {
            return nil
        }

        return openFromProfile
    }

    private func openFromProfile(_ sheet: ProfileSheet) {
        isProfilePresented = false
        profileSheet = sheet
    }

    private func showProfile() {
        isProfilePresented = true
    }

    private func showUnreads() {
        isUnreadsPresented = true
    }
}

// a round icon button in the mac's user bar, red with a slash while it is off, lit and lifted a
// little under the pointer
private struct UserBarButton: View {
    let title: String
    let systemImage: String
    let isOff: Bool
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isOff ? Theme.red : Theme.muted)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 36, height: 36)
            .hoverHighlight(cornerRadius: 10)
            .hoverPop()
            .buttonStyle(.plain)
    }
}

// discord's mac opens your profile above the user bar, a phone or ipad gets the sheet
private struct ProfilePresentation<Profile: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let profile: () -> Profile

    func body(content: Content) -> some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            content
                .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                    profile()
                        // a fixed size: a mac popover takes no ideal height, and the log out
                        // at the bottom sat under a scroll
                        .frame(width: 380, height: 700)
                        .macPopover()
                }
        } else {
            content
                .sheet(isPresented: $isPresented) {
                    profile()
                        .presentationSizing(TallerFormSizing())
                        .appSheet()
                }
        }
    }
}

// the ipad's usual sheet a little taller, so the profile's log out shows without scrolling. a
// phone's sheet already runs the screen's height
private struct TallerFormSizing: PresentationSizing {
    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        let form: FormPresentationSizing = .form
        let size = form.proposedSize(for: root, context: context)

        return ProposedViewSize(width: size.width, height: size.height.map { $0 + 24 })
    }
}
