import AVFoundation
import AuthenticationServices
import SwiftUI

// discord's sign in: a welcome screen with register and log in, then cards over the starry
// background. the server comes first, since what it allows decides the rest: register only
// shows where the server takes new members, sso where it has an identity provider
struct ConnectView: View {
    private enum Step: Equatable {
        case welcome
        case server(Intent)
        case login
        case register
        // waiting for the device showing the qr code to approve
        case link(ServerListStore.LinkLogin)
        // showing a qr code for a device already signed in to scan and approve
        case requestCode
    }

    private enum Intent: Equatable {
        case login
        case register
        // past the server, straight to a qr code for a signed in phone to scan
        case code
    }

    // false for the very first server, there is nothing to go back to
    let canCancel: Bool

    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var step = Step.welcome
    @State private var serverURL = ""
    @State private var identity = ""
    @State private var password = ""
    @State private var serverInfo: ServerInfo?
    // an invite link or its code, from the address field or typed in on a closed server
    @State private var invite = ""
    @State private var twoFactorCode = ""
    @State private var serverError: String?
    @State private var isScannerPresented = false
    private let hasCamera = AVCaptureDevice.default(for: .video) != nil
    @State private var isCheckingServer = false
    @State private var loginRequest: AuthAPI.LoginRequest?
    // a new code asked for after the last one ran out or was declined
    @State private var requestAttempt = 0

