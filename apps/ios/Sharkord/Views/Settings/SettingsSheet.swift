import SwiftUI

// discord's user settings: account things for the selected server, then this device's own. a
// list of pages on a phone or ipad, the whole window with the pages down the side on a mac
struct SettingsSheet: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var selection: UserSettingsPage? = .account
    @State private var query = ""

    // discord's sidebar search, narrowing the pages by name
    private var sections: [(title: String, pages: [UserSettingsPage])] {
        let text = query.trimmingCharacters(in: .whitespaces)

        return UserSettingsPage.sections.compactMap { section in
            let pages = section.pages.filter { text.isEmpty || $0.title.localizedCaseInsensitiveContains(text) }

            return pages.isEmpty ? nil : (section.title, pages)
        }
    }

    var body: some View {
        if Platform.isMac {
            splitView
        } else {
            stackView
        }
    }

    private var stackView: some View {
        NavigationStack {
            SettingsForm {
                ForEach(UserSettingsPage.sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.pages, id: \.self) { page in
                            NavigationLink {
                                page.screen
                            } label: {
                                SettingsRow(title: page.title, systemImage: page.systemImage, value: page.value)
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive, action: logOut) {
                        SettingsRow(title: "Log Out", systemImage: "rectangle.portrait.and.arrow.right", tint: Theme.red)
                    }
                } footer: {
                    Text("Logs out of \(session.displayName) on this device.")
                        .wrappingFooter()
                }
            }
            .settingsListStyle()
            .navigationTitle("Settings")
            .inlineNavigationTitle()
            .toolbar {
                ActionToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: close)
                }
            }
        }
        // a page on ipad, as wide as discord's settings, rather than a narrow card in the middle
        .presentationSizing(.page)
        .presentationBackground(Theme.deepBackground)
    }

    private var splitView: some View {
        SettingsWindow {
            List {
                ForEach(sections, id: \.title) { section in
                    Section {
                        ForEach(section.pages, id: \.self) { page in
                            SettingsSidebarRow(title: page.title, systemImage: page.systemImage, isSelected: selection == page) {
                                selection = page
                            }
                        }
                    } header: {
                        SettingsSidebarHeader(title: section.title)
                    }
                    .listSectionSeparator(.hidden)
                }

                Section {
                    SettingsSidebarRow(
                        title: "Log Out",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        isSelected: false,
                        tint: Theme.red,
                        action: logOut
                    )
                }
                .listSectionSeparator(.hidden)
            }
            .settingsSidebarStyle()
            // the app's own field rather than the system's, which kept escape for itself. not
            // focused on opening: a mac put its texted code autofill over the first rows
            .pageSearchable(text: $query, prompt: "Search")
        } detail: {
            // a stack of its own per page, so a page's own links push inside it and picking
            // another page starts over
            NavigationStack {
                if let selection {
                    selection.screen
                        .settingsPage(onClose: close)
                }
            }
            .id(selection)
        }
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
                // a fixed height too, or a taller symbol made its row taller than the rest
                .frame(width: 28, height: 24)

            Text(title)
                .foregroundStyle(tint)

            Spacer()

            if let value {
                Text(value)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, Platform.isPad ? 8 : 4)
    }
}

extension View {
    func settingsListStyle() -> some View {
        #if os(macOS)
        let grouped = listStyle(.inset)
        #else
        let grouped = listStyle(.insetGrouped)
        #endif

        let styled = grouped
            .scrollContentBackground(.hidden)
            .background(Theme.deepBackground)
            .listHoverHighlight()
            .listRowBackground(Theme.listBackground)

        #if os(macOS)
        // a mac's settings form tints its own rows. a tint on the whole page reached a pushed
        // page's back button, a blurple disc in a neutral bar
        return styled
        #else
        return styled.tint(Theme.blurple)
        #endif
    }

    // a list styled some other way still lights the row under a mac pointer
    func listHoverHighlight() -> some View {
        background {
            if Platform.isMac {
                ListHoverHighlighter()
            }
        }
    }
}

#if os(macOS)
// the same on the native mac, where appkit draws a list as a table view. a row's background there
// is drawn by swiftui inside the row, out of reach, so a translucent rounded fill is laid over
// the hovered row instead, the way a mac sidebar lights one
private struct ListHoverHighlighter: NSViewRepresentable {
    func makeNSView(context: Context) -> ListHoverProbe {
        ListHoverProbe()
    }

