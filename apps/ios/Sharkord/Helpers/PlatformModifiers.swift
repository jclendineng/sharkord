import SwiftUI

// the iphone and ipad modifiers a mac has no such thing for, under names both can call. a mac
// window has a toolbar rather than a navigation bar, and a sheet where a phone covers the screen
extension View {
    func inlineNavigationTitle() -> some View {
        #if os(macOS)
        self
        #else
        navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // no window name in the middle of the bar, where it sat between the channel's name and the
    // search box. left empty rather than removed: without a title a mac packs every item at the
    // bar's leading edge
    func windowTitleBlank() -> some View {
        #if os(macOS)
        navigationTitle("")
        #else
        self
        #endif
    }

    // a settings page's own search. a mac put the toolbar's search field twice over a split view's
    // detail inside a sheet, once in each bar, so there it sits at the top of the page instead
    func pageSearchable(text: Binding<String>, prompt: String) -> some View {
        #if os(macOS)
        safeAreaInset(edge: .top, spacing: 0) {
            PageSearchField(text: text, prompt: prompt)
        }
        #else
        searchable(text: text, prompt: Text(prompt))
        #endif
    }

    // a mac list cuts a section's footer off at one line, where a phone's wraps
    func wrappingFooter() -> some View {
        lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    // a row's delete: a swipe on a phone, and a right click menu as well on a mac, where a row
    // is deleted the way it is in apple's own lists
    func rowDeleteAction(_ title: String = "Delete", perform action: @escaping () -> Void) -> some View {
        swipeActions {
            Button(title, systemImage: "trash", role: .destructive, action: action)
        }
        #if os(macOS)
        .contextMenu {
            Button(title, systemImage: "trash", role: .destructive, action: action)
        }
        #endif
    }

    // a mac's pointer turns to the column resize arrows over something that resizes a column
    func resizePointer() -> some View {
        #if os(macOS)
        pointerStyle(.columnResize)
        #else
        self
        #endif
    }

    // a mac's title bar see through, for a screen whose background runs to the window's top edge
    func transparentWindowBar() -> some View {
        #if os(macOS)
        toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #else
        self
        #endif
    }

    // a title with a line under it. a phone's bar stacks the two in its middle, a mac takes a
    // subtitle of its own: its sheets draw no item in the middle of the bar at all
    func titleWithSubtitle(_ title: String, subtitle: String?) -> some View {
        #if os(macOS)
        navigationTitle(title)
            .navigationSubtitle(subtitle ?? "")
        #else
        navigationTitle(title)
            .toolbar {
                if let subtitle {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(Theme.header)

                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        #endif
    }

    // the window's smallest: the rail, the channel list and a chat wide enough for its top bar's
    // search and icons. narrower, the bar put its icons away under a chevron and the message box
    // cut its own placeholder off
    func macWindowMinimumSize() -> some View {
        #if os(macOS)
        frame(minWidth: 940, minHeight: 600)
        #else
        self
        #endif
    }

    func noHoverEffect() -> some View {
        #if os(macOS)
        self
        #else
        hoverEffectDisabled()
        #endif
    }

    func navigationBarBackground(_ color: Color) -> some View {
        #if os(macOS)
        toolbarBackground(color, for: .windowToolbar)
        #else
        toolbarBackground(color, for: .navigationBar)
        #endif
    }

    func navigationBarBackgroundVisible() -> some View {
        #if os(macOS)
        toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        #else
        toolbarBackgroundVisibility(.visible, for: .navigationBar)
        #endif
    }

    func navigationBarHidden() -> some View {
        #if os(macOS)
        self
        #else
        toolbarVisibility(.hidden, for: .navigationBar)
        #endif
    }

    func tabBarHidden() -> some View {
        #if os(macOS)
        self
        #else
        toolbarVisibility(.hidden, for: .tabBar)
        #endif
    }

    // a mac sheet in place of the full screen, as large as the smallest window allows. a fixed
    // size: a mac sheet is otherwise only as big as its content, a sliver for a split view or a
    // list, and grew and shrank with each settings page picked
    func fullScreen<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented) {
            content()
                .frame(width: 860, height: 540)
                .phoneControlStyle()
                .phoneButtons()
        }
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }

    func fullScreen<Item: Identifiable, Content: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(macOS)
        sheet(item: item) { item in
            content(item)
                .frame(width: 860, height: 540)
                .phoneControlStyle()
                .phoneButtons()
        }
        #else
        fullScreenCover(item: item, content: content)
        #endif
    }

    // what a phone draws by default that a mac does not: a toggle as a switch rather than a
    // checkbox, a menu as its own label with no chevron beside it, a text field with no bezel of
    // its own inside the app's rounded boxes, no blue ring round a focused
    // field, which sat inside the app's own rounded ones, and list rows tall enough that a row
    // of text lines up with a row of avatars. a mac's sheets and popovers do not inherit it from
    // the window, so each presentation sets it again
    func phoneControlStyle() -> some View {
        #if os(macOS)
        toggleStyle(PhoneSwitchToggleStyle())
            .menuStyle(PhoneMenuStyle())
            .textFieldStyle(.plain)
            .focusEffectDisabled()
            .environment(\.defaultMinListRowHeight, 36)
        #else
        self
        #endif
    }

    // a phone's borderless button, for the app's own panels. not set for the whole window: it
    // reached every toolbar too, and stripped the bar's own spacing from its buttons
    func phoneButtons() -> some View {
        #if os(macOS)
        buttonStyle(.borderless)
        #else
        self
        #endif
    }

    // a mac sheet is only as big as its content asks, and a list asks for a sliver. a minimum
    // only, so a sheet that asks for more still gets it. one sized to its own content keeps its
    // height, a minimum left a grid of a few sounds over a tall empty space
    func macSheetMinimumSize(fitsContent: Bool = false) -> some View {
        #if os(macOS)
        frame(minWidth: 480, minHeight: fitsContent ? nil : 520)
        #else
        self
        #endif
    }

    // the side of the button a popover opens away from. a phone names the side of the popover
    // its arrow is on, a mac the side of the button it hangs off, so the two are opposites
    func popover<Content: View>(isPresented: Binding<Bool>, opensAwayFrom edge: Edge, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(macOS)
        popover(isPresented: isPresented, arrowEdge: edge.opposite) {
            content()
                .phoneControlStyle()
                .phoneButtons()
        }
        #else
        popover(isPresented: isPresented, arrowEdge: edge, content: content)
        #endif
    }
}

#if os(macOS)
private struct PageSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.muted)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Theme.inputBackground, in: .rect(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// a menu drawn as its own label, as a phone's is. a mac's borderless one drew the label as a
// template icon in the accent colour and ignored its size, and its default added a chevron
private struct PhoneMenuStyle: MenuStyle {
    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
    }
}

