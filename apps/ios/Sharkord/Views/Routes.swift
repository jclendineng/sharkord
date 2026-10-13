import SwiftUI

struct ChatRoute: Hashable {
    let channelId: Int
}

struct ThreadRoute: Hashable {
    let parent: Message
}

struct SearchRoute: Hashable {}

extension View {
    func chatDestinations() -> some View {
        navigationDestination(for: ChatRoute.self) { route in
            ChatScreen(channelId: route.channelId)
        }
        .navigationDestination(for: ThreadRoute.self) { route in
            ThreadScreen(parent: route.parent)
        }
        .navigationDestination(for: SearchRoute.self) { _ in
            SearchScreen()
        }
    }
}

private struct RequestedChannelOpener: ViewModifier {
    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session
    @Binding var path: NavigationPath

    // the phase is part of it so a request made while connecting runs once channels arrive
    private var requestKey: [AnyHashable] {
        [ObjectIdentifier(session), session.requestedChannelId, session.phase]
    }

    func body(content: Content) -> some View {
        content.task(id: requestKey) {
            guard
                let channelId = session.requestedChannelId,
                let channel = session.channel(channelId)
            else {
                return
            }

            servers.isShowingDirectMessages = channel.isDm
            path = NavigationPath([ChatRoute(channelId: channelId)])
            session.requestedChannelId = nil
        }
    }
}

extension View {
    // a tapped notification, a search result or a server picked in the rail asks for a channel
    func opensRequestedChannel(_ path: Binding<NavigationPath>) -> some View {
        modifier(RequestedChannelOpener(path: path))
    }
}
