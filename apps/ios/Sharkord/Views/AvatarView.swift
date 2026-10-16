import SwiftUI

struct AvatarView: View {
    let user: PublicUser?
    var size: CGFloat = 40
    var showsStatus = false

    @Environment(SessionStore.self) private var session

    var body: some View {
        image
            .frame(width: size, height: size)
            .clipShape(.circle)
            .overlay(alignment: .bottomTrailing) {
                if showsStatus {
                    Circle()
                        .fill(Theme.statusColor(user?.status))
                        .frame(width: size * 0.32, height: size * 0.32)
                        .overlay {
                            Circle().stroke(Theme.chatBackground, lineWidth: size * 0.08)
                        }
                        .offset(x: size * 0.04, y: size * 0.04)
                }
            }
    }

    @ViewBuilder
    private var image: some View {
        if let avatar = user?.avatar, let address = session.address {
            CachedFileImage(file: avatar, url: address.fileURL(avatar)) {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)

            Image(systemName: "person.fill")
                .font(.system(size: size * 0.5))
                .foregroundStyle(.white)
        }
    }

    // getAvatarGradient in packages/shared: a picked profile color, otherwise a hue from the id
    // spread by the golden angle so neighbouring ids look different
    private var gradient: [Color] {
        if let profileColor = user?.profileColor, profileColor != "#262626" {
            return [Color(hex: profileColor)]
        }

        let hue = ((Double(user?.id ?? 0) * 137.508).truncatingRemainder(dividingBy: 360)).rounded()

        return [
            Self.hsl(hue: hue, saturation: 0.60, lightness: 0.52),
            Self.hsl(hue: (hue + 40).truncatingRemainder(dividingBy: 360), saturation: 0.65, lightness: 0.38)
        ]
    }

    // SwiftUI only takes hue, saturation and brightness, so the css hsl values are converted
    private static func hsl(hue: Double, saturation: Double, lightness: Double) -> Color {
        let brightness = lightness + saturation * min(lightness, 1 - lightness)
        let hsbSaturation = brightness == 0 ? 0 : 2 * (1 - lightness / brightness)

        return Color(hue: hue / 360, saturation: hsbSaturation, brightness: brightness)
    }
}
