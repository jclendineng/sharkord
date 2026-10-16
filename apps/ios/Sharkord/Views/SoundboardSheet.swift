import SwiftUI

// discord's soundboard in a call: the server's sounds in a grid, a tap plays one for everyone
// in the call. a long press previews it for only you
struct SoundboardSheet: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            Group {
                if session.sounds.isEmpty {
                    ContentUnavailableView(
                        "No Sounds Yet",
                        systemImage: "waveform",
                        description: Text("Someone who manages the server can add sounds in its settings.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                            ForEach(session.sounds) { sound in
                                SoundTile(sound: sound)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle("Soundboard")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.listBackground)
    }
}

private struct SoundTile: View {
    let sound: SoundboardSound

    @Environment(SessionStore.self) private var session

    var body: some View {
        Button(action: play) {
            HStack(spacing: 8) {
                if let emoji = sound.emoji, !emoji.isEmpty {
                    EmojiView(value: emoji, size: 20)
                }

                Text(sound.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.header)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(Theme.deepBackground, in: .rect(cornerRadius: 12))
            .hoverBrighten(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Preview", systemImage: "play.fill", action: preview)
        }
    }

    private func play() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            await session.playSound(sound)
        }
    }

    private func preview() {
        session.previewSound(sound)
    }
}
