import SwiftUI

// where a right click landed: within the view it was on, and within the window, for a menu
// held by a view further up than the row that was clicked
struct SecondaryClick {
    let anchor: UnitPoint
    let windowPoint: CGPoint
}

extension EnvironmentValues {
    // closes the mac's pointer menu a long press sheet is shown in, where dismiss has nothing
    // to dismiss
    @Entry var closePointerMenu: (() -> Void)?
}

extension View {
    // what a long press opens on a touch screen, a right click opens with a mouse or trackpad
    func onSecondaryClick(perform action: @escaping (SecondaryClick) -> Void) -> some View {
        overlay {
            if Platform.isMac {
                SecondaryClickView(action: action)
            }
        }
    }

    // a name over the view while the pointer is on it, as discord's are, on a mac
    func pointerTooltip(_ text: String) -> some View {
        modifier(PointerTooltip(text: text))
    }

    // a long press sheet on a touch screen. on a mac, discord's menu beside the pointer instead,
    // which a click anywhere else closes
    func actionsPresentation<Menu: View>(
        isPresented: Binding<Bool>,
        anchor: UnitPoint,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder menu: @escaping () -> Menu
    ) -> some View {
        modifier(ActionsPresentation(isPresented: isPresented, anchor: anchor, onDismiss: onDismiss, menu: menu))
    }

    func actionsPresentation<Item: Identifiable, Menu: View>(
        item: Binding<Item?>,
        anchor: UnitPoint,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder menu: @escaping (Item) -> Menu
    ) -> some View {
        modifier(ItemActionsPresentation(item: item, anchor: anchor, onDismiss: onDismiss, menu: menu))
    }
}

private let isOnMac = Platform.isMac

private struct ActionsPresentation<Menu: View>: ViewModifier {
    @Binding var isPresented: Bool
    let anchor: UnitPoint
    let onDismiss: (() -> Void)?
    @ViewBuilder let menu: () -> Menu

    @State private var menuId = UUID()
    @State private var frame = CGRect.zero

    func body(content: Content) -> some View {
        if isOnMac {
            content
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { newFrame in
                    frame = newFrame
                }
                .onChange(of: isPresented, presentedChanged)
        } else {
            content
                .sheet(isPresented: $isPresented, onDismiss: onDismiss, content: menu)
        }
    }

    private func presentedChanged(_: Bool, _ presented: Bool) {
        if presented {
            PointerMenus.show(menuId, at: point(of: anchor, in: frame), content: AnyView(menu()), close: close)
        } else {
            PointerMenus.closed(menuId)
            onDismiss?()
        }
    }

    private func close() {
        isPresented = false
    }
}

private struct ItemActionsPresentation<Item: Identifiable, Menu: View>: ViewModifier {
    @Binding var item: Item?
    let anchor: UnitPoint
    let onDismiss: (() -> Void)?
    @ViewBuilder let menu: (Item) -> Menu

    @State private var menuId = UUID()
    @State private var frame = CGRect.zero

    func body(content: Content) -> some View {
        if isOnMac {
            content
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { newFrame in
                    frame = newFrame
                }
                .onChange(of: item.map { AnyHashable($0.id) }, itemChanged)
        } else {
            content
                .sheet(item: $item, onDismiss: onDismiss, content: menu)
        }
    }

    private func itemChanged(_: AnyHashable?, _: AnyHashable?) {
        if let item {
            PointerMenus.show(menuId, at: point(of: anchor, in: frame), content: AnyView(menu(item)), close: close)
        } else {
            PointerMenus.closed(menuId)
            onDismiss?()
        }
    }

    private func close() {
        item = nil
    }
}

private struct PointerTooltip: ViewModifier {
    let text: String

    @State private var frame = CGRect.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { newFrame in
                frame = newFrame
            }
            .onHover(perform: hovered)
            // a view going while the pointer is on it, a hover bar as its row loses the pointer,
            // never hears it leave
            .onDisappear(perform: disappeared)
    }

    private func disappeared() {
        PointerMenus.hideTooltip(text)
    }

    private func hovered(_ isHovered: Bool) {
        guard isOnMac else {
            return
        }

        if isHovered {
            PointerMenus.showTooltip(text, over: frame)
        } else {
            PointerMenus.hideTooltip(text)
        }
    }
}

private func point(of anchor: UnitPoint, in frame: CGRect) -> CGPoint {
    CGPoint(x: frame.minX + anchor.x * frame.width, y: frame.minY + anchor.y * frame.height)
}

struct ShownPointerMenu {
    let id: UUID
    // in the window
    let point: CGPoint
    let content: AnyView
}

struct ShownTooltip {
    let text: String
    // the view it names, in the window
    let anchor: CGRect
}

struct ShownSubmenu {
    let id: UUID
    // the row it opened from, in the window
    let anchor: CGRect
    let content: AnyView
}

@Observable
final class PointerMenuState {
    static let shared = PointerMenuState()

