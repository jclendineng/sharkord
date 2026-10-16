import SwiftUI

// an action sheet exactly as tall as its rows, the last one included, with nothing to scroll
// or drag to. a fixed half height cut the bottom row off on an ipad. put on the sheet's content,
// inside its scroll view, so the height measured is the rows' own
private struct FittedSheet: ViewModifier {
    @Environment(\.isPointerMenu) private var isPointerMenu

    @State private var height: CGFloat?

    func body(content: Content) -> some View {
        content
            .padding(.bottom, isPointerMenu ? 6 : 16)
            .onGeometryChange(for: CGFloat.self, of: \.size.height, action: fit)
            .sheetDetents([height.map { .height($0) } ?? .medium])
    }

    private func fit(_ measured: CGFloat) {
        guard height == nil else {
            return
        }

        // the grabber sits above the content
        height = measured + 12
    }
}

extension View {
    func fittedSheet() -> some View {
        modifier(FittedSheet())
    }
}
