import SwiftUI

// discord's user settings: account things for the selected server, then this device's own
struct SettingsSheet: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Account Settings") {
                    NavigationLink {
                        AccountSettingsScreen()
                    } label: {
                        SettingsRow(title: "Account", systemImage: "person.crop.circle.fill")
                    }

                    NavigationLink {
                        DevicesScreen()
                    } label: {
                        SettingsRow(title: "Devices", systemImage: "laptopcomputer.and.iphone")
                    }

                    NavigationLink {
                        SignInDeviceScreen()
                    } label: {
                        SettingsRow(title: "Sign In Another Device", systemImage: "qrcode")
                    }
                }

                Section("App Settings") {
                    NavigationLink {
                        VoiceVideoSettingsScreen()
                    } label: {
                        SettingsRow(title: "Voice & Video", systemImage: "mic.fill")
                    }

                    NavigationLink {
                        NotificationSettingsScreen()
                    } label: {
                        SettingsRow(title: "Notifications", systemImage: "bell.fill")
                    }
                }

                Section("Support") {
                    NavigationLink {
                        AboutScreen()
                    } label: {
                        SettingsRow(title: "About", systemImage: "info.circle.fill", value: AppInfo.version)
                    }
                }

                Section {
                    Button(role: .destructive, action: logOut) {
                        SettingsRow(title: "Log Out", systemImage: "rectangle.portrait.and.arrow.right", tint: Theme.red)
                    }
                } footer: {
                    Text("Logs out of \(session.displayName) on this device.")
                }
            }
            .settingsListStyle()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: close)
                }
            }
        }
        // a page on ipad, as wide as discord's settings, rather than a narrow card in the middle
        .presentationSizing(.page)
        .presentationBackground(Theme.deepBackground)
    }

    private func close() {
        dismiss()
    }

    private func logOut() {
        dismiss()
        servers.remove(session)
    }
}

struct SettingsRow: View {
    let title: String
    let systemImage: String
    var value: String?
    var tint = Theme.header

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 28)

            Text(title)
                .foregroundStyle(tint)

            Spacer()

            if let value {
                Text(value)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, UIDevice.current.userInterfaceIdiom == .pad ? 8 : 4)
    }
}

extension View {
    func settingsListStyle() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.deepBackground)
            .listHoverHighlight()
            .listRowBackground(Theme.listBackground)
            .tint(Theme.blurple)
    }

    // a list styled some other way still lights the row under a mac pointer
    func listHoverHighlight() -> some View {
        background {
            if ProcessInfo.processInfo.isiOSAppOnMac {
                ListHoverHighlighter()
            }
        }
    }
}

// a mac pointer over a settings row lights it the way channels and messages do. a list's rows are
// collection view cells swiftui makes, so this finds the list's collection view and tints the
// cell under the pointer through its background configuration, which keeps a section's rounded
// corners. one place for every settings screen rather than a modifier on each row
private struct ListHoverHighlighter: UIViewRepresentable {
    func makeUIView(context: Context) -> ListHoverProbe {
        ListHoverProbe()
    }

    func updateUIView(_ uiView: ListHoverProbe, context: Context) {}
}

final class ListHoverProbe: UIView {
    private static let hoverColor = UIColor.white.withAlphaComponent(0.06)

    private weak var collectionView: UICollectionView?
    private weak var hoveredCell: UICollectionViewCell?
    private var restoredColor: UIColor?

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard window != nil else {
            return
        }

        // the list is laid out a moment after its background, so it is looked for then
        DispatchQueue.main.async { [weak self] in
            self?.attach()
        }
    }

    private func attach() {
        guard collectionView == nil, let list = findCollectionView() else {
            return
        }

        collectionView = list
        list.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered)))
    }

    // the background sits beside the list rather than in it, so the nearest collection view
    // under a shared ancestor that covers this probe is the list
    private func findCollectionView() -> UICollectionView? {
        var ancestor = superview

        while let current = ancestor {
            if let list = Self.firstCollectionView(in: current, covering: convert(bounds, to: current)) {
                return list
            }

            ancestor = current.superview
        }

        return nil
    }

    private static func firstCollectionView(in view: UIView, covering frame: CGRect) -> UICollectionView? {
        if let list = view as? UICollectionView, list.convert(list.bounds, to: view).intersects(frame) || list.superview == nil {
            return list
        }

        for subview in view.subviews {
            if let list = firstCollectionView(in: subview, covering: subview.convert(frame, from: view)) {
                return list
            }
        }

        return nil
    }

    @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
        guard let list = collectionView else {
            return
        }

        switch recognizer.state {
        case .began, .changed:
            let cell = list.indexPathForItem(at: recognizer.location(in: list)).flatMap(list.cellForItem(at:))

            if cell !== hoveredCell {
                highlight(cell)
            }
        default:
            highlight(nil)
        }
    }

    private func highlight(_ cell: UICollectionViewCell?) {
        if let previous = hoveredCell {
            previous.backgroundConfiguration?.backgroundColor = restoredColor
        }

        hoveredCell = cell
        restoredColor = cell?.backgroundConfiguration?.backgroundColor

        guard let cell, let color = restoredColor else {
            return
        }

        cell.backgroundConfiguration?.backgroundColor = color.blended(with: Self.hoverColor)
    }
}

private extension UIColor {
    // the hover tint laid over the row's own colour, as a translucent fill over it would look
    func blended(with overlay: UIColor) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        var overlayRed: CGFloat = 0, overlayGreen: CGFloat = 0, overlayBlue: CGFloat = 0, overlayAlpha: CGFloat = 0

        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        overlay.getRed(&overlayRed, green: &overlayGreen, blue: &overlayBlue, alpha: &overlayAlpha)

        return UIColor(
            red: red + (overlayRed - red) * overlayAlpha,
            green: green + (overlayGreen - green) * overlayAlpha,
            blue: blue + (overlayBlue - blue) * overlayAlpha,
            alpha: alpha
        )
    }
}
