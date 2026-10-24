import AVFoundation
import SwiftUI

// the camera's effects in the app's own look: your picture, reactions to play on it, center
// stage. portrait and studio light are the user's alone, apple lets an app read them but only
// its own panel changes them, so those rows say where they stand and open that panel
struct VideoEffectsSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var effects: VoiceConnection.CameraEffects?
    @State private var isCenterStageOn = AVCaptureDevice.isCenterStageEnabled
    @State private var isPortraitOn = AVCaptureDevice.isPortraitEffectEnabled
    @State private var isStudioLightOn = AVCaptureDevice.isStudioLightEnabled

    private var ownTrack: VideoTrackBox? {
        session.ownUserId.flatMap { session.videoTracks[VoiceStreamKey(kind: .video, remoteId: $0)] }
    }

    private var centerStage: Binding<Bool> {
        Binding(
            get: { isCenterStageOn },
            set: setCenterStage
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    preview

                    if let effects, !effects.reactions.isEmpty {
                        SettingsCard(title: "Reactions", footnote: "Hand gestures play them too, like a thumbs up, a heart with both hands or a peace sign.") {
                            ReactionGrid(reactions: effects.reactions, onPlay: play)
                        }
                    }

                    if effects?.supportsCenterStage == true {
                        SettingsCard(title: "Framing") {
                            SettingToggle(
                                title: "Center Stage",
                                subtitle: "Keeps you in frame as you move",
                                systemImage: "person.crop.square.badge.camera",
                                isOn: centerStage
                            )
                        }
                    }

                    SettingsCard(title: "Look", footnote: "Apple keeps these two for you to choose in its own panel, the app can only show where they stand.") {
                        StatusRow(title: "Portrait", subtitle: "Blurs what is behind you", systemImage: "f.cursive", isOn: isPortraitOn)

                        CardDivider()

                        StatusRow(title: "Studio Light", subtitle: "Lights your face, dims the background", systemImage: "cube", isOn: isStudioLightOn)

                        CardDivider()

                        Button(action: showSystemPanel) {
                            HStack(spacing: 14) {
                                SettingIcon(systemImage: "slider.horizontal.3")

                                Text("Change Portrait or Studio Light")
                                    .foregroundStyle(Theme.header)

                                Spacer()

                                Image(systemName: "arrow.up.forward.app")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.listBackground)
            .navigationTitle("Video Effects")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
        }
        .sheetDetents([.large])
        .presentationBackground(Theme.listBackground)
        // the panel and control center change these without telling the app, so they are read
        // again while the sheet is up
        .task {
            effects = await session.cameraEffects()

            while !Task.isCancelled {
                refreshStates()

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var preview: some View {
        ZStack {
            Theme.deepBackground

            if let ownTrack {
                VideoView(track: ownTrack, isMirrored: true)
            } else {
                Label("Your camera is off", systemImage: "video.slash")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.muted)
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .frame(maxWidth: 260)
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.panelEdge, lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func refreshStates() {
        isCenterStageOn = AVCaptureDevice.isCenterStageEnabled
        isPortraitOn = AVCaptureDevice.isPortraitEffectEnabled
        isStudioLightOn = AVCaptureDevice.isStudioLightEnabled
    }

    // cooperative, so a change in control center still counts and the app follows it
    private func setCenterStage(_ isOn: Bool) {
        AVCaptureDevice.centerStageControlMode = .cooperative
        AVCaptureDevice.isCenterStageEnabled = isOn
        isCenterStageOn = isOn
    }

    private func play(_ reaction: AVCaptureReactionType) {
        session.performCameraReaction(reaction)
    }

    private func showSystemPanel() {
        AVCaptureDevice.showSystemUserInterface(.videoEffects)
    }

    private func close() {
        dismiss()
    }
}

// a reaction's symbol in a circle, four to a row, played on the camera with a tap
private struct ReactionGrid: View {
    let reactions: [AVCaptureReactionType]
    let onPlay: (AVCaptureReactionType) -> Void

    // apple's own order, the way its panel and the gestures list them
    private static let order: [AVCaptureReactionType] = [
        .heart, .thumbsUp, .thumbsDown, .balloons, .rain, .confetti, .fireworks, .lasers
    ]

    private var sorted: [AVCaptureReactionType] {
        reactions.sorted { (Self.order.firstIndex(of: $0) ?? 99) < (Self.order.firstIndex(of: $1) ?? 99) }
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(sorted, id: \.rawValue) { reaction in
                ReactionButton(reaction: reaction, onPlay: onPlay)
            }
        }
        .padding(14)
    }
}

private struct ReactionButton: View {
    let reaction: AVCaptureReactionType
    let onPlay: (AVCaptureReactionType) -> Void

    @State private var plays = 0

    var body: some View {
        Button(action: play) {
            Image(systemName: reaction.systemImageName)
                .font(.system(size: 22))
                .symbolRenderingMode(.multicolor)
                .symbolEffect(.bounce, value: plays)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.listBackground, in: .rect(cornerRadius: 14))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: plays)
        .accessibilityLabel(title)
    }

    private var title: String {
        switch reaction {
        case .heart: "Heart"
        case .thumbsUp: "Thumbs Up"
        case .thumbsDown: "Thumbs Down"
        case .balloons: "Balloons"
        case .rain: "Rain"
        case .confetti: "Confetti"
        case .fireworks: "Fireworks"
        case .lasers: "Lasers"
        default: "Reaction"
        }
    }

    private func play() {
        plays += 1
        onPlay(reaction)
    }
}

// an effect only apple's panel changes: whether it is on, nothing to flip here
private struct StatusRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            SettingIcon(systemImage: systemImage)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Theme.header)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

            Text(isOn ? "On" : "Off")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? Theme.green : Theme.muted)
                .contentTransition(.numericText())
                .animation(.snappy, value: isOn)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
