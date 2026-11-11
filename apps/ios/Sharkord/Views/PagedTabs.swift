import SwiftUI
#if os(iOS)
import UIKit
#endif

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
        .background {
            PagerSwipeBack(isOnFirstPage: items.first.map(value) == selection)
        }
        #endif
    }
}

#if os(iOS)
// the system's swipe back, which follows the finger, works in a pushed screen that pages:
// on the first page a swipe right goes back, on any other it pages back. without it the
// pager's own scroll took every sideways swipe and a screen of tabs could only be left by
// its back button
private struct PagerSwipeBack: UIViewRepresentable {
    let isOnFirstPage: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()

        view.isUserInteractionEnabled = false
        view.onMove = { [coordinator = context.coordinator] probe in
            coordinator.attach(from: probe)
        }

        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        context.coordinator.isOnFirstPage = isOnFirstPage
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class ProbeView: UIView {
        var onMove: ((ProbeView) -> Void)?

        // pushed, it lands in a window mid transition, before the pager beside it is laid
        // out, so it looks again on each layout until it has found it
        override func didMoveToWindow() {
            super.didMoveToWindow()

            if window != nil {
                onMove?(self)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            if window != nil {
                onMove?(self)
            }
        }
    }

    final class Coordinator {
        private weak var popGesture: UIGestureRecognizer?

        var isOnFirstPage = true {
            didSet {
                popGesture?.isEnabled = isOnFirstPage
            }
        }

        func attach(from probe: UIView) {
            guard
                popGesture == nil,
                let navigation = Self.navigationController(of: probe),
                let pop = navigation.interactiveContentPopGestureRecognizer,
                let pager = Self.pager(near: probe)
            else {
                return
            }

            // the pager's pan waits on the swipe back, which gives up at once on a swipe left
            // or when it is switched off away from the first page
            pager.panGestureRecognizer.require(toFail: pop)
            popGesture = pop
            pop.isEnabled = isOnFirstPage
        }

        // the swipe back belongs to the whole stack, the pager going away hands it back
        func detach() {
            popGesture?.isEnabled = true
        }

        private static func navigationController(of view: UIView) -> UINavigationController? {
            var responder: UIResponder? = view

            while let current = responder {
                if let controller = current as? UIViewController, let navigation = controller.navigationController {
                    return navigation
                }

                responder = current.next
            }

            return nil
        }

        // the probe sits behind the pager, both inside the page's own hosting view, where
        // swiftui nests the pager well down. only that far up: past it is the stack's other pages
        private static func pager(near view: UIView) -> UIScrollView? {
            var ancestor = view.superview

            for _ in 0..<3 {
                guard let current = ancestor else {
                    return nil
                }

                if let found = pagingScrollView(in: current, depth: 24) {
                    return found
                }

                ancestor = current.superview
            }

            return nil
        }

        private static func pagingScrollView(in view: UIView, depth: Int) -> UIScrollView? {
            if let scrollView = view as? UIScrollView, scrollView.isPagingEnabled {
                return scrollView
            }

            guard depth > 0 else {
                return nil
            }

            for subview in view.subviews {
                if let found = pagingScrollView(in: subview, depth: depth - 1) {
                    return found
                }
            }

            return nil
        }
    }
}
#endif
