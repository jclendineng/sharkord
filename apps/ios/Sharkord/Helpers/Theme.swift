import SwiftUI

// one colour per appearance, each with a stronger one for Increase Contrast. the dark set started
// from discord's palette, with muted, link and red text lifted to 4.5:1 on every surface they sit on
enum Theme {
    static let chatBackground = dynamic(light: "#FFFFFF", dark: "#313338")
    static let listBackground = dynamic(light: "#F2F3F5", dark: "#2B2D31")
    static let deepBackground = dynamic(light: "#E3E5E8", dark: "#1E1F22")
    static let inputBackground = dynamic(light: "#EBEDEF", dark: "#383A40")
    static let hover = dynamic(light: "#E3E5E8", dark: "#404249", darkContrast: "#3A3C42")
    static let divider = dynamic(light: "#D4D6DA", dark: "#3F4147", lightContrast: "#9A9CA3", darkContrast: "#6D6F78")

    // the home screen's darker set: the server rail, the channel panel a shade above it, its
    // controls and its selected row
    static let railBackground = dynamic(light: "#F7F8FA", dark: "#121214")
    static let panelBackground = dynamic(light: "#F2F3F5", dark: "#1A1A1E")
    static let panelControl = dynamic(light: "#E3E5E8", dark: "#242429")
    static let panelSelected = dynamic(light: "#D7D9DE", dark: "#2C2D32")
    static let panelEdge = dynamic(light: "#0000001A", dark: "#FFFFFF0F", lightContrast: "#0000004D", darkContrast: "#FFFFFF40")
    // the composer, call bar and pop up cards, raised a step off the page behind them
    static let raisedBackground = dynamic(light: "#FFFFFF", dark: "#232428")
    static let floatingBackground = dynamic(light: "#FFFFFF", dark: "#2B2C31")
    // a grouped form's rows, white on the light page as a system form's are
    static let groupedRowBackground = dynamic(light: "#FFFFFF", dark: "#2B2D31")
    // a translucent wash for hovered and pressed rows, over any background
    static let hoverOverlay = dynamic(light: "#0000000D", dark: "#FFFFFF14")

    static let text = dynamic(light: "#313338", dark: "#DBDEE1", lightContrast: "#000000", darkContrast: "#FFFFFF")
    static let header = dynamic(light: "#060607", dark: "#F2F3F5", lightContrast: "#000000", darkContrast: "#FFFFFF")
    static let muted = dynamic(light: "#5C5E66", dark: "#ABB0B8", lightContrast: "#3C3E45", darkContrast: "#C9CDD3")

    // blurple fills primary actions and selection. text in the accent colour, links and thread
    // replies, uses accentText, which keeps 4.5:1 where blurple itself only reaches 2.7:1
    static let blurple = Color(hex: "#5865F2")
    static let accentText = dynamic(light: "#4752C4", dark: "#A8AEFA", lightContrast: "#2F38A0", darkContrast: "#C0C5FF")
    static let link = dynamic(light: "#005FCC", dark: "#38B6FF", lightContrast: "#0047A3", darkContrast: "#7CCBFF")
    static let mentionText = dynamic(light: "#3C45A5", dark: "#C9CDFB", lightContrast: "#2F38A0", darkContrast: "#E0E3FF")
    // a mention as Messages shows one, the name alone in the accent colour
    // nonisolated for the composer field's formatting, which runs off the main actor
    nonisolated static let mentionTint = dynamic(light: "#4752C4", dark: "#A8AEFA", lightContrast: "#2F38A0", darkContrast: "#C0C5FF")
    // red fills destructive buttons under white text (4.6:1), redText is red as text
    static let red = Color(hex: "#DA373C")
    static let redText = dynamic(light: "#C4272C", dark: "#FF8A8D", lightContrast: "#9E1A1F", darkContrast: "#FFA3A5")
    static let green = Color(hex: "#248046")
    static let greenText = dynamic(light: "#1A7F40", dark: "#3BC170", lightContrast: "#12602F", darkContrast: "#6FD896")
    static let yellow = Color(hex: "#F0B232")

    // "#rrggbb" or "#rrggbbaa", resolved by the system as the appearance or contrast changes
    nonisolated private static func dynamic(light: String, dark: String, lightContrast: String? = nil, darkContrast: String? = nil) -> Color {
        #if os(macOS)
        let color = NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let isHighContrast = match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua

            return platformColor(pick(light: light, dark: dark, lightContrast: lightContrast, darkContrast: darkContrast, isDark: isDark, isHighContrast: isHighContrast))
        }

        return Color(nsColor: color)
        #else
        let color = UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let isHighContrast = traits.accessibilityContrast == .high

            return platformColor(pick(light: light, dark: dark, lightContrast: lightContrast, darkContrast: darkContrast, isDark: isDark, isHighContrast: isHighContrast))
        }

        return Color(uiColor: color)
        #endif
    }

    nonisolated private static func pick(light: String, dark: String, lightContrast: String?, darkContrast: String?, isDark: Bool, isHighContrast: Bool) -> String {
        if isDark {
            return isHighContrast ? darkContrast ?? dark : dark
        }

        return isHighContrast ? lightContrast ?? light : light
    }

    nonisolated private static func platformColor(_ hex: String) -> PlatformColor {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(digits, radix: 16) ?? 0
        let hasAlpha = digits.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        let alpha = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255

        #if os(macOS)
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        #else
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }

    static func statusColor(_ status: UserStatus?) -> Color {
        switch status {
        case .online:
            green
        case .idle:
            yellow
        case .dnd:
            red
        case .offline, nil:
            muted
        }
    }
}

enum MessageDate {
    // "Today at 3:41 PM", "Yesterday at 3:41 PM" or "10/12/26, 3:41 PM", in the reader's own
    // language and date order
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true

        return formatter
    }()

    static func timestamp(_ date: Date) -> String {
        formatter.string(from: date)
    }

    static func day(_ date: Date) -> String {
        date.formatted(date: .long, time: .omitted)
    }
}

extension SessionStore {
    // a name in its role's colour, or the header colour of the current appearance without one
    func nameColor(for user: PublicUser?) -> Color {
        guard let hex = roleColor(for: user) else {
            return Theme.header
        }

        return Color(hex: hex)
    }
}
