import SwiftUI

// pages swiped through sideways on a phone. a mac shows only the picked one: a tab view there
// put an empty tab bar in the window's toolbar, and these screens have their own way to pick
struct PagedTabs<Item: Identifiable, Value: Hashable, Page: View>: View {
    @Binding var selection: Value
    let items: [Item]
    let value: (Item) -> Value
    @ViewBuilder let page: (Item) -> Page

    var body: some View {
        #if os(macOS)
        // a page of its own per item, so a page's task runs again for the next one rather than
        // the same page being handed another item
        if let item = items.first(where: { value($0) == selection }) {
            page(item)
                .id(value(item))
        }
        #else
        TabView(selection: $selection) {
            ForEach(items) { item in
                page(item)
                    .tag(value(item))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
    }
}
