import SwiftUI

struct ErrorToast: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.red, in: .capsule)
            .shadow(radius: 8)
            .padding(.top, 8)
    }
}

struct ReconnectingBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text("Reconnecting…")
                .fontWeight(.semibold)
        }
        .font(.footnote)
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Theme.yellow)
    }
}

// discord's bar when the account joined voice from another device: this one's call has ended,
// and reconnect takes the seat back
struct VoiceTakenOverBanner: View {
    let channelId: Int

    @Environment(SessionStore.self) private var session

    var body: some View {
        HStack(spacing: 10) {
            Text("Your voice has been disconnected because you connected at another location.")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Reconnect", action: reconnect)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                }
                .buttonStyle(.plain)
        }
        .font(.footnote)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.red)
    }

    private func reconnect() {
        Task {
            await session.joinVoice(channelId)
        }
    }
}

// the bars along the top of the channel list and the chat, the reconnecting one and the one
// for a call another device took over
struct SessionBanners: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            if session.showsReconnectingBanner {
                ReconnectingBanner()
            }

            if let channelId = session.voiceTakenOverChannelId {
                VoiceTakenOverBanner(channelId: channelId)
            }
        }
    }
}
