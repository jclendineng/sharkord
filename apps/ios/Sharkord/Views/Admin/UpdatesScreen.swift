import SwiftUI

// others.getUpdate and others.updateServer
struct UpdatesScreen: View {
    @Environment(SessionStore.self) private var session

    @State private var update: AdminUpdate?
    @State private var errorMessage: String?
    @State private var isConfirming = false
    @State private var isUpdating = false

    var body: some View {
        List {
            if let update {
                Section {
                    LabeledContent("Running", value: update.currentVersion ?? "Unknown")
                    LabeledContent("Latest", value: update.latestVersion == "0.0.0" ? "Unknown" : update.latestVersion)
                }

                Section {
                    status(update)
                }

                if update.canUpdate && update.hasUpdate {
                    Section {
                        Button(action: confirm) {
                            if isUpdating {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Update to \(update.latestVersion)")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(isUpdating)
                    } footer: {
                        Text("The server restarts to finish, everyone is disconnected for a moment.")
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                }
            }
        }
        .settingsListStyle()
        .overlay {
            if update == nil && errorMessage == nil {
                ProgressView()
            }
        }
        .navigationTitle("Updates")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Update the server?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Update and Restart", action: start)
        } message: {
            Text("Everyone connected is dropped while it restarts.")
        }
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    @ViewBuilder
    private func status(_ update: AdminUpdate) -> some View {
        if !update.canUpdate {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Updates aren't supported here")
                        .foregroundStyle(Theme.header)

                    Text("This server can't update itself. In Docker, pull the new image and recreate the container.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            } icon: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.red)
            }
        } else if update.hasUpdate {
            Label {
                Text("Version \(update.latestVersion) is available")
                    .foregroundStyle(Theme.header)
            } icon: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Theme.blurple)
            }
        } else {
            Label {
                Text("Up to date")
                    .foregroundStyle(Theme.header)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.green)
            }
        }
    }

    private func load() async {
        do {
            update = try await session.request("others.getUpdate")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirm() {
        isConfirming = true
    }

    private func start() {
        struct NoInput: Encodable {}

        isUpdating = true
        errorMessage = nil

        Task {
            do {
                try await session.perform("others.updateServer", NoInput())
            } catch {
                errorMessage = error.localizedDescription
                isUpdating = false
            }
        }
    }
}
