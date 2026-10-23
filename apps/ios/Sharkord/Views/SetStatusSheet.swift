import SwiftUI

// availability and the status message, users.setPresence
struct SetStatusSheet: View {
    // the server's limit for a status message
    private static let messageLimit = 128

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var presence = Presence.online
    @State private var message = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("What's on your mind?", text: $message)

                        if !message.isEmpty {
                            Button("Clear", systemImage: "xmark.circle.fill", action: clearMessage)
                                .labelStyle(.iconOnly)
                                .foregroundStyle(Theme.muted)
                                .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Status Message")
                } footer: {
                    Text("\(message.count)/\(Self.messageLimit)")
                        .foregroundStyle(message.count > Self.messageLimit ? Theme.red : Theme.muted)
                }

                Section {
                    ForEach(Presence.allCases, id: \.self) { option in
                        Button(action: { presence = option }) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Theme.statusColor(option == .invisible ? .offline : option.status))
                                    .frame(width: 12, height: 12)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title)
                                        .foregroundStyle(Theme.header)

                                    if let detail = detail(option) {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(Theme.muted)
                                    }
                                }

                                Spacer()

                                if option == presence {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.blurple)
                                }
                            }
                            .contentShape(.rect)
                        }
                    }
                } header: {
                    Text("Online Status")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.red)
                    }
                }
            }
            .settingsListStyle()
            .navigationTitle("Set Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .disabled(message.count > Self.messageLimit)
                    }
                }
            }
            .onAppear(perform: fill)
        }
        .sheetDetents([.medium, .large])
        .presentationBackground(Theme.deepBackground)
    }

    private func detail(_ option: Presence) -> String? {
        switch option {
        case .dnd:
            "You won't get push notifications"
        case .invisible:
            "You'll appear offline, but still have full access"
        case .online, .idle:
            nil
        }
    }

    private func fill() {
        presence = session.ownPresence
        message = session.ownCustomStatus ?? ""
    }

    private func clearMessage() {
        message = ""
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)

                try await session.setPresence(presence, customStatus: trimmed.isEmpty ? nil : trimmed)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }

    private func close() {
        dismiss()
    }
}
