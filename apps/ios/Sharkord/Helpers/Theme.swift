import SwiftUI

// discord's dark palette
enum Theme {
    static let chatBackground = Color(hex: "#313338")
    static let listBackground = Color(hex: "#2B2D31")
    static let deepBackground = Color(hex: "#1E1F22")
    static let inputBackground = Color(hex: "#383A40")
    static let hover = Color(hex: "#404249")
    static let divider = Color(hex: "#3F4147")

    static let text = Color(hex: "#DBDEE1")
    static let header = Color(hex: "#F2F3F5")
    static let muted = Color(hex: "#949BA4")

    static let blurple = Color(hex: "#5865F2")
    static let link = Color(hex: "#00A8FC")
    static let mentionText = Color(hex: "#C9CDFB")
    static let mentionBackground = Color(hex: "#5865F2").opacity(0.3)
    static let red = Color(hex: "#F23F43")
    static let green = Color(hex: "#23A55A")
    static let yellow = Color(hex: "#F0B232")

    static func statusColor(_ status: UserStatus?) -> Color {
        switch status {
        case .online:
            green
        case .idle:
            yellow
        case .offline, nil:
            muted
        }
    }
}

enum MessageDate {
    // "Today at 3:41 PM", "Yesterday at 3:41 PM" or "10/12/26, 3:41 PM"
    static func timestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)

        if calendar.isDateInToday(date) {
            return "Today at \(time)"
        }

        if calendar.isDateInYesterday(date) {
            return "Yesterday at \(time)"
        }

        return date.formatted(date: .numeric, time: .shortened)
    }

    static func day(_ date: Date) -> String {
        date.formatted(date: .long, time: .omitted)
    }
}
