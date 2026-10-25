import SwiftUI

// discord's "mute this conversation" sheet: how long, from 15 minutes to until it is turned
// back on. a mute for a while ends by itself, on the server too
struct MuteDurationSheet: View {
    let title: String
    let subtitle: String
    // a category mutes each of its channels
    let channelIds: [Int]

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
            .listHoverHighlight()
            .background(Theme.deepBackground)
            .titleWithSubtitle(title, subtitle: subtitle)
            .inlineNavigationTitle()
            .toolbar {
                ActionToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: close)
                }
            }
        }
        .sheetDetents([.large])
        .presentationBackground(Theme.deepBackground)
    }

    private func mute(for duration: MuteDuration) {
        Task {
            for channelId in channelIds {
                await session.setNotificationLevel(.none, for: channelId, muteForMinutes: duration.minutes)
            }
        }

        dismiss()
    }

    private func close() {
        dismiss()
    }
}
