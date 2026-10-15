import SwiftUI

// every device signed in to this account on the selected server, with a way to sign each out
struct DevicesScreen: View {
    @Environment(SessionStore.self) private var session

    @State private var devices: [DeviceSession] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isConfirmingLogOutAll = false

    private var current: [DeviceSession] {
        devices.filter(\.isCurrent)
    }

    private var others: [DeviceSession] {
        devices.filter { !$0.isCurrent }
    }

    var body: some View {
        List {
            Section {
                Text("These are the devices signed in to your account on \(session.displayName). Sign out of any you don't recognize, and change your password if you think someone else has it.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                }
            }

            if !current.isEmpty {
                Section("Current Device") {
                    ForEach(current) { device in
                        DeviceRow(device: device, onRevoke: nil)
                    }
                }
            }

            if !others.isEmpty {
                Section("Other Devices") {
                    ForEach(others) { device in
                        DeviceRow(device: device, onRevoke: { revoke(device) })
                    }
                }

                Section {
                    Button(role: .destructive, action: confirmLogOutAll) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Log Out All Known Devices")
                                .foregroundStyle(Theme.red)

                            Text("Every other device will have to log in again.")
                                .font(.caption)
                                .foregroundStyle(Theme.red.opacity(0.8))
                        }
                    }
                }
            }
        }
        .settingsListStyle()
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .refreshable {
            await load()
        }
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Log out every other device?", isPresented: $isConfirmingLogOutAll, titleVisibility: .visible) {
            Button("Log Out All", role: .destructive, action: logOutAll)
        }
        .task {
            await load()
        }
    }

    private func load() async {
        do {
            devices = try await session.deviceSessions()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func revoke(_ device: DeviceSession) {
        Task {
            do {
                try await session.revokeSession(device.id)
                devices.removeAll { $0.id == device.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func confirmLogOutAll() {
        isConfirmingLogOutAll = true
    }

    private func logOutAll() {
        Task {
            do {
                _ = try await session.revokeOtherSessions()
                devices.removeAll { !$0.isCurrent }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct DeviceRow: View {
    let device: DeviceSession
    let onRevoke: (() -> Void)?

    // an ipad reports ios as its system, so the model tells it apart from a phone
    private var icon: String {
        let os = device.os?.lowercased() ?? ""
        let model = device.device?.lowercased() ?? ""

        if model.contains("ipad") || model.contains("tablet") {
            return "ipad"
        }

        if os.contains("ios") || os.contains("android") {
            return "iphone"
        }

        return "desktopcomputer"
    }

    private var title: String {
        [device.os, device.device]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            .nonEmpty ?? "Unknown device"
    }

    private var location: String? {
        [device.city, device.region, device.country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
            .nonEmpty
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.header)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.header)

                if let location {
                    Text(location)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }

                if onRevoke != nil {
                    Text(device.lastActiveDate, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }

            Spacer()

            if let onRevoke {
                Button("Sign Out", systemImage: "xmark", action: onRevoke)
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(Theme.muted)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
