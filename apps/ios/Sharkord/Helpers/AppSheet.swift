import SwiftUI

extension View {
    // on a mac a trackpad scroll past a sheet's top drags it to close, fading the whole sheet
    // out, so the drag is turned off there. a sheet with no close of its own gets an x like the
    // toolbar's in a row across its top, everywhere: a mac has no other way out, and a phone's
    // swipe is not obvious to everyone
    func appSheet(addsClose: Bool = false, fitsContent: Bool = false) -> some View {
        modifier(AppSheet(addsClose: addsClose, fitsContent: fitsContent))
    }

    // a sheet given heights pins itself to the bottom of a mac window and runs off it, so there
    // it is left as the usual form centred in the window
    func sheetDetents(_ detents: Set<PresentationDetent>) -> some View {
        modifier(SheetDetents(detents: detents))
    }

    // a page pushed over the chat goes back on escape on a mac, the way its sheets close
    func escapeGoesBack() -> some View {
        modifier(EscapeGoesBack())
    }

    // a narrow mac window counts as compact and turns a popover into a sheet rising from the
    // bottom. discord's hang off their button at any width, a phone still gets the sheet
    func macPopover() -> some View {
        presentationCompactAdaptation(Platform.isMac ? .popover : .automatic)
            .phoneControlStyle()
            .phoneButtons()
    }
}

private struct EscapeGoesBack: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .background {
                if Platform.isMac {
                    Button("Back", action: goBack)
                        .keyboardShortcut(.cancelAction)
                        .hidden()
                }
            }
    }

    private func goBack() {
        dismiss()
    }
}

private struct SheetDetents: ViewModifier {
    let detents: Set<PresentationDetent>

    func body(content: Content) -> some View {
        if Platform.isMac {
            content
        } else {
            content.presentationDetents(detents)
        }
    }
}

private struct AppSheet: ViewModifier {
    let addsClose: Bool
    let fitsContent: Bool

    @Environment(\.dismiss) private var dismiss

    private let isOnMac = Platform.isMac

    func body(content: Content) -> some View {
        content
            // left alone elsewhere: an outer false here would override a sheet that turns the
            // swipe off for itself, the voice channel's open one does
            .modifier(MacDismissLock(isOnMac: isOnMac))
            .macSheetMinimumSize(fitsContent: fitsContent)
            .phoneControlStyle()
            .phoneButtons()
            // escape closes it, as it does a mac sheet
            .background {
                if isOnMac {
                    Button("Close", action: close)
                        .keyboardShortcut(.cancelAction)
                        .hidden()
                }
            }
            #if os(macOS)
            .modifier(MacDoneBar(isShown: addsClose, close: close))
            #else
            .safeAreaInset(edge: .top, spacing: 0) {
                if addsClose {
                    HStack {
                        SheetCloseButton(action: close)

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    // clear of the content below, which often starts with a background of its own
                    .padding(.bottom, 8)
                }
            }
            #endif
    }

    private func close() {
        dismiss()
    }
}

#if os(macOS)
// a mac sheet ends in a done button at its bottom right rather than an x over its top. laid out
// under the page, as the sheets with a bar of their own are: as a safe area inset a scrolling
// page ran on beneath it, the button floating over its rows
private struct MacDoneBar: ViewModifier {
    let isShown: Bool
    let close: () -> Void

    func body(content: Content) -> some View {
        if isShown {
            VStack(spacing: 0) {
                content

                Theme.divider.frame(height: 1)

                HStack {
                    Spacer()

                    // filled, as the done of a sheet with a bar of its own is
                    Button("Done", action: close)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.blurple)
                }
                .padding(20)
            }
        } else {
            content
        }
    }
}
#endif

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
        // plain glass on a mac and an ipad: the interactive kind takes a pointer's press for its
        // own animation, and the button only saw an occasional click, so the x needed several
        .glassEffect(Platform.isMac || Platform.isPad ? .regular : .regular.interactive(), in: .circle)
        .contentShape(.circle)
        .accessibilityLabel("Close")
    }
}
