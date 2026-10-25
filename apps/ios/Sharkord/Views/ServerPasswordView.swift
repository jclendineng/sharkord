import SwiftUI

struct ServerPasswordView: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session

    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Server password", text: $password)
                        .onSubmit(join)
                } footer: {
                    Text("This server requires a password to join.")
                        .wrappingFooter()
                }

                if let errorMessage = session.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Join", action: join)
                        .disabled(password.isEmpty)

                    Button("Cancel", role: .cancel, action: cancel)
                }
            }
            // a mac lays a plain form out in two columns with the labels right aligned. grouped
            // is a phone's own anyway
            .formStyle(.grouped)
            .sheetBarBackground()
            .navigationTitle("Server Password")
        }
    }

    private func join() {
        Task {
            await session.submitServerPassword(password)
        }
    }

    private func cancel() {
        servers.remove(session)
    }
}
