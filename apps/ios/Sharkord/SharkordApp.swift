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
                // the sharkord:// scheme, and the server's own invite links once ios hands them over
                .onOpenURL { url in
                    servers.open(inviteURL: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        servers.open(inviteURL: url)
                    }
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