    var body: some View {
        ZStack {
            StarryBackground()

            switch step {
            case .welcome:
                welcome
                    .transition(.opacity)
            case .server(let intent):
                AuthCard(onBack: back) {
                    serverCard(intent: intent)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .login:
                AuthCard(onBack: back) {
                    loginCard
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .register:
                AuthCard(onBack: back) {
                    registerCard
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .link(let login):
                AuthCard(onBack: back) {
                    linkCard(login)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .requestCode:
                AuthCard(onBack: back) {
                    requestCodeCard
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: step)
        .transparentWindowBar()
        .onAppear(perform: resumeSignIn)
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .sheet(isPresented: $isScannerPresented) {
            QRScannerSheet(onScan: scanned)
                .environment(session)
                .environment(servers)
                .appSheet()
        }
    }


    private var welcome: some View {
        VStack(spacing: 0) {
            if canCancel {
                HStack {
                    Button(action: cancel) {
                        Label("Close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 12)
            }

            Spacer()

            VStack(spacing: 14) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)

                Text("WELCOME TO SHARKORD")
                    .font(.system(size: 30, weight: .black).width(.expanded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)

                Text(Platform.isMac ? "Your server, your people. Click below to get started!" : "Your server, your people. Tap below to get started!")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 10) {
                Button(action: startRegister) {
                    Text("Register")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(.white, in: .rect(cornerRadius: 12))
                }

                Button(action: startLogin) {
                    Text("Log In")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color(hex: "#090B33"), in: .rect(cornerRadius: 12))
                }

                // a device already signed in shows a code in settings, no server or password to
                // type. where there is no camera to scan it with, a mac mini or a studio, this
                // device shows a code for a signed in phone to scan instead
                if hasCamera {
                    Button(action: showScanner) {
                        Label("Scan a QR Code", systemImage: "qrcode.viewfinder")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                } else {
                    Button(action: startCodeLogin) {
                        Label("Log In With a QR Code", systemImage: "qrcode")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.top, 32)

            Spacer()
            Spacer()
        }
    }


    @ViewBuilder
    private func linkCard(_ login: ServerListStore.LinkLogin) -> some View {
        AuthTitle(title: "Check your other device", subtitle: "Approve signing in on the device showing the code. It's waiting under Settings, Sign In Another Device.")

        HStack(spacing: 10) {
            if session.errorMessage == nil {
                ProgressView()
                    .tint(.white)
            }

            Text(ServerAddress(userInput: login.server)?.baseURL.host() ?? login.server)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .task(id: login) {
            await session.signIn(serverURL: login.server, linkToken: login.token)
        }

        errorText
    }

    @ViewBuilder
    private var requestCodeCard: some View {
        AuthTitle(title: "Scan with your phone", subtitle: "On a phone signed in to this server, open Sharkord, go to Settings, Sign In Another Device and tap Scan a Code. Its camera app works too.")

        Group {
            if let loginRequest, let url = approvalURL(for: loginRequest), let image = QRCode.image(url) {
                Image(platformImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(14)
                    .background(.white, in: .rect(cornerRadius: 16))
            } else if session.errorMessage == nil {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(width: 220, height: 220)
        .frame(maxWidth: .infinity)

        if let loginRequest, session.errorMessage == nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(Double(loginRequest.expiresAt) / 1000 - context.date.timeIntervalSince1970))

                Text("Waiting for approval, \(remaining / 60):\(String(format: "%02d", remaining % 60)) left")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
            }
        }

        errorText

        if session.errorMessage != nil {
            AuthButton(title: "Show a New Code", isEnabled: true, isWorking: false, action: retryRequestCode)
        }

        Color.clear
            .frame(height: 0)
            .task(id: requestAttempt) {
                await runLoginRequest()
            }
    }

    @ViewBuilder
    private func serverCard(intent: Intent) -> some View {
        AuthTitle(title: "Enter your server", subtitle: "The address you use to reach it, like chat.example.com, or the invite link you were sent.")

        AuthField(label: "Server Address") {
            TextField("", text: $serverURL, prompt: Text("chat.example.com").foregroundStyle(Theme.muted))
                .keyboard(.url)
                .textContentType(.URL)
                .noAutocapitalization()
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { checkServer(for: intent) }
                .accessibilityLabel("Server Address")
                .accessibilityIdentifier("serverAddress")
        }

        if let serverError {
            Text(serverError)
                .font(.footnote)
                .foregroundStyle(Theme.red)
        }

        AuthButton(title: "Next", isEnabled: !serverURL.isEmpty, isWorking: isCheckingServer) {
            checkServer(for: intent)
        }
    }


    @ViewBuilder
    private var loginCard: some View {
        AuthTitle(title: "Welcome back!", subtitle: serverInfo.map { "We're so excited to see you on \($0.name) again!" } ?? "We're so excited to see you again!")

        ServerBadge(info: serverInfo, address: ServerAddress(userInput: serverURL))

        if serverInfo?.oidcDisableLocalLogin != true {
            credentialFields(passwordContent: .password)

            errorText

            AuthButton(title: "Log In", isEnabled: canSubmit, isWorking: isConnecting, action: signIn)
        }

        ssoOption(title: "Log in with SSO")

        // for a device with no camera to scan a code with, a mac mini or a studio: it shows one
        // instead, for a phone already signed in to scan and approve
        Button(action: showRequestCode) {
            Label("Log In With a QR Code", systemImage: "qrcode")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.link)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.plain)

        if serverInfo?.allowNewUsers == true {
            HStack(spacing: 4) {
                Text("Need an account?")
                    .foregroundStyle(Theme.muted)

                Button("Register", action: switchToRegister)
                    .foregroundStyle(Theme.link)
                    .buttonStyle(.plain)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity)
        }
    }


    @ViewBuilder
    private var registerCard: some View {
        AuthTitle(title: "Create an account", subtitle: serverInfo.map { "Join \($0.name)." } ?? "Join the server.")

        ServerBadge(info: serverInfo, address: ServerAddress(userInput: serverURL))

        if serverInfo?.allowNewUsers != true {
            AuthField(label: "Invite Link") {
                TextField("", text: $invite, prompt: Text("Paste the invite link you were sent").foregroundStyle(Theme.muted))
                    .keyboard(.url)
                    .noAutocapitalization()
                    .autocorrectionDisabled()
                    .accessibilityLabel("Invite Link")
            }
        }

        if (serverInfo?.allowNewUsers == true || inviteCode != nil) && serverInfo?.oidcDisableLocalLogin != true {
            credentialFields(passwordContent: .newPassword)

            Text("Pick a username and a password of at least 4 characters. You'll use them to log in.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)

            errorText

            AuthButton(title: "Create Account", isEnabled: canSubmit, isWorking: isConnecting, action: signIn)
        } else if serverInfo?.allowNewUsers != true && inviteCode == nil {
            Text("\(serverInfo?.name ?? "This server") only takes new members with an invite. Paste the link you were sent above, or log in if you already have an account.")
                .font(.subheadline)
                .foregroundStyle(Theme.text)

            AuthButton(title: "Log In Instead", isEnabled: true, isWorking: false, action: switchToLogin)
        }

        ssoOption(title: "Continue with SSO")
    }


    @ViewBuilder
    private func credentialFields(passwordContent: PlatformTextContentType) -> some View {
        AuthField(label: "Username") {
            TextField("", text: $identity)
                .accessibilityLabel("Username")
                .accessibilityIdentifier("username")
                .textContentType(.username)
                .noAutocapitalization()
                .autocorrectionDisabled()
                .submitLabel(.next)
        }

        AuthField(label: "Password") {
            PasswordField(text: $password, contentType: passwordContent, onSubmit: signIn)
        }

        if session.needsTwoFactorCode {
            AuthField(label: "Authenticator Code") {
                TextField("", text: $twoFactorCode, prompt: Text("Or a recovery code").foregroundStyle(Theme.muted))
                    .textContentType(.oneTimeCode)
                    .keyboard(.ascii)
                    .noAutocapitalization()
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(signIn)
                    .accessibilityLabel("Authenticator Code")
            }
        }
    }

    @ViewBuilder
    private var errorText: some View {
        if let errorMessage = session.errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(Theme.red)
        }
    }

    @ViewBuilder
    private func ssoOption(title: String) -> some View {
        if serverInfo?.oidcEnabled == true {
            if serverInfo?.oidcDisableLocalLogin != true {
                HStack(spacing: 12) {
                    Rectangle().fill(Theme.divider).frame(height: 1)

                    Text("OR")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)

                    Rectangle().fill(Theme.divider).frame(height: 1)
                }
            }

            Button(action: signInWithOIDC) {
                Label(title, systemImage: "key.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.header)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.inputBackground, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }


    private var isConnecting: Bool {
        session.phase == .connecting
    }

    private var canSubmit: Bool {
        !identity.isEmpty && password.count >= 4 && !isConnecting
    }

    // signing in again to a server whose session ended skips straight to its login card
    private func resumeSignIn() {
        // a sign in code scanned with the camera app goes straight to waiting for approval
        if let login = servers.pendingLinkLogin {
            servers.pendingLinkLogin = nil
            step = .link(login)
            return
        }

        // an invite link that opened the app goes straight to making an account with it
        if let link = servers.pendingInviteLink {
            servers.pendingInviteLink = nil
            serverURL = link
            checkServer(for: .register)
            return
        }

        guard serverURL.isEmpty, let address = session.address else {
            return
        }

        serverURL = address.baseURL.absoluteString
        step = .login

        Task {
            serverInfo = try? await AuthAPI.fetchInfo(address)
        }
    }

    private func startRegister() {
        session.errorMessage = nil
        step = .server(.register)
    }

    private func startLogin() {
        session.errorMessage = nil
        step = .server(.login)
    }

    private func startCodeLogin() {
        session.errorMessage = nil
        step = .server(.code)
    }

    private func switchToRegister() {
        session.errorMessage = nil
        step = .register
    }

    private func switchToLogin() {
        session.errorMessage = nil
        step = .login
    }

    private func back() {
        session.errorMessage = nil
        serverError = nil

        switch step {
        case .welcome:
            break
        case .server:
            step = .welcome
        case .login, .register:
            step = .server(step == .register ? .register : .login)
        case .link:
            step = .welcome
        case .requestCode:
            loginRequest = nil
            step = .login
        }
    }

    private func showRequestCode() {
        session.errorMessage = nil
        loginRequest = nil
        step = .requestCode
    }

    private func retryRequestCode() {
        session.errorMessage = nil
        loginRequest = nil
        requestAttempt += 1
    }

    // sharkord://approve?server=…&request=…, which a signed in phone opens to approve this device
    private func approvalURL(for request: AuthAPI.LoginRequest) -> String? {
        guard let address = ServerAddress(userInput: serverURL) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "sharkord"
        components.host = "approve"
        components.queryItems = [
            URLQueryItem(name: "server", value: address.baseURL.absoluteString),
            URLQueryItem(name: "request", value: request.token)
        ]

        return components.url?.absoluteString
    }

    // a code to show, then waiting on it until a phone approves it, it is declined or runs out
    private func runLoginRequest() async {
        guard let address = ServerAddress(userInput: serverURL) else {
            session.errorMessage = "That doesn't look like a server address."
            return
        }

        do {
            let request = try await AuthAPI.startLoginRequest(address)

            loginRequest = request
            await session.signIn(address: address, loginRequest: request)
        } catch is CancellationError {
            return
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    private func showScanner() {
        isScannerPresented = true
    }

    private func scanned(_ code: String) {
        isScannerPresented = false

        guard let url = URL(string: code), let login = ServerListStore.LinkLogin(url: url) else {
            session.errorMessage = "That isn't a Sharkord sign in code."
            return
        }

        session.errorMessage = nil
        step = .link(login)
    }

    private func cancel() {
        servers.cancelSignIn()
    }

    private var inviteCode: String? {
        ServerAddress.inviteCode(in: invite)
    }

    private func checkServer(for intent: Intent) {
        guard let address = ServerAddress(userInput: serverURL) else {
            serverError = "That doesn't look like a server address."
            return
        }

        guard !address.isInsecure else {
            serverError = ServerAddress.insecureMessage
            return
        }

        serverError = nil
        isCheckingServer = true

        // an invite link goes straight to making an account with it, as discord's does
        if let code = ServerAddress.inviteCode(in: serverURL), serverURL.contains("invite=") {
            invite = code
        }

        Task {
            do {
                serverInfo = try await AuthAPI.fetchInfo(address)

                if intent == .code {
                    showRequestCode()
                } else {
                    step = intent == .register || inviteCode != nil ? .register : .login
                }
            } catch {
                serverError = "Couldn't reach a Sharkord server there. Check the address and try again."
            }

            isCheckingServer = false
        }
    }

    private func signIn() {
        guard canSubmit else {
            return
        }

        Task {
            await session.signIn(
                serverURL: serverURL,
                identity: identity,
                password: password,
                invite: step == .register ? inviteCode : nil,
                totp: session.needsTwoFactorCode ? twoFactorCode : nil
            )
        }
    }

    private func signInWithOIDC() {
        Task {
            await session.signInWithOIDC(serverURL: serverURL, invite: inviteCode) { url in
                try await webAuthenticationSession.authenticate(
                    using: url,
                    callback: .customScheme(OIDCLogin.callbackScheme),
                    additionalHeaderFields: [:]
                )
            }
        }
    }
}


// the dark card the steps sit in, centered and narrow on an ipad, nearly full width on a phone
private struct AuthCard<Content: View>: View {
    let onBack: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button(action: onBack) {
                    Label("Back", systemImage: "arrow.left")
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.header)
                        .frame(width: 36, height: 36, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                content
            }
            .padding(24)
            .frame(maxWidth: 520)
            .background(Color(hex: "#232428"), in: .rect(cornerRadius: 24))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center) { length, _ in
                length
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct AuthTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2.weight(.heavy))
                .foregroundStyle(Theme.header)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.text)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }
}

private struct AuthField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)

            content
                .foregroundStyle(Theme.header)
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(Color(hex: "#1A1B1E"), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).stroke(Theme.divider, lineWidth: 1)
                }
        }
    }
}

private struct AuthButton: View {
    let title: String
    let isEnabled: Bool
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isWorking {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                }
            }
            .font(.headline)
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.6))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.blurple.opacity(isEnabled ? 1 : 0.5), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isWorking)
    }
}

private struct PasswordField: View {
    @Binding var text: String
    let contentType: PlatformTextContentType
    let onSubmit: () -> Void

    @State private var isRevealed = false

    var body: some View {
        HStack {
            Group {
                if isRevealed {
                    TextField("", text: $text)
                        .noAutocapitalization()
                        .autocorrectionDisabled()
                } else {
                    SecureField("", text: $text)
                }
            }
            .textContentType(contentType)
            .submitLabel(.go)
            .onSubmit(onSubmit)
            .accessibilityLabel("Password")
            .accessibilityIdentifier("password")

            Button(isRevealed ? "Hide Password" : "Show Password", systemImage: isRevealed ? "eye.slash" : "eye", action: toggle)
                .labelStyle(.iconOnly)
                .foregroundStyle(Theme.muted)
                .buttonStyle(.plain)
        }
    }

    private func toggle() {
        isRevealed.toggle()
    }
}

// which server the card is for, so nobody types their password into the wrong one
private struct ServerBadge: View {
    let info: ServerInfo?
    let address: ServerAddress?

    var body: some View {
        if let info {
            HStack(spacing: 10) {
                Group {
                    if let address, let logo = info.logo {
                        CachedFileImage(file: logo, url: address.fileURL(logo)) {
                            Theme.inputBackground
                        }
                    } else {
                        Text(String(info.name.prefix(1)).uppercased())
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.blurple)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(.rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 1) {
                    Text(info.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.header)

                    if let host = address?.baseURL.host() {
                        Text(host)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Theme.inputBackground.opacity(0.5), in: .rect(cornerRadius: 14))
        }
    }
}

// discord's night sky: a deep blue gradient, soft glowing shapes and small square stars
private struct StarryBackground: View {
    private struct Star {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
    }

    // fixed so the sky doesn't change between launches or redraws
    private static let stars: [Star] = {
        var generator = SeededGenerator(seed: 7)

        return (0..<70).map { _ in
            Star(
                x: .random(in: 0...1, using: &generator),
                y: .random(in: 0...1, using: &generator),
                size: .random(in: 3...8, using: &generator),
                opacity: .random(in: 0.25...0.8, using: &generator)
            )
        }
    }()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "#0A0840"), Color(hex: "#0F1C8C"), Color(hex: "#2A4BD8")],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(Color(hex: "#C9C3F5").opacity(0.55))
                    .frame(width: 180)
                    .blur(radius: 30)
                    .position(x: proxy.size.width * 0.8, y: proxy.size.height * 0.08)

                Circle()
                    .fill(Color(hex: "#8A3FD1").opacity(0.55))
                    .frame(width: 220)
                    .blur(radius: 50)
                    .position(x: proxy.size.width * 0.12, y: proxy.size.height * 0.28)

                Circle()
                    .fill(Color(hex: "#7B6BFF").opacity(0.45))
                    .frame(width: 160)
                    .blur(radius: 40)
                    .position(x: proxy.size.width * 0.78, y: proxy.size.height * 0.88)

                Canvas { context, size in
                    for star in Self.stars {
                        let rect = CGRect(x: star.x * size.width, y: star.y * size.height, width: star.size, height: star.size)

                        context.fill(Path(rect), with: .color(Color(hex: "#8F9BFF").opacity(star.opacity)))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407

        return state
    }
}
