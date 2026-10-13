import UIKit

// the keyboard's height as last shown, so the attachment panel can be exactly as tall and the
// two can trade places without the composer above them moving
enum KeyboardMetrics {
    // a phone keyboard above the home indicator, until one has been seen
    private static let fallback: CGFloat = 300

    private static var observer: NSObjectProtocol?

    // how much of the keyboard sits above the bottom safe area, which is what the composer
    // rests on
    private(set) static var heightAboveSafeArea: CGFloat = fallback

    @MainActor
    static func start() {
        guard observer == nil else {
            return
        }

        observer = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                return
            }

            MainActor.assumeIsolated {
                let bottomInset = UIApplication.shared.topViewController?.view.window?.safeAreaInsets.bottom ?? 0

                // a hardware keyboard shows only a thin bar, keep the last real height then
                if frame.height > 200 {
                    heightAboveSafeArea = frame.height - bottomInset
                }
            }
        }
    }
}
