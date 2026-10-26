import SwiftUI

// the composer's text box. a TextEditor rather than a TextField, which cannot show a picked
// mention tinted. a hidden copy of the text sizes it, so it grows with its text up to six
// lines like the field it replaced and scrolls past that
struct ComposerField: View {
    let placeholder: String
    @Binding var text: AttributedString
    @Binding var selection: AttributedTextSelection
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    // a phone's 22 point line and a mac's 16 point one each padded out to 44. the phone's 11 on a
    // mac left the box 38 high, and sat low in the row it is aligned to the bottom of
    #if os(macOS)
    static let verticalInset: CGFloat = 14
    #else
    static let verticalInset: CGFloat = 11
    #endif

    private var isEmpty: Bool {
        text.characters.isEmpty
    }

    var body: some View {
        // the space keeps a last empty line measured
        Text(isEmpty ? placeholder : String(text.characters) + " ")
            .foregroundStyle(Theme.muted)
            // the placeholder stays one line on a narrow phone, as a TextField's does
            .lineLimit(isEmpty ? 1...1 : 1...6)
            .opacity(isEmpty ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            // one line comes to 44 points, the buttons' height beside it, so its text is centered
            .padding(.vertical, Self.verticalInset)
            .overlay {
                TextEditor(text: $text, selection: $selection)
                    .attributedTextFormattingDefinition(ComposerFormatting())
                    .focused(isFocused)
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .textEditorStyle(.plain)
                    .editorInsets()
                    .onKeyPress(.return, phases: .down, action: submit)
            }
    }

    // return sends and shift return starts a new line, as on discord. only a hardware keyboard
    // reaches this, so a phone's own keyboard still starts a new line
    private func submit(_ press: KeyPress) -> KeyPress.Result {
        guard !press.modifiers.contains(.shift) else {
            return .ignored
        }

        onSubmit()

        return .handled
    }
}

private extension View {
    func editorInsets() -> some View {
        #if os(macOS)
        // a mac's text view has no inset of its own, so its text sat at the top of the box. moved
        // down onto the measured copy, it still runs to the bottom of the box
        padding(.top, ComposerField.verticalInset)
            .padding(.horizontal, -5)
        #else
        // the text view insets its text 8 points and its line sits 3 lower than a Text's,
        // measured on a phone, which together land it on the measured copy
        padding(.top, 0)
            .padding(.bottom, 6)
            .padding(.horizontal, -5)
        #endif
    }
}

private struct ComposerFormatting: AttributedTextFormattingDefinition {
    typealias Scope = AttributeScopes.ComposerAttributes

    var body: some AttributedTextFormattingDefinition<Scope> {
        MentionTint()
    }
}

// only a mention is tinted, the rest takes the field's own color
private struct MentionTint: AttributedTextValueConstraint {
    typealias Scope = AttributeScopes.ComposerAttributes
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute

    func constrain(_ container: inout Attributes) {
        container[AttributeKey.self] = container[ComposerMentionAttribute.self] == nil ? nil : Theme.mentionTint
    }
}
