import CoreImage.CIFilterBuiltins
import SwiftUI

// signing another device in without typing anything: this one shows a qr code holding the
// server and a one time code, the other scans it, and it is let in from here
struct SignInDeviceScreen: View {
    private struct LoginLink: Decodable {
        let id: String
        let token: String
        let expiresAt: Int
    }

    private struct LoginLinkState: Decodable {
        let status: String
        let os: String?
        let device: String?
    }

    @Environment(SessionStore.self) private var session

    @State private var link: LoginLink?
    @State private var state: LoginLinkState?
    @State private var errorMessage: String?
    @State private var isAnswering = false

    private var claimedDevice: String {
        let parts = [state?.os, state?.device].compactMap { $0 }.filter { !$0.isEmpty }

        return parts.isEmpty ? "A device" : parts.joined(separator: " · ")
    }

    private var qrURL: String? {
        guard let link, let base = session.address?.baseURL.absoluteString else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "sharkord"
        components.host = "login"
        components.queryItems = [
            URLQueryItem(name: "server", value: base),
            URLQueryItem(name: "token", value: link.token)
        ]

        return components.url?.absoluteString
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if state?.status == "approved" {
                    ContentUnavailableView(
                        "Signed in",
                        systemImage: "checkmark.circle.fill",
                        description: Text("\(claimedDevice) is signed in to \(session.displayName).")
                    )
                } else if state?.status == "claimed" {
                    approval
                } else {
                    code
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                }
            }
            .padding(20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.deepBackground)
        .navigationTitle("Sign In Another Device")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await run()
        }
    }

    private var code: some View {
        VStack(spacing: 16) {
            Text("On the other device, open Sharkord and tap Scan a QR Code, or point its camera at this code. You'll approve it here before it's signed in.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)

            Group {
                if let qrURL, let image = Self.qrImage(qrURL) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                        .background(.white, in: .rect(cornerRadius: 16))
                } else {
                    ProgressView()
                }
            }
            .frame(width: 260, height: 260)

            if let link {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(Double(link.expiresAt) / 1000 - context.date.timeIntervalSince1970))

                    Text("A new code in \(remaining / 60):\(String(format: "%02d", remaining % 60))")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var approval: some View {
        VStack(spacing: 16) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 44))
                .foregroundStyle(Theme.blurple)

            Text("Sign in \(claimedDevice)?")
                .font(.title3.bold())
                .foregroundStyle(Theme.header)
                .multilineTextAlignment(.center)

            Text("It scanned your code and will be signed in to \(session.displayName) as you. Only approve a device you're holding.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)

            Button(action: approve) {
                Text("Approve")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.blurple, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isAnswering)

            Button(action: decline) {
                Text("Decline")
                    .font(.headline)
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.listBackground, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isAnswering)
        }
    }

    // a code, then every couple of seconds whether it was scanned, with a new one when it runs out
    private func run() async {
        while !Task.isCancelled {
            do {
                if link == nil || state?.status == "expired" || state?.status == "denied" {
                    link = try await session.perform("sessions.createLoginLink", EmptyInput())
                    state = nil
                }

                if let link {
                    state = try await session.request("sessions.getLoginLink", ["id": link.id])
                }

                errorMessage = nil

                if state?.status == "approved" {
                    return
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func approve() {
        answer(true)
    }

    private func decline() {
        answer(false)
    }

    private func answer(_ approve: Bool) {
        struct AnswerInput: Encodable {
            let id: String
            let approve: Bool
        }

        guard let link else {
            return
        }

        isAnswering = true

        Task {
            do {
                try await session.perform("sessions.approveLoginLink", AnswerInput(id: link.id, approve: approve))
                state = LoginLinkState(status: approve ? "approved" : "denied", os: state?.os, device: state?.device)
            } catch {
                errorMessage = error.localizedDescription
            }

            isAnswering = false
        }
    }

    private struct EmptyInput: Encodable {}

    private static func qrImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard
            let output = filter.outputImage,
            let cgImage = CIContext().createCGImage(output, from: output.extent)
        else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