// a phone's switch, the label at the leading edge and the switch at the trailing one. a mac's
// own sits the switch right after its label
private struct PhoneSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            Spacer(minLength: 8)

            Toggle("", isOn: configuration.$isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

private extension Edge {
    var opposite: Edge {
        switch self {
        case .top:
            .bottom
        case .bottom:
            .top
        case .leading:
            .trailing
        case .trailing:
            .leading
        }
    }
}
#endif

// the on screen keyboard a field asks for, which a mac's hardware one ignores
enum KeyboardKind {
    case url
    case email
    case number
    case decimal
    case ascii

    #if os(iOS)
    fileprivate var type: UIKeyboardType {
        switch self {
        case .url:
            .URL
        case .email:
            .emailAddress
        case .number:
            .numberPad
        case .decimal:
            .decimalPad
        case .ascii:
            .asciiCapable
        }
    }
    #endif
}

extension View {
    func keyboard(_ kind: KeyboardKind) -> some View {
        #if os(macOS)
        self
        #else
        keyboardType(kind.type)
        #endif
    }

    // a list's reorder handles, which a mac's lists show only while dragging
    func editing(_ isActive: Bool) -> some View {
        #if os(macOS)
        self
        #else
        environment(\.editMode, .constant(isActive ? .active : .inactive))
        #endif
    }

    func noAutocapitalization() -> some View {
        #if os(macOS)
        self
        #else
        textInputAutocapitalization(.never)
        #endif
    }
}

extension ToolbarItemPlacement {
    static var barLeading: Self {
        #if os(macOS)
        .navigation
        #else
        .topBarLeading
        #endif
    }

    // a mac's primary action sits at the bar's leading edge, its automatic place at the trailing
    static var barTrailing: Self {
        #if os(macOS)
        .automatic
        #else
        .topBarTrailing
        #endif
    }
}

extension SearchFieldPlacement {
    // always showing, under the title on a phone
    static var alwaysShown: Self {
        #if os(macOS)
        .automatic
        #else
        .navigationBarDrawer(displayMode: .always)
        #endif
    }
}
