import SwiftUI

// discord's "mute this conversation" sheet: how long, from 15 minutes to until it is turned
// back on. a mute for a while ends by itself, on the server too
struct MuteDurationSheet: View {
    let title: String
    let subtitle: String
    let channelId: Int
    // the sheet this opened from goes too, once a length is picked
    let onMuted: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(MuteDuration.allCases) { duration in
                        Button(duration.title) {
                            mute(for: duration)
                        }
                        .foregroundStyle(Theme.header)
                    }
                }
                .listRowBackground(Theme.listBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.deepBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Theme.header)

                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: close)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.deepBackground)
    }

    private func mute(for duration: MuteDuration) {
        Task {
            await session.setNotificationLevel(.none, for: channelId, muteForMinutes: duration.minutes)
        }

        dismiss()
        onMuted()
    }

    private func close() {
        dismiss()
    }
}
