import SwiftUI

@main
struct SharkordApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    #else
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    #endif
    @State private var servers = ServerListStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                // the mac's right click menus, drawn over everything else in the window
                .overlay {
                    PointerMenuLayer()
                }
                .phoneControlStyle()
                .windowTitleBlank()
                .macWindowMinimumSize()
                .guardsLeavingLinks(servers: servers)
                .environment(servers)
                .task {
                    KeyboardMetrics.start()
                    AudioInputPreference.start()
                    PushToTalk.start(servers: servers)
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
        // a mac opens a new window at its content's smallest otherwise
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…", action: requestSettings)
                    .keyboardShortcut(",")
            }
        }
    }

    private func requestSettings() {
        servers.settingsRequests += 1
    }
}
