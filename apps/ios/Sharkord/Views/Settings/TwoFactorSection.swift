import SwiftUI

// users.getTwoFactor, startTwoFactor, confirmTwoFactor and disableTwoFactor: an authenticator
// app asked for after the password. the qr code holds the otpauth link every app reads
struct TwoFactorSection: View {
    private struct Status: Decodable {
        let enabled: Bool
    }

    private struct Setup: Decodable {
        let secret: String
        let uri: String
    }

    private struct Confirmed: Decodable {
        let recoveryCodes: [String]
    }

    @Environment(SessionStore.self) private var session

    @State private var isEnabled: Bool?
    @State private var setup: Setup?
    @State private var code = ""
    @State private var recoveryCodes: [String]?
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        Section {
            if let recoveryCodes {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recovery Codes")
                        .font(.headline)

                    Text(recoveryCodes.joined(separator: "\n"))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)

                    Button("Copy Codes", systemImage: "doc.on.doc", action: copyRecoveryCodes)
                }
            }

            if let setup {
                if let image = QRCode.image(setup.uri) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200)
                        .frame(maxWidth: .infinity)
                }

                if let url = URL(string: setup.uri) {
                    Link("Add to an Authenticator App", destination: url)
                }

                Text(setup.secret)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)

                codeField(prompt: "Code from the app")

                Button("Turn On", action: confirm)
                    .disabled(code.isEmpty || isWorking)
            } else if isEnabled == true {
                codeField(prompt: "Authenticator or recovery code")

                Button("Turn Off", role: .destructive, action: disable)
                    .disabled(code.isEmpty || isWorking)
            } else if isEnabled == false {
                Button("Set Up Two-Factor", action: start)
                    .disabled(isWorking)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.red)
            }
        } header: {
            Text("Two-Factor Authentication")
        } footer: {
            Text("After your password, a code from an authenticator app such as Apple Passwords, Google Authenticator or 1Password is asked for. Each recovery code works once if you lose it.")
        }
        .task {
            let status: Status? = try? await session.request("users.getTwoFactor")

            isEnabled = status?.enabled
        }
    }

    private func codeField(prompt: String) -> some View {
        TextField(prompt, text: $code)
            .textContentType(.oneTimeCode)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    private func start() {
        run {
            setup = try await session.perform("users.startTwoFactor", [String: String]())
            code = ""
        }
    }

    private func confirm() {
        run {
            let confirmed: Confirmed = try await session.perform("users.confirmTwoFactor", ["code": code])

            recoveryCodes = confirmed.recoveryCodes
            setup = nil
            isEnabled = true
            code = ""
        }
    }

    private func disable() {
        run {
            try await session.perform("users.disableTwoFactor", ["code": code])

            isEnabled = false
            recoveryCodes = nil
            code = ""
        }
    }

    private func copyRecoveryCodes() {
        UIPasteboard.general.string = recoveryCodes?.joined(separator: "\n")
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil

        Task {
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }

            isWorking = false
        }
    }
}
