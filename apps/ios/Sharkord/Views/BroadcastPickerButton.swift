import ReplayKit
import SwiftUI

// only the system picker may start a broadcast, so the share button is that picker with its
// own button restyled. tapping it again while sharing offers to stop
struct BroadcastPickerButton: UIViewRepresentable {
    static let extensionBundleId = "com.sharkord.ios.broadcast"

    let isSharing: Bool

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 56, height: 56))

        picker.preferredExtension = Self.extensionBundleId
        picker.showsMicrophoneButton = false
        style(picker)

        return picker
    }

    func updateUIView(_ picker: RPSystemBroadcastPickerView, context: Context) {
        style(picker)
    }

    private func style(_ picker: RPSystemBroadcastPickerView) {
        guard let button = picker.subviews.compactMap({ $0 as? UIButton }).first else {
            return
        }

        // the picker sizes its button for its own small icon, it has to cover the whole circle
        button.frame = picker.bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let configuration = UIImage.SymbolConfiguration(textStyle: .title3)
        let image = UIImage(systemName: isSharing ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle", withConfiguration: configuration)?
            .withRenderingMode(.alwaysTemplate)

        button.setImage(image, for: .normal)
        button.imageView?.contentMode = .center
        button.tintColor = isSharing ? .black : UIColor(Theme.header)
        button.accessibilityLabel = isSharing ? "Stop Sharing Screen" : "Share Screen"
    }
}
