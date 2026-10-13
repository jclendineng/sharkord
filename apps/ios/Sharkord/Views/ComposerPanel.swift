import SwiftUI

// what the attachment and expression panels share: the keyboard's place under the composer,
// a grabber that drags the panel up over the conversation, which dims behind it, or down and
// away, one color down behind the home indicator, and the fade to the chat color while the
// keyboard slides over it. the panel's own content and the bar floating over its bottom are
// handed in
struct ComposerPanel<Content: View, Bar: View>: View {
    // the one color the whole panel is, down behind the home indicator
    static var background: Color {
        Color(hex: "#232428")
    }

    let model: AttachPanelModel
    @ViewBuilder let content: Content
    @ViewBuilder let bar: Bar

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .opacity(model.expansion * 0.5)
                .frame(height: 2400)
                .allowsHitTesting(false)

            panel
        }
        .frame(height: AttachPanelModel.restingHeight, alignment: .bottom)
    }

    private var panel: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // the content fades out under the grabber instead of meeting an edge
            .overlay(alignment: .top) {
                grabber
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous))
            .frame(height: model.height)
            .overlay(alignment: .bottom) {
                bar
            }
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                    .fill(Self.background)
                    .ignoresSafeArea(edges: .bottom)
            }
            .overlay {
                Theme.chatBackground
                    .opacity(model.isCoveredByKeyboard ? 1 : 0)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            }
    }

    // the drag handle, over a fade the content scrolls up into
    private var grabber: some View {
        Capsule()
            .fill(Theme.muted.opacity(0.5))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .top)
            .background {
                LinearGradient(
                    stops: [
                        .init(color: Self.background, location: 0),
                        .init(color: Self.background, location: 0.45),
                        .init(color: Self.background.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .contentShape(.rect)
            .gesture(resize)
    }

    private var resize: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                model.drag(value.translation.height)
            }
            .onEnded { value in
                model.release(predicted: value.predictedEndTranslation.height)
            }
    }
}
