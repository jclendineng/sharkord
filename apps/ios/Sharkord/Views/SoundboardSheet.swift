import SwiftUI

// the server's sounds in a call, a tap plays one for everyone in it, a long press (a right click
// on a mac) previews it for only you. a tile lights up while its sound plays, whoever played it
struct SoundboardSheet: View {
    @Environment(SessionStore.self) private var session

    private let isOnMac = Platform.isMac

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("Soundboard")
                        .font(.headline)
                        .foregroundStyle(Theme.header)

                    Text(isOnMac ? "Click to play for everyone, right click to preview" : "Tap to play for everyone, hold to preview")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                if session.sounds.isEmpty {
                    ContentUnavailableView(
                        "No Sounds Yet",
                        systemImage: "waveform",
                        description: Text("Someone who manages the server can add sounds in its settings.")
                    )
                    .padding(.vertical, 12)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 10)], spacing: 10) {
                        ForEach(session.sounds) { sound in
                            SoundTile(sound: sound, isPlaying: session.playingSounds[sound.id] != nil)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .fittedSheet()
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.deepBackground)
        // a form as tall as its sounds on an ipad and a mac, where the heights above do nothing
        .presentationSizing(.form.fitted(horizontal: false, vertical: true))
        .appSheet(fitsContent: true)
    }
}

private struct SoundTile: View {
    let sound: SoundboardSound
    let isPlaying: Bool

    @Environment(SessionStore.self) private var session

    var body: some View {
        Button(action: play) {
            VStack(spacing: 8) {
                icon
                    .frame(height: 40)
                    .scaleEffect(isPlaying ? 1.12 : 1)

                Text(sound.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.header)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(isPlaying ? Theme.green.opacity(0.18) : Theme.listBackground, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isPlaying ? Theme.green : Theme.panelEdge, lineWidth: isPlaying ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.green)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                        .padding(8)
                        .transition(.opacity)
                }
            }
            .contentShape(.rect(cornerRadius: 16))
            .hoverBrighten(cornerRadius: 16)
        }
        .buttonStyle(SoundTileButtonStyle())
        .animation(.snappy, value: isPlaying)
        .contextMenu {
            Button("Preview", systemImage: "play.fill", action: preview)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let emoji = sound.emoji, !emoji.isEmpty {
            EmojiView(value: emoji, size: 34)
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
    }

    private func play() {
        Haptics.light()

        Task {
            await session.playSound(sound)
        }
    }

    private func preview() {
        session.previewSound(sound)
    }
}

// sinks under the finger, so a tap shows before the sound comes back from the server
private struct SoundTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}