    fileprivate(set) var shown: ShownPointerMenu?
    fileprivate(set) var submenu: ShownSubmenu?
    fileprivate(set) var tooltip: ShownTooltip?
    // where the menu and its submenu are drawn, in the window, so a right click on them leaves
    // them be
    var menuFrame = CGRect.zero
    var submenuFrame = CGRect.zero
    // a right click outside the menus, in the window, for a panel that a click elsewhere puts
    // away, the chat's inbox and pins among them
    fileprivate(set) var rightClicks = 0
    fileprivate(set) var rightClickPoint = CGPoint.zero
}

// discord's right click works over and over: one on something with a menu moves the open menu
// there, one anywhere else closes it, and a click outside closes it at once. a mac hands an
// ipad app a right click only as a context menu request, never as a touch, and a system
// popover's backdrop swallowed those and was slow to go, so the menus are drawn in the app's
// own layer over the window instead (PointerMenuLayer)
enum PointerMenus {
    fileprivate static let views = NSHashTable<RightClickOnlyView>.weakObjects()
    private static var openMenu: (id: UUID, close: () -> Void)?

    private static var state: PointerMenuState {
        PointerMenuState.shared
    }

    // a menu drawn by its owner, the server rail's, that a right click elsewhere should close
    static func opened(_ id: UUID, close: @escaping () -> Void) {
        openMenu = (id, close)
    }

    // a menu already replaced by the next one closing late leaves that one in place
    static func closed(_ id: UUID) {
        if openMenu?.id == id {
            openMenu = nil
        }

        if state.shown?.id == id {
            state.shown = nil
        }
    }

    fileprivate static func show(_ id: UUID, at point: CGPoint, content: AnyView, close: @escaping () -> Void) {
        opened(id, close: close)
        state.submenu = nil
        state.shown = ShownPointerMenu(id: id, point: point, content: content)
    }

    static func showSubmenu(_ id: UUID, beside anchor: CGRect, content: AnyView) {
        state.submenu = ShownSubmenu(id: id, anchor: anchor, content: content)
    }

    static func showTooltip(_ text: String, over anchor: CGRect) {
        state.tooltip = ShownTooltip(text: text, anchor: anchor)
    }

    // only its own, the pointer reaching the next one may already have replaced it
    static func hideTooltip(_ text: String) {
        if state.tooltip?.text == text {
            state.tooltip = nil
        }
    }

    static func hideSubmenu() {
        if state.submenu != nil {
            state.submenu = nil
        }
    }

    static func closeCurrent() {
        let menu = openMenu

        openMenu = nil
        state.tooltip = nil
        state.submenu = nil
        state.shown = nil
        menu?.close()
    }

    // from a row's own context menu request, or the window's when no row was under the pointer
    fileprivate static func rightClick(at point: CGPoint, on row: RightClickOnlyView?) {
        let isOnSubmenu = state.submenu != nil && state.submenuFrame.contains(point)
        let isOnMenu = state.shown != nil && (state.menuFrame.contains(point) || isOnSubmenu)

        if isOnMenu {
            return
        }

        state.rightClickPoint = point
        state.rightClicks += 1

        let target = row ?? views.allObjects.last { view in
            view.window != nil && view.contains(windowPoint: point)
        }
        let hadMenu = openMenu != nil

        closeCurrent()

        guard let target else {
            return
        }

        guard hadMenu else {
            target.open(at: point)
            return
        }

        // the closing has to reach the view before the same row can open again, or the two
        // changes cancel out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            target.open(at: point)
        }
    }
}

// the open menu by the pointer, over the whole window, and a submenu beside it. a click anywhere
// else closes them
struct PointerMenuLayer: View {
    private static let width: CGFloat = 220
    private static let submenuWidth: CGFloat = 200

    private let state = PointerMenuState.shared

    @State private var layerFrame = CGRect.zero
    @State private var menuSize = CGSize.zero
    @State private var submenuSize = CGSize.zero
    @State private var tooltipSize = CGSize.zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let shown = state.shown {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(perform: PointerMenus.closeCurrent)

                // escape closes it, as it does a mac menu
                Button("Close Menu", action: PointerMenus.closeCurrent)
                    .keyboardShortcut(.cancelAction)
                    .hidden()

                card(shown.content, width: Self.width)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: menuMoved)
                    .offset(offset(for: shown.point))
                    .id(shown.id)

