import SwiftUI

struct AboutScreen: View {
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
            }

            Section("Acknowledgements") {
                Link("Sharkord", destination: URL(string: "https://github.com/Sharkord/sharkord")!)
                Link("mediasoup-client-swift", destination: URL(string: "https://github.com/VLprojects/mediasoup-client-swift")!)
                Link("WebRTC", destination: URL(string: "https://webrtc.org")!)
            }
        }
        .settingsListStyle()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
