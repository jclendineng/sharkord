import SwiftUI

// the mac's server search, a card hanging under the box above the channel list, styled as the
// chat's search dropdown. a click anywhere else puts it away
struct SearchDropdownCard: View {
    private static let width: CGFloat = 500
    private static let maxHeight: CGFloat = 640

    let dropdown: ServerListStore.SearchDropdown

    @Environment(ServerListStore.self) private var servers

    var body: some View {
        GeometryReader { proxy in
            let top = dropdown.anchor.maxY + 6
            let left = min(dropdown.anchor.minX, proxy.size.width - Self.width - 12)

            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(perform: close)

                NavigationStack {
                    SearchScreen(channelId: dropdown.route.channelId, directMessages: dropdown.route.directMessages)
                }
                .frame(width: Self.width)
                .frame(maxHeight: min(Self.maxHeight, proxy.size.height - top - 12))
                .background(Theme.deepBackground)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.panelEdge, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                .compositingGroup()
                .offset(x: max(12, left), y: top)
            }
        }
        // escape puts it away, as it does the chat's
        .background {
            Button("Close Search", action: close)
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
    }

    private func close() {
        servers.searchDropdown = nil
    }
}
