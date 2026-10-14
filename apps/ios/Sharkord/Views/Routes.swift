import SwiftUI

struct ChatRoute: Hashable {
    let channelId: Int
}

struct ThreadRoute: Hashable {
    let parent: Message
}

// from a channel the search starts in it, from the server it covers everything
struct SearchRoute: Hashable {
    var channelId: Int?
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
            SearchScreen(channelId: route.channelId)
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

    // the phase is part of it so a request made while connecting runs once channels arrive, and
    // whether the channel is known yet, so a direct message just opened is shown once it arrives
    private var requestKey: [AnyHashable] {
        let isKnown = session.requestedChannelId.map { session.channel($0) != nil } ?? false

        return [ObjectIdentifier(session), session.requestedChannelId, session.phase, isKnown]
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
