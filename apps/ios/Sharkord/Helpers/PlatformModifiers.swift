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

    func pagedTabs() -> some View {
        #if os(macOS)
        self
        #else
        tabViewStyle(.page(indexDisplayMode: .never))
        #endif
    }

    func fullScreen<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented, content: content)
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }

    func fullScreen<Item: Identifiable, Content: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(macOS)
        sheet(item: item, content: content)
        #else
        fullScreenCover(item: item, content: content)
        #endif
    }
}

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

    static var barTrailing: Self {
        #if os(macOS)
        .primaryAction
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
