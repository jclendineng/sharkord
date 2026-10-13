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
