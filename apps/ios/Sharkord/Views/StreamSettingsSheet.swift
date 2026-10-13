import SwiftUI

// discord's stream settings, shown before the system picker starts the broadcast
struct StreamSettingsSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var quality = AppSettings.shared.streamQuality
    @State private var trigger = BroadcastPickerTrigger()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stream Settings")
                .font(.title3.bold())
                .foregroundStyle(Theme.header)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)

            Text("Stream Mode")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)

            VStack(spacing: 0) {
                QualityRow(
                    title: "Default",
                    detail: "Balanced quality and performance (720p, 30fps)",
                    systemImage: "iphone",
                    isSelected: quality == .standard,
                    action: { select(.standard) }
                )

                Theme.divider.frame(height: 1)
                    .padding(.leading, 56)

                QualityRow(
                    title: "High Quality",
                    detail: "For video and gaming (1080p, 30fps)",
                    systemImage: "photo.badge.plus",
                    isSelected: quality == .high,
                    action: { select(.high) }
                )
            }
            .background(Theme.deepBackground, in: .rect(cornerRadius: 14))

            Text("Everything on your screen is shared, notifications included. Turn on Do Not Disturb first if you'd rather they stay private.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)

            Spacer()

            Button(action: start) {
                Text("Start Streaming")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.blurple, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .background {
                HiddenBroadcastPicker(trigger: trigger)
                    .frame(width: 1, height: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.listBackground)
        .onChange(of: session.isSharingScreen) { _, isSharing in
            if isSharing {
                dismiss()
            }
        }
    }

    private func select(_ newQuality: AppSettings.StreamQuality) {
        quality = newQuality
    }

    // the extension reads the quality when the broadcast starts, so it is saved first
    private func start() {
        session.setStreamQuality(quality)
        trigger.open()
    }
}

private struct QualityRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Theme.text)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.header)

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                Spacer()

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.blurple : Theme.muted)
            }
            .padding(14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