    func updateNSView(_ nsView: ListHoverProbe, context: Context) {}
}

final class ListHoverProbe: NSView {
    private weak var tableView: NSTableView?
    private let fill = HoverFill()
    private var trackingArea: NSTrackingArea?
    private var scrollObserver: NSObjectProtocol?

    isolated deinit {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }

        fill.removeFromSuperview()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard window != nil else {
            return
        }

        // the list is laid out a moment after its background, so it is looked for then
        DispatchQueue.main.async { [weak self] in
            self?.attach()
        }
    }

    private func attach() {
        guard tableView == nil, let table = findTableView() else {
            return
        }

        tableView = table
        fill.isHidden = true
        table.addSubview(fill, positioned: .above, relativeTo: nil)

        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )

        table.addTrackingArea(area)
        trackingArea = area

        // a scroll moves the rows under a pointer that stays still
        if let clipView = table.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.update()
                }
            }
        }
    }

    // the background sits beside the list rather than in it, so the nearest table view under a
    // shared ancestor that covers this probe is the list
    private func findTableView() -> NSTableView? {
        var ancestor = superview

        while let current = ancestor {
            if let table = Self.firstTableView(in: current, covering: convert(bounds, to: current)) {
                return table
            }

            ancestor = current.superview
        }

        return nil
    }

    private static func firstTableView(in view: NSView, covering frame: NSRect) -> NSTableView? {
        if let table = view as? NSTableView, let scrollView = table.enclosingScrollView, scrollView.convert(scrollView.bounds, to: view).intersects(frame) {
            return table
        }

        for subview in view.subviews {
            if let table = firstTableView(in: subview, covering: subview.convert(frame, from: view)) {
                return table
            }
        }

        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        update()
    }

    override func mouseEntered(with event: NSEvent) {
        update()
    }

    override func mouseExited(with event: NSEvent) {
        fill.isHidden = true
    }

    private func update() {
        guard let table = tableView, let window = table.window else {
            return
        }

        let point = table.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let row = table.row(at: point)

        guard
            row >= 0,
            table.visibleRect.contains(point),
            let rowView = table.rowView(atRow: row, makeIfNecessary: false),
            !rowView.isGroupRowStyle
        else {
            fill.isHidden = true
            return
        }

        // the row's content, which an inset list draws narrower than the row itself
        let content = rowView.subviews.first.map { rowView.convert($0.frame, to: table) } ?? table.rect(ofRow: row)

        fill.frame = content
        fill.isHidden = false
    }
}

// never takes a click, it only tints what is under it
private final class HoverFill: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.cornerRadius = 6
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
#endif

#if os(iOS)
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
#endif

enum UserSettingsPage: Hashable {
    case account
    case devices
    case signInDevice
    case voiceVideo
    case notifications
    case about

    static let sections: [(title: String, pages: [UserSettingsPage])] = [
        ("Account Settings", [.account, .devices, .signInDevice]),
        ("App Settings", [.voiceVideo, .notifications]),
        ("Support", [.about])
    ]

    var title: String {
        switch self {
        case .account:
            "Account"
        case .devices:
            "Devices"
        case .signInDevice:
            "Sign In Another Device"
        case .voiceVideo:
            "Voice & Video"
        case .notifications:
            "Notifications"
        case .about:
            "About"
        }
    }

    var systemImage: String {
        switch self {
        case .account:
            "person.crop.circle.fill"
        case .devices:
            "laptopcomputer.and.iphone"
        case .signInDevice:
            "qrcode"
        case .voiceVideo:
            "mic.fill"
        case .notifications:
            "bell.fill"
        case .about:
            "info.circle.fill"
        }
    }

    var value: String? {
        self == .about ? AppInfo.version : nil
    }

    @ViewBuilder
    var screen: some View {
        switch self {
        case .account:
            AccountSettingsScreen()
        case .devices:
            DevicesScreen()
        case .signInDevice:
            SignInDeviceScreen()
        case .voiceVideo:
            VoiceVideoSettingsScreen()
        case .notifications:
            NotificationSettingsScreen()
        case .about:
            AboutScreen()
        }
    }
}
