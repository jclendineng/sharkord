import SwiftUI

// discord's layout: the server rail on the left, the picked server's channels or the direct
// messages next to it, the user bar along the bottom
struct HomeView: View {
    static let coordinateSpace = "home"

    let session: SessionStore

    @Environment(ServerListStore.self) private var servers

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HStack(spacing: 0) {
                ServerRail(onSelectServer: selectServer, onSelectDirectMessages: showDirectMessages)

                panel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        // the rail's color melts into the list's instead of meeting an edge, and
                        // both run under the status bar and the user bar
                        LinearGradient(
                            stops: [
                                .init(color: Theme.deepBackground, location: 0),
                                .init(color: Theme.listBackground, location: 0.12)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .ignoresSafeArea()
                    }
                    .id(ObjectIdentifier(session))
            }
            .background(Theme.deepBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 6) {
                    if let voiceSession = servers.voiceSession {
                        VoiceBar()
                            .environment(voiceSession)
                    }

                    UserBar()
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .background {
                    // the list fades out under the floating bars rather than stopping at a band
                    LinearGradient(
                        colors: [Theme.deepBackground.opacity(0), Theme.deepBackground.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .padding(.top, -48)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .chatDestinations()
            .opensRequestedChannel($path)
        }
        .environment(session)
        .coordinateSpace(.named(Self.coordinateSpace))
        .overlay {
            if let menu = servers.railMenu {
                ServerRailMenu(menu: menu)
                    .environment(session)
            }
        }
        .animation(.snappy(duration: 0.2), value: servers.railMenu?.server.id)
        .overlay(alignment: .top) {
            if let toastMessage = session.toastMessage {
                ErrorToast(message: toastMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: session.toastMessage)
        .onChange(of: ObjectIdentifier(session)) {
            path = NavigationPath()
        }
        .sheet(isPresented: needsServerPassword) {
            ServerPasswordView()
                .environment(session)
                .interactiveDismissDisabled()
        }
    }

    @ViewBuilder
    private var panel: some View {
        if servers.isShowingDirectMessages {
            DirectMessagesPanel(onOpen: openChannel)
        } else {
            switch session.phase {
            case .signedOut:
                SignedOutPanel()
            case .connecting, .needsServerPassword:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .connected, .reconnecting:
                ChannelListPanel()
            }
        }
    }

    private var needsServerPassword: Binding<Bool> {
        Binding(
            get: { session.phase == .needsServerPassword },
            set: { _ in }
        )
    }

    // a different server opens its default channel straight away, like discord does
    private func selectServer(_ selected: SessionStore) {
        let isSameServer = selected === session

        servers.select(selected)

        if !isSameServer, let channelId = selected.defaultChannelId {
            selected.requestedChannelId = channelId
        }
    }

    private func showDirectMessages() {
        servers.isShowingDirectMessages = true
    }

    private func openChannel(_ channelId: Int) {
        path.append(ChatRoute(channelId: channelId))
    }
}

private struct SignedOutPanel: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session

    var body: some View {
        ContentUnavailableView {
            Label("Signed out of \(session.displayName)", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            if let errorMessage = session.errorMessage {
                Text(errorMessage)
            }
        } actions: {
            Button("Log In", action: signIn)
                .buttonStyle(.borderedProminent)
        }
    }

    private func signIn() {
        servers.signInAgain(session)
    }
}

struct PanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Theme.header)
                .lineLimit(1)

            trailing

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}
