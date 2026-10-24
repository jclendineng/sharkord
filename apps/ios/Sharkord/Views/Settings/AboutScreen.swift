import SwiftUI

struct AboutScreen: View {
    private static let sourceURL = URL(string: "https://github.com/jclendineng/sharkord")!

    @Environment(SessionStore.self) private var session

    var body: some View {
        List {
            Section("App") {
                LabeledContent("Version", value: AppInfo.version)
                LabeledContent("Build", value: AppInfo.build)
            }

            Section("Server") {
                LabeledContent("Name", value: session.displayName)

                if let host = session.address?.baseURL.absoluteString {
                    LabeledContent("Address", value: host)
                }

                if let serverVersion = session.serverVersion {
                    LabeledContent("Version", value: serverVersion)
                }
            }

            // the server's admins are who can help with it, so their address comes first
            Section {
                if let reportEmail = session.reportEmail, let mail = URL(string: "mailto:\(reportEmail)") {
                    Link(destination: mail) {
                        LabeledContent("Contact", value: reportEmail)
                    }
                }

                Link("Source Code", destination: Self.sourceURL)
                Link("Report a Problem", destination: Self.sourceURL.appending(path: "issues"))
            } header: {
                Text("Help")
            } footer: {
                if session.reportEmail != nil {
                    Text("Contact goes to this server's admins. Report a Problem is for the app itself.")
                }
            }

            Section("Acknowledgements") {
                Link("Sharkord", destination: URL(string: "https://github.com/Sharkord/sharkord")!)
                Link("mediasoup-client-swift", destination: URL(string: "https://github.com/VLprojects/mediasoup-client-swift")!)
                Link("WebRTC", destination: URL(string: "https://webrtc.org")!)
            }
        }
        .settingsListStyle()
        .navigationTitle("About")
        .inlineNavigationTitle()
    }
}
