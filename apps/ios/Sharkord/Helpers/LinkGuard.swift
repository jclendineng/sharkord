import SwiftUI
import UIKit

// discord's "leaving" warning before a link opens outside the app: where it goes, the domain in
// bold, and a box to trust that domain from then on. links to the servers you are signed in to,
// and domains you trusted, open straight away
enum TrustedLinkDomains {
    private static let key = "trustedLinkDomains"

    static func contains(_ host: String) -> Bool {
        let domains = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])

        return domains.contains(host.lowercased())
    }

    static func add(_ host: String) {
        var domains = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])

        domains.insert(host.lowercased())
        UserDefaults.standard.set(Array(domains), forKey: key)
    }
}

extension View {
    // every link opened through swiftui below this, message links and buttons alike
    func guardsLeavingLinks(servers: ServerListStore) -> some View {
        environment(\.openURL, OpenURLAction { url in
            guard
                let scheme = url.scheme?.lowercased(),
                scheme == "http" || scheme == "https",
                let host = url.host()?.lowercased()
            else {
                return .systemAction
            }

            let serverHosts = servers.sessions.compactMap { $0.address?.baseURL.host()?.lowercased() }

            if serverHosts.contains(host) || TrustedLinkDomains.contains(host) {
                return .systemAction
            }

            LeavingWarning.present(for: url, host: host)

            return .handled
        })
    }
}

// shown over whatever is on screen, sheets included, which swiftui's own presentation from the
// root could not do while a sheet is up
@MainActor
private enum LeavingWarning {
    static func present(for url: URL, host: String) {
        guard let top = UIApplication.shared.topViewController else {
            return
        }

        var controller: UIViewController?

        let card = LeavingCard(url: url, host: host) { visit, trust in
            if trust {
                TrustedLinkDomains.add(host)
            }

            controller?.dismiss(animated: true) {
                if visit {
                    UIApplication.shared.open(url)
                }
            }
        }

        let hosting = UIHostingController(rootView: card)

        hosting.view.backgroundColor = .clear
        hosting.modalPresentationStyle = .overFullScreen
        hosting.modalTransitionStyle = .crossDissolve
        controller = hosting

        top.present(hosting, animated: true)
    }
}

private struct LeavingCard: View {
    let url: URL
    let host: String
    let onFinish: (_ visit: Bool, _ trust: Bool) -> Void

    @State private var trusts = false

    // the address with its domain in bold, as discord shows it
    private var address: AttributedString {
        var text = AttributedString(url.absoluteString)

        text.foregroundColor = Theme.muted

        if let range = text.range(of: url.host() ?? host) {
            text[range].foregroundColor = Theme.header
            text[range].font = .body.weight(.semibold)
        }

        return text
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: goBack)

            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("Leaving Sharkord")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.header)

                    Text("This link is taking you to the following website")
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                }

                Text(address)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                Toggle(isOn: $trusts) {
                    Text("Trust **\(host)** links from now on")
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                }
                .tint(Theme.blurple)

                VStack(spacing: 10) {
                    Button(action: visit) {
                        Text("Visit Site")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.blurple, in: .rect(cornerRadius: 10))
                    }

                    Button(action: goBack) {
                        Text("Go Back")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.header)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.listBackground, in: .rect(cornerRadius: 10))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .background(Theme.deepBackground, in: .rect(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 1)
            }
            .padding(.horizontal, 20)
        }
    }

    private func visit() {
        onFinish(true, trusts)
    }

    private func goBack() {
        onFinish(false, false)
    }
}