                if let submenu = state.submenu {
                    card(submenu.content.environment(\.isInSubmenu, true), width: Self.submenuWidth)
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: submenuMoved)
                        .offset(submenuOffset(beside: submenu.anchor))
                        .id(submenu.id)
                }
            }

            if let tooltip = state.tooltip {
                Text(tooltip.text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.header)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black, in: .rect(cornerRadius: 6))
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self, of: \.size) { size in
                        tooltipSize = size
                    }
                    .offset(tooltipOffset(over: tooltip.anchor))
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
            layerFrame = frame
        }
    }

    private func card(_ content: some View, width: CGFloat) -> some View {
        content
            .environment(\.isPointerMenu, true)
            .environment(\.closePointerMenu, PointerMenus.closeCurrent)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.deepBackground)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.panelEdge, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .compositingGroup()
    }

    // at the pointer, moved back in where it would run off the right, and up as far as it has
    // to where it would run off the bottom, as discord's are
    private func offset(for point: CGPoint) -> CGSize {
        let x = point.x - layerFrame.minX
        let y = point.y - layerFrame.minY
        let maxX = layerFrame.width - Self.width - 8
        let maxY = layerFrame.height - menuSize.height - 8

        return CGSize(
            width: max(min(x, maxX), 8),
            height: max(min(y, maxY), 8)
        )
    }

    // level with its row, to the right of the menu or to its left where the window ends
    private func submenuOffset(beside anchor: CGRect) -> CGSize {
        let right = state.menuFrame.maxX + 4 - layerFrame.minX
        let left = state.menuFrame.minX - Self.submenuWidth - 4 - layerFrame.minX
        let fitsRight = right + Self.submenuWidth + 8 <= layerFrame.width
        let top = anchor.minY - 6 - layerFrame.minY

        return CGSize(
            width: fitsRight ? right : max(left, 8),
            height: max(min(top, layerFrame.height - submenuSize.height - 8), 8)
        )
    }

    // centred over the view it names, a little above it
    private func tooltipOffset(over anchor: CGRect) -> CGSize {
        CGSize(
            width: max(anchor.midX - layerFrame.minX - tooltipSize.width / 2, 4),
            height: max(anchor.minY - layerFrame.minY - tooltipSize.height - 6, 4)
        )
    }

    private func menuMoved(_ frame: CGRect) {
        menuSize = frame.size
        state.menuFrame = frame
    }

    private func submenuMoved(_ frame: CGRect) {
        submenuSize = frame.size
        state.submenuFrame = frame
    }
}

#if os(macOS)
// over the row, but only a right click lands on it. every other click falls through to the
// row's own gestures as if it were not there. points are in the window's content, top left
// first, the way swiftui's global frames are
private final class RightClickOnlyView: NSView {
    var action: (SecondaryClick) -> Void = { _ in }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent, event.type == .rightMouseDown || event.type == .rightMouseUp else {
            return nil
        }

        return super.hitTest(point)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            PointerMenus.views.add(self)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let content = window?.contentView else {
            return
        }

        PointerMenus.rightClick(at: content.convert(event.locationInWindow, from: nil), on: self)
    }

    func contains(windowPoint: CGPoint) -> Bool {
        bounds.contains(convert(windowPoint, from: window?.contentView))
    }

    func open(at windowPoint: CGPoint) {
        let location = convert(windowPoint, from: window?.contentView)
        let anchor = UnitPoint(
            x: bounds.width > 0 ? location.x / bounds.width : 0.5,
            y: bounds.height > 0 ? location.y / bounds.height : 0.5
        )

        action(SecondaryClick(anchor: anchor, windowPoint: windowPoint))
    }
}

private struct SecondaryClickView: NSViewRepresentable {
    let action: (SecondaryClick) -> Void

    func makeNSView(context: Context) -> RightClickOnlyView {
        let view = RightClickOnlyView()

        view.action = action

        return view
    }

    func updateNSView(_ view: RightClickOnlyView, context: Context) {
        view.action = action
    }
}
#else
// the window's own catcher for a right click on nothing that has a menu, found after every row
private final class WindowRightClick: NSObject, UIContextMenuInteractionDelegate {
    static let shared = WindowRightClick()

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        PointerMenus.rightClick(at: interaction.location(in: nil), on: nil)

        return nil
    }
}

// over the row, but only a right click lands on it. every other click falls through to the
// row's own gestures as if it were not there
private final class RightClickOnlyView: UIView {
    var action: (SecondaryClick) -> Void = { _ in }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let mask = event?.buttonMask ?? []

        guard mask.contains(.secondary) else {
            return nil
        }

        return super.hitTest(point, with: event)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard let window else {
            return
        }

        PointerMenus.views.add(self)

        let hasCatcher = window.interactions.contains { interaction in
            (interaction as? UIContextMenuInteraction)?.delegate === WindowRightClick.shared
        }

        if !hasCatcher {
            window.addInteraction(UIContextMenuInteraction(delegate: WindowRightClick.shared))
        }
    }

    func contains(windowPoint: CGPoint) -> Bool {
        bounds.contains(convert(windowPoint, from: nil))
    }

    func open(at windowPoint: CGPoint) {
        let location = convert(windowPoint, from: nil)
        let anchor = UnitPoint(
            x: bounds.width > 0 ? location.x / bounds.width : 0.5,
            y: bounds.height > 0 ? location.y / bounds.height : 0.5
        )

        action(SecondaryClick(anchor: anchor, windowPoint: windowPoint))
    }
}

// a mac hands an ipad app's right click only to a context menu interaction, never to a tap
// recogniser. this one opens the app's own menu and gives the system none to show
private struct SecondaryClickView: UIViewRepresentable {
    let action: (SecondaryClick) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RightClickOnlyView {
        let view = RightClickOnlyView()

        view.action = action
        view.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))

        return view
    }

    func updateUIView(_ view: RightClickOnlyView, context: Context) {
        view.action = action
    }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            PointerMenus.rightClick(at: interaction.location(in: nil), on: interaction.view as? RightClickOnlyView)

            return nil
        }
    }
}
#endif
