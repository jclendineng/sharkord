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
            AsyncImage(url: address.fileURL(avatar)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(hex: user?.profileColor ?? "#5865F2")

            Image(systemName: "person.fill")
                .font(.system(size: size * 0.5))
                .foregroundStyle(.white)
        }
    }
}
