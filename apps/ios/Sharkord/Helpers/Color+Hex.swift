import SwiftUI

extension Color {
    // profile colors are stored as "#rrggbb"
    nonisolated init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0

        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Color {
    // the "#rrggbb" form users.update accepts
    var hexString: String {
        let components = PlatformColor(self).cgColor.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .defaultIntent,
            options: nil
        )?.components ?? [0, 0, 0]
        let channels = components.prefix(3).map { Int((min(max($0, 0), 1) * 255).rounded()) }

        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }
}
