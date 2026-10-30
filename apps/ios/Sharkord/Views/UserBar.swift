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

    private var horizontalPadding: CGFloat {
        isCompact ? 10 : 12
    }

    private var verticalPadding: CGFloat {
        isCompact ? 7 : 10
    }

    // the profile's highlight stops this far from the bar's edge all round, its corners the
    // bar's less that gap. a smaller radius left dark corners against the bar's rounded ends
    private static let highlightGap: CGFloat = 3

    private var profileHighlightRadius: CGFloat {
        cornerRadius - Self.highlightGap
    }

    private var buttonHighlightRadius: CGFloat {
        cornerRadius - verticalPadding
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
                .padding(.horizontal, horizontalPadding - Self.highlightGap)
                .padding(.vertical, verticalPadding - Self.highlightGap)
                .hoverHighlight(cornerRadius: profileHighlightRadius)
                .padding(.horizontal, Self.highlightGap - horizontalPadding)
                .padding(.vertical, Self.highlightGap - verticalPadding)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // the system's pointer platter drew under the highlight, in a shape of its own
            .noHoverEffect()

            if Platform.isMac {
                // discord's mac: mute, deafen and settings at hand, the inbox up in the top bar
                UserBarButton(
                    title: session.micMuted ? "Unmute" : "Mute",
                    systemImage: session.micMuted ? "mic.slash.fill" : "mic.fill",
                    isOff: session.micMuted,
                    highlightRadius: buttonHighlightRadius,
                    action: toggleMic
                )

                UserBarButton(
                    title: session.soundMuted ? "Undeafen" : "Deafen",
                    systemImage: session.soundMuted ? "headphones.slash" : "headphones",
                    isOff: session.soundMuted,
                    highlightRadius: buttonHighlightRadius,
                    action: toggleSound
                )

                UserBarButton(
                    title: "User Settings",
                    systemImage: "gearshape.fill",
                    isOff: false,
                    highlightRadius: buttonHighlightRadius,
                    action: openSettings
                )
            } else {
                unreadsButton
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        // the shadow on the bar's shape alone: on the whole bar it fell under each hover
        // highlight too, a dark band beneath it. kept small and light, a wide dark one read as a
        // black box around the bar on the panel's dark background
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.raisedBackground)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.panelEdge, lineWidth: 1)
        }
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .modifier(ProfilePresentation(isPresented: $isProfilePresented) {
            ProfileScreen(onOpen: profileOpener)
                .environment(session)
                .environment(servers)
        })
        .profileSheet($profileSheet)
        .onChange(of: servers.settingsRequests, openSettings)
    }

    private var unreadsButton: some View {
        Button(action: showUnreads) {
            Label("Unreads", systemImage: "bell.fill")
                .labelStyle(.iconOnly)
                .font(isCompact ? .body : .title3)
                .foregroundStyle(Theme.muted)
                .frame(width: isCompact ? 36 : 44, height: isCompact ? 36 : 44)
                .contentShape(.rect(cornerRadius: 10))
        }
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
        guard Platform.isMac else {
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
    let highlightRadius: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isOff ? Theme.redText : Theme.muted)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .contentShape(.rect(cornerRadius: highlightRadius))
        }
        .hoverHighlight(cornerRadius: highlightRadius)
            .hoverPop()
            .buttonStyle(.plain)
            .noHoverEffect()
    }
}

// discord's mac opens your profile above the user bar, a phone or ipad gets the sheet
private struct ProfilePresentation<Profile: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let profile: () -> Profile

    func body(content: Content) -> some View {
        if Platform.isMac {
            content
                .popover(isPresented: $isPresented, opensAwayFrom: .bottom) {
                    profile()
                        // its content's own height: a mac popover takes no ideal height, and
                        // the log out at the bottom sat under a scroll
                        .frame(width: 380)
                        .fixedSize(horizontal: false, vertical: true)
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
