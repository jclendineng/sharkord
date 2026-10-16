import SwiftUI

// where a right click landed: within the view it was on, and within the window, for a popover
// held by a view further up than the row that was clicked
struct SecondaryClick {
    let anchor: UnitPoint
    let windowPoint: CGPoint
}

extension View {
    // what a long press opens on a touch screen, a right click opens with a mouse or trackpad
    func onSecondaryClick(perform action: @escaping (SecondaryClick) -> Void) -> some View {
        overlay {
            if ProcessInfo.processInfo.isiOSAppOnMac {
                SecondaryClickView(action: action)
            }
        }
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
        @ViewBuilder menu: @escaping (Item) -> Menu
    ) -> some View {
        modifier(ItemActionsPresentation(item: item, anchor: anchor, menu: menu))
    }
}

private let isOnMac = ProcessInfo.processInfo.isiOSAppOnMac

private struct ActionsPresentation<Menu: View>: ViewModifier {
    @Binding var isPresented: Bool
    let anchor: UnitPoint
    let onDismiss: (() -> Void)?
    @ViewBuilder let menu: () -> Menu

    func body(content: Content) -> some View {
        if isOnMac {
            content
                .popover(isPresented: $isPresented, attachmentAnchor: .point(anchor)) {
                    menu()
                        .popoverMenu()
                }
                .onChange(of: isPresented, closed)
        } else {
            content
                .sheet(isPresented: $isPresented, onDismiss: onDismiss, content: menu)
        }
    }

    private func closed(_: Bool, _ presented: Bool) {
        if !presented {
            onDismiss?()
            SecondaryClickReplay.replay()
        }
    }
}

private struct ItemActionsPresentation<Item: Identifiable, Menu: View>: ViewModifier {
    @Binding var item: Item?
    let anchor: UnitPoint
    @ViewBuilder let menu: (Item) -> Menu

    func body(content: Content) -> some View {
        if isOnMac {
            content
                .popover(item: $item, attachmentAnchor: .point(anchor)) { item in
                    menu(item)
                        .popoverMenu()
                }
                .onChange(of: item == nil, closed)
        } else {
            content
                .sheet(item: $item, content: menu)
        }
    }

    private func closed(_: Bool, _ isClosed: Bool) {
        if isClosed {
            SecondaryClickReplay.replay()
        }
    }
}

extension View {
    // as tall as its rows, the long press sheet's scroll view otherwise asking for the whole
    // screen
    fileprivate func popoverMenu() -> some View {
        frame(width: 320)
            .fixedSize(horizontal: false, vertical: true)
            .presentationCompactAdaptation(.popover)
    }
}

// a right click while a menu is open only closes it, the click landing on the popover's
// backdrop rather than the row under it. discord opens that row's menu instead, so the click is
// noted on its way in and played again on the row once the menu has gone
private enum SecondaryClickReplay {
    static let views = NSHashTable<RightClickOnlyView>.weakObjects()
    static var lastClick: (point: CGPoint, time: Date)?

    static func record(_ point: CGPoint) {
        lastClick = (point, Date())
    }

    static func replay() {
        guard let click = lastClick, Date().timeIntervalSince(click.time) < 0.5 else {
            return
        }

        lastClick = nil

        // a popover cannot open while the last one is still on its way out
        Task {
            try? await Task.sleep(for: .milliseconds(300))

            let target = views.allObjects.last { view in
                view.window != nil && view.bounds.contains(view.convert(click.point, from: nil))
            }

            target?.open(at: click.point)
        }
    }
}

// sees every right click in the window, the ones on a popover's backdrop too, and steps aside
// at once so no other gesture waits on it
private final class SecondaryClickWatcher: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if event.buttonMask.contains(.secondary), let touch = touches.first {
            SecondaryClickReplay.record(touch.location(in: nil))
        }

        state = .failed
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

        SecondaryClickReplay.views.add(self)

        let recognizers = window.gestureRecognizers ?? []

        if !recognizers.contains(where: { $0 is SecondaryClickWatcher }) {
            let watcher = SecondaryClickWatcher()

            watcher.cancelsTouchesInView = false
            watcher.delaysTouchesEnded = false
            window.addGestureRecognizer(watcher)
        }
    }

    func open(at windowPoint: CGPoint) {
        SecondaryClickReplay.lastClick = nil

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
            let view = interaction.view as? RightClickOnlyView

            view?.open(at: interaction.location(in: nil))

            return nil
        }
    }
}
