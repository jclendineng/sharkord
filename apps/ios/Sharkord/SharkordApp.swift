import SwiftUI

@main
struct SharkordApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var servers = ServerListStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .guardsLeavingLinks(servers: servers)
                .environment(servers)
                .task {
                    KeyboardMetrics.start()
                    appDelegate.servers = servers
                    await servers.restore()
                }
                // sharkord:// links, invites and sign in codes alike, which work with any server
                // since nothing ties the app to one domain
                .onOpenURL { url in
                    servers.open(inviteURL: url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        servers.appDidBecomeActive()
                    case .background:
                        servers.appDidEnterBackground()
                    default:
                        break
                    }
                }
        }
    }
}
