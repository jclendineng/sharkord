import SwiftUI

@main
struct SharkordApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var servers = ServerListStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(servers)
                .task {
                    appDelegate.servers = servers
                    await servers.restore()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        servers.appDidBecomeActive()
                    }
                }
        }
    }
}
