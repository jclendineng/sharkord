import SwiftUI

struct ChatRoute: Hashable {
    let channelId: Int
}

struct ThreadRoute: Hashable {
    let parent: Message
}

// from a channel the search starts in it, from the server it covers everything
struct SearchRoute: Hashable, Identifiable {
    var channelId: Int?
    // from the messages panel: only direct messages
    var directMessages = false

    var id: Self { self }
}

extension EnvironmentValues {
    // set on the ipad's side by side layout, where search covers the whole screen as discord's
    // does rather than opening in the chat's column
    @Entry var presentSearch: (@MainActor (SearchRoute) -> Void)?
    // the ipad's, sliding a chat that covers the list back beside it
    @Entry var showChannelList: (@MainActor () -> Void)?
    // the ipad's, sliding a chat beside the list over it to the full width for typing in
    @Entry var expandChat: (@MainActor () -> Void)?
}

// a way into search: pushed on a phone, the whole screen on an ipad in landscape
struct SearchLink<Label: View>: View {
    let route: SearchRoute
    @ViewBuilder let label: Label

    @Environment(\.presentSearch) private var presentSearch
    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @State private var isDropdownPresented = false

    var body: some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            // discord's mac search drops down from the box, filters and results in it, and a
            // result opens in the window behind as the dropdown goes. handed the stores by hand:
            // on a mac a presentation is worked out before it inherits anything
            Button(action: showDropdown) {
                label
            }
            .popover(isPresented: $isDropdownPresented, arrowEdge: .top) {
                NavigationStack {
                    SearchScreen(channelId: route.channelId, directMessages: route.directMessages)
                }
                .frame(idealWidth: 460, idealHeight: 640)
                .presentationCompactAdaptation(.popover)
                .environment(session)
                .environment(servers)
            }
            .onChange(of: session.requestedChannelId) { _, channelId in
                if channelId != nil {
                    isDropdownPresented = false
                }
            }
        } else if let presentSearch {
            Button {
                presentSearch(route)
            } label: {
                label
            }
        } else {
            NavigationLink(value: route) {
                label
            }
        }
    }
}

extension SearchLink {
    private func showDropdown() {
        isDropdownPresented = true
    }
}

// the channel's own screen, opened from its name: members, media, pins, links and files
struct ChannelInfoRoute: Hashable {
    let channelId: Int
}

extension View {
    func chatDestinations() -> some View {
        navigationDestination(for: ChatRoute.self) { route in
            ChatScreen(channelId: route.channelId)
        }
        .navigationDestination(for: ThreadRoute.self) { route in
            ThreadScreen(parent: route.parent)
        }
        .navigationDestination(for: SearchRoute.self) { route in
            SearchScreen(channelId: route.channelId, directMessages: route.directMessages)
        }
        .navigationDestination(for: ChannelInfoRoute.self) { route in
            ChannelInfoScreen(channelId: route.channelId)
        }
    }
}

private struct RequestedChannelOpener: ViewModifier {
    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session
    @Binding var path: NavigationPath
    // the ipad's chat beside the list, which a channel replaces rather than being pushed onto
    var detailChannelId: Binding<Int?>?

    // the phase is part of it so a request made while connecting runs once channels arrive, and
    // whether the channel is known yet, so a direct message just opened is shown once it arrives
    private var requestKey: [AnyHashable] {
        let isKnown = session.requestedChannelId.map { session.channel($0) != nil } ?? false

        return [ObjectIdentifier(session), session.requestedChannelId, session.phase, isKnown]
    }

    // on a change rather than as a task: the home screen's tasks are cancelled while a chat or
    // the channel screen is pushed over it, which left a request made from there unanswered
    func body(content: Content) -> some View {
        content
            .onAppear(perform: openRequestedChannel)
            .onChange(of: requestKey, openRequestedChannel)
    }

    private func openRequestedChannel() {
        guard
            let channelId = session.requestedChannelId,
            let channel = session.channel(channelId)
        else {
            return
        }

        servers.isShowingDirectMessages = channel.isDm

        if let detailChannelId {
            detailChannelId.wrappedValue = channelId
            path = NavigationPath()

            // the same channel already beside the list is not opened again, so a jump to one
            // of its messages has to be asked for here
            let store = session.messages(for: channelId)

            if store.pendingJumpMessageId != nil {
                Task {
                    await store.loadIfNeeded()
                }
            }
        } else {
            path = NavigationPath([ChatRoute(channelId: channelId)])
        }

        session.requestedChannelId = nil
    }
}

extension View {
    // a tapped notification, a search result or a server picked in the rail asks for a channel
    func opensRequestedChannel(_ path: Binding<NavigationPath>, detailChannelId: Binding<Int?>? = nil) -> some View {
        modifier(RequestedChannelOpener(path: path, detailChannelId: detailChannelId))
    }
}
