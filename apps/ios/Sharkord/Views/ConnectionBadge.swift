import SwiftUI

// the call's signal bars, green, yellow or red, with the ping and the packet loss on a tap
struct ConnectionBadge: View {
    // a circle on the call screen, the call sheet's rounded square otherwise, like the buttons beside it
    var isRound = false

    @Environment(SessionStore.self) private var session

    @State private var isDetailShown = false

    private var quality: ConnectionQuality? {
        session.connectionQuality
    }

    private var color: Color {
        switch quality?.grade {
        case .good:
            Theme.green
        case .fair:
            Theme.yellow
        case .poor:
            Theme.red
        case nil:
            Theme.muted
        }
    }

    private var bars: Double {
        switch quality?.grade {
        case .good:
            1
        case .fair:
            0.66
        case .poor:
            0.33
        case nil:
            0
        }
    }

    var body: some View {
        Button(action: showDetail) {
            Image(systemName: "cellularbars", variableValue: bars)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(isRound ? Theme.listBackground : Theme.deepBackground, in: .rect(cornerRadius: isRound ? 20 : 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .popover(isPresented: $isDetailShown) {
            detail
                .presentationCompactAdaptation(.popover)
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(color)

            LabeledContent("Ping", value: quality?.ping.map { "\($0) ms" } ?? "Measuring")

            LabeledContent("Packet Loss", value: quality.map { $0.loss.formatted(.percent.precision(.fractionLength(1))) } ?? "Measuring")
        }
        .font(.subheadline)
        .foregroundStyle(Theme.header)
        .padding(16)
        .frame(minWidth: 220)
    }

    private var title: String {
        switch quality?.grade {
        case .good:
            "Good Connection"
        case .fair:
            "Unstable Connection"
        case .poor:
            "Poor Connection"
        case nil:
            "Connecting"
        }
    }

    private func showDetail() {
        isDetailShown = true
    }
}
