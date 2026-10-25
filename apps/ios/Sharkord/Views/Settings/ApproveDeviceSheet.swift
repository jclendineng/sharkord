import SwiftUI

// another device's qr code, scanned here: which device is asking, and approve or decline it for
// this account. the asking device signs in by itself once approved
struct ApproveDeviceSheet: View {
    let token: String

    private struct RequestState: Decodable {
        let status: String
        let os: String?
        let device: String?
    }

    private struct AnswerInput: Encodable {
        let token: String
        let approve: Bool
    }

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var state: RequestState?
    @State private var errorMessage: String?
    @State private var isAnswering = false
    @State private var answer: Bool?

    private var askingDevice: String {
        let parts = [state?.os, state?.device].compactMap { $0 }.filter { !$0.isEmpty }

        return parts.isEmpty ? "A device" : parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                content

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(20)
            .frame(maxWidth: 520, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
            .background(Theme.deepBackground)
            .sheetBarBackground()
            .navigationTitle("Sign In Another Device")
            .inlineNavigationTitle()
            .toolbar {
                ActionToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: close)
                }
            }
        }
        .sheetDetents([.medium, .large])
        .presentationBackground(Theme.deepBackground)
        // once the server is connected, which a cold start from the camera app is not yet
        .task(id: session.phase == .connected) {
            if session.phase == .connected && state == nil {
                await load()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if answer == true {
            ContentUnavailableView(
                "Signed in",
                systemImage: "checkmark.circle.fill",
                description: Text("\(askingDevice) is signing in to \(session.displayName).")
            )
        } else if answer == false {
            ContentUnavailableView("Declined", systemImage: "xmark.circle.fill", description: Text("\(askingDevice) was not signed in."))
        } else if state?.status == "waiting" {
            approval
        } else if let state {
            ContentUnavailableView(
                state.status == "expired" ? "Code ran out" : "Already answered",
                systemImage: "qrcode",
                description: Text("Show a new code on the other device and scan it again.")
            )
        } else if session.phase == .signedOut {
            ContentUnavailableView(
                "Signed out",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text("Sign in to \(session.displayName) on this device first, then scan the code again.")
            )
        } else if errorMessage == nil {
            ProgressView()
        }
    }

    private var approval: some View {
        VStack(spacing: 16) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 44))
                .foregroundStyle(Theme.blurple)

            Text("Sign in \(askingDevice)?")
                .font(.title3.bold())
                .foregroundStyle(Theme.header)
                .multilineTextAlignment(.center)

            Text("It will be signed in to \(session.displayName) as you. Only approve a device you're holding, never one a stranger shows you.")
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

    private func load() async {
        do {
            state = try await session.request("sessions.getLoginRequest", ["token": token])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func approve() {
        respond(true)
    }

    private func decline() {
        respond(false)
    }

    private func respond(_ approve: Bool) {
        isAnswering = true

        Task {
            do {
                try await session.perform("sessions.approveLoginRequest", AnswerInput(token: token, approve: approve))
                answer = approve
            } catch {
                errorMessage = error.localizedDescription
            }

            isAnswering = false
        }
    }

    private func close() {
        dismiss()
    }
}
