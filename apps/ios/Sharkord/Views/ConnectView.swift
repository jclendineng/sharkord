import AuthenticationServices
import SwiftUI

struct ConnectView: View {
    // false for the very first server, there is nothing to go back to
    let canCancel: Bool

    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var serverURL = ""
    @State private var identity = ""
    @State private var password = ""
    @State private var serverInfo: ServerInfo?

    private var isConnecting: Bool {
        session.phase == .connecting
    }

    private var canSubmit: Bool {
        !serverURL.isEmpty && !identity.isEmpty && password.count >= 4 && !isConnecting
    }

    private var isOIDCEnabled: Bool {
        serverInfo?.oidcEnabled == true
    }

    private var isLocalLoginDisabled: Bool {
        serverInfo?.oidcDisableLocalLogin == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if canCancel {
                    Button("Cancel", action: cancel)
                        .foregroundStyle(Theme.text)
                }

                VStack(spacing: 6) {
                    Text(canCancel ? "Add a server" : "Welcome!")
                        .font(.title.bold())
                        .foregroundStyle(Theme.header)

                    Text("Log in to a Sharkord server to join its channels.")
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, canCancel ? 8 : 40)

                field("Server") {
                    TextField("", text: $serverURL, prompt: Text("chat.example.com").foregroundStyle(Theme.muted))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    serverFooter
                }

                if !isLocalLoginDisabled {
                    localLoginFields
                }

                if let errorMessage = session.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(Theme.red)
                }

                if !isLocalLoginDisabled {
                    Button(action: signIn) {
                        Group {
                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Log In")
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.blurple.opacity(canSubmit ? 1 : 0.5), in: .rect(cornerRadius: 8))
                    }
                    .disabled(!canSubmit)
                }

                if isOIDCEnabled {
                    Button(action: signInWithOIDC) {
                        Text("Sign in with SSO")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.deepBackground, in: .rect(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.chatBackground)
        .task(id: serverURL) {
            await loadServerInfo()
        }
        .onAppear(perform: prefillAddress)
    }

    @ViewBuilder
    private var localLoginFields: some View {
        field("Identity") {
            TextField("", text: $identity)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } footer: {
            EmptyView()
        }

        field("Password") {
            SecureField("", text: $password)
                .textContentType(.password)
                .onSubmit(signIn)
        } footer: {
            EmptyView()
        }
    }

    private func field<Content: View, Footer: View>(
        _ title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.muted)

            content()
                .foregroundStyle(Theme.text)
                .padding(12)
                .background(Theme.deepBackground, in: .rect(cornerRadius: 8))

            footer()
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private var serverFooter: some View {
        if let serverInfo {
            VStack(alignment: .leading, spacing: 2) {
                Label(serverInfo.name, systemImage: "checkmark.circle.fill")
                    .font(.footnote.bold())
                    .foregroundStyle(Theme.green)

                if let description = serverInfo.description, !description.isEmpty {
                    Text(description)
                }
            }
        } else {
            Text("Add http:// for servers without TLS.")
        }
    }

    // signing in again to a server whose session ended
    private func prefillAddress() {
        if serverURL.isEmpty, let address = session.address {
            serverURL = address.baseURL.absoluteString
        }
    }

    private func cancel() {
        servers.cancelSignIn()
    }

    private func signIn() {
        guard canSubmit else {
            return
        }

        Task {
            await session.signIn(serverURL: serverURL, identity: identity, password: password)
        }
    }

    private func signInWithOIDC() {
        Task {
            await session.signInWithOIDC(serverURL: serverURL) { url in
                try await webAuthenticationSession.authenticate(
                    using: url,
                    callback: .customScheme(OIDCLogin.callbackScheme),
                    additionalHeaderFields: [:]
                )
            }
        }
    }

    // debounced through task(id:), which cancels the previous run on every keystroke
    private func loadServerInfo() async {
        serverInfo = nil

        guard let address = ServerAddress(userInput: serverURL) else {
            return
        }

        try? await Task.sleep(for: .milliseconds(600))

        guard !Task.isCancelled else {
            return
        }

        serverInfo = try? await AuthAPI.fetchInfo(address)
    }
}
