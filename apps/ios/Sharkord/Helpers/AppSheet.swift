import SwiftUI

extension View {
    // on a mac a trackpad scroll past a sheet's top drags it to close, fading the whole sheet
    // out, so the drag is turned off there. a sheet with no close of its own gets an x like the
    // toolbar's in a row across its top, everywhere: a mac has no other way out, and a phone's
    // swipe is not obvious to everyone
    func appSheet(addsClose: Bool = false) -> some View {
        modifier(AppSheet(addsClose: addsClose))
    }

    // a sheet given heights pins itself to the bottom of a mac window and runs off it, so there
    // it is left as the usual form centred in the window
    func sheetDetents(_ detents: Set<PresentationDetent>) -> some View {
        modifier(SheetDetents(detents: detents))
    }

    // a narrow mac window counts as compact and turns a popover into a sheet rising from the
    // bottom. discord's hang off their button at any width, a phone still gets the sheet
    func macPopover() -> some View {
        presentationCompactAdaptation(ProcessInfo.processInfo.isiOSAppOnMac ? .popover : .automatic)
    }
}

private struct SheetDetents: ViewModifier {
    let detents: Set<PresentationDetent>

    func body(content: Content) -> some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            content
        } else {
            content.presentationDetents(detents)
        }
    }
}

private struct AppSheet: ViewModifier {
    let addsClose: Bool

    @Environment(\.dismiss) private var dismiss

    private let isOnMac = ProcessInfo.processInfo.isiOSAppOnMac

    func body(content: Content) -> some View {
        content
            // left alone elsewhere: an outer false here would override a sheet that turns the
            // swipe off for itself, the voice channel's open one does
            .modifier(MacDismissLock(isOnMac: isOnMac))
            .safeAreaInset(edge: .top, spacing: 0) {
                if addsClose {
                    HStack {
                        SheetCloseButton(action: close)

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                }
            }
    }

    private func close() {
        dismiss()
    }
}

private struct MacDismissLock: ViewModifier {
    let isOnMac: Bool

    func body(content: Content) -> some View {
        if isOnMac {
            // no grabber either: nothing drags a sheet on a mac, and the strip it owns at the top
            // took the clicks meant for the x beside it, which needed several to close
            content
                .interactiveDismissDisabled()
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
    }
}

// the toolbar's own close, a sheet like new message has: glass with the x in the tint colour
private struct SheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        // plain glass on a mac: the interactive kind takes the press for its own animation there,
        // and the button only saw an occasional click, so the x needed several to close
        .glassEffect(ProcessInfo.processInfo.isiOSAppOnMac ? .regular : .regular.interactive(), in: .circle)
        .contentShape(.circle)
        .accessibilityLabel("Close")
    }
}
