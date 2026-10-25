import SwiftUI

// the mac's server search, a card hanging under the box above the channel list, styled as the
// chat's search dropdown. a click anywhere else puts it away
struct SearchDropdownCard: View {
    private static let width: CGFloat = 500
    private static let maxHeight: CGFloat = 640

    let dropdown: ServerListStore.SearchDropdown

    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session

    @State private var model = SearchQueryModel()
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let top = dropdown.anchor.maxY + 6
            let left = min(dropdown.anchor.minX, proxy.size.width - Self.width - 12)

            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(perform: close)

                // the box at the card's top rather than in the screen's own bar: a stack inside the
                // window has no bar of its own on a mac, and its box and filters went up into the
                // window's toolbar beside the chat's
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        SearchBox(
                            model: model,
                            prompt: model.prompt(in: session, directMessages: dropdown.route.directMessages),
                            isFocused: $isFieldFocused
                        )

                        FilterMenu(isFiltering: model.filters.narrowsPastChannel, onChoose: chooseFilter)
                    }
                    .padding(10)

                    NavigationStack {
                        SearchScreen(
                            channelId: dropdown.route.channelId,
                            directMessages: dropdown.route.directMessages,
                            model: model,
                            showsSearchBox: false
                        )
                    }
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
        // a moment after it appears, before which the window has not settled its first responder
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            isFieldFocused = true
        }
        .onChange(of: model.focusRequest) {
            isFieldFocused = true
        }
    }

    private func chooseFilter(_ picker: FilterPicker) {
        if picker.isDate {
            model.pendingDatePicker = picker
            return
        }

        model.token = picker
        model.query = ""
        isFieldFocused = true
    }

    private func close() {
        servers.searchDropdown = nil
    }
}
