import SwiftUI

// the menu bar's own items, so what the window offers can also be found, and run from the
// keyboard, there. a mac's Settings… comes from its settings window, an ipad's is added here
struct AppCommands: Commands {
    let servers: ServerListStore

    private var hasServer: Bool {
        servers.selectedSession != nil
    }

    private var voiceSession: SessionStore? {
        servers.voiceSession
    }

    var body: some Commands {
        #if os(iOS)
        CommandGroup(replacing: .appSettings) {
            Button("Settings…", action: requestSettings)
                .keyboardShortcut(",")
        }
        #endif

        CommandGroup(after: .newItem) {
            Button("New Message…", action: requestNewMessage)
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!hasServer)
        }

        CommandGroup(before: .toolbar) {
            #if os(macOS)
            Button(servers.isSidebarHidden ? "Show Sidebar" : "Hide Sidebar", action: toggleSidebar)
                .keyboardShortcut("s", modifiers: [.command, .control])

            Divider()
            #endif

            Button("Back", action: servers.goBack)
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!servers.canGoBack)

            Button("Forward", action: servers.goForward)
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!servers.canGoForward)

            Divider()
        }

        CommandMenu("Server") {
            Button("Search…", action: requestSearch)
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!hasServer)

            Button("Direct Messages", action: showDirectMessages)
                .keyboardShortcut("d", modifiers: [.command, .option])
                .disabled(!hasServer)

            Divider()

            Button("Previous Server", action: showPreviousServer)
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(servers.sessions.count < 2)

            Button("Next Server", action: showNextServer)
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(servers.sessions.count < 2)

            Divider()

            Button("Add a Server…", action: servers.addServer)
        }

        CommandMenu("Call") {
            Button(voiceSession?.micMuted == true ? "Unmute" : "Mute", action: toggleMic)
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(voiceSession == nil)

            Button(voiceSession?.soundMuted == true ? "Undeafen" : "Deafen", action: toggleSound)
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(voiceSession == nil)

            Divider()

            Button("Show Call", action: showCall)
                .disabled(voiceSession == nil)

            Button("Leave Call", action: leaveCall)
                .disabled(voiceSession == nil)
        }
    }

    private func requestSettings() {
        servers.settingsRequests += 1
    }

    private func requestNewMessage() {
        servers.isShowingDirectMessages = true
        servers.isNewMessageRequested = true
    }

    private func toggleSidebar() {
        servers.sidebarToggleRequests += 1
    }

    private func requestSearch() {
        servers.searchRequests += 1
    }

    private func showDirectMessages() {
        servers.isShowingDirectMessages = true
    }

    private func showPreviousServer() {
        servers.showAdjacentServer(-1)
    }

    private func showNextServer() {
        servers.showAdjacentServer(1)
    }

    private func toggleMic() {
        guard let voiceSession else {
            return
        }

        Task {
            await voiceSession.toggleMicMuted()
        }
    }

    private func toggleSound() {
        guard let voiceSession else {
            return
        }

        Task {
            await voiceSession.toggleSoundMuted()
        }
    }

    private func showCall() {
        servers.isCallPresented = true
    }

    private func leaveCall() {
        guard let voiceSession else {
            return
        }

        Task {
            await voiceSession.leaveVoice()
        }
    }
}
