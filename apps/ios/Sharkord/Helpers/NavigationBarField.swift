#if os(iOS)
import UIKit

// a text field in a navigation bar doesn't get the keyboard from focus state alone, so it is
// found in the key window's bars and made first responder directly. the search screen's box and
// the ipad chat's box in its top bar both need it
enum NavigationBarField {
    static func focus() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)

        guard let window = windows.first(where: \.isKeyWindow) else {
            return
        }

        // the topmost one, a full screen cover's bar over the screen it covers
        let field = fields(in: window).last

        field?.becomeFirstResponder()
    }

    private static func fields(in view: UIView, isInBar: Bool = false) -> [UITextField] {
        let isBar = isInBar || view is UINavigationBar

        if isBar, let field = view as? UITextField {
            return [field]
        }

        return view.subviews.flatMap { fields(in: $0, isInBar: isBar) }
    }
}
#endif
