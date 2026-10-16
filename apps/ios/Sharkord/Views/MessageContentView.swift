import SwiftUI

struct MessageContentView: View {
    let html: String

    @Environment(SessionStore.self) private var session

    private var emojiCache: EmojiImageCache { .shared }

    var body: some View {
        let blocks = MessageHTML.blocks(for: html)
        let isJumbo = MessageHTML.isEmojiOnly(blocks)

        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let inlines):
                    paragraph(inlines, isJumbo: isJumbo)
                        .font(isJumbo ? .system(size: 44) : .body)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let code):
                    CodeBlockView(code: code)
                case .listItem(let marker, let depth, let inlines):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker)
                            .foregroundStyle(Theme.muted)
                            .frame(minWidth: 14, alignment: .trailing)

                        paragraph(inlines, isJumbo: false)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(depth) * 16)
                case .quote(let inlines):
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.muted.opacity(0.5))
                            .frame(width: 4)

                        paragraph(inlines, isJumbo: false)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // a paragraph is one Text so it wraps as a whole, custom emoji go in as inline images
    private func paragraph(_ inlines: [MessageInline], isJumbo: Bool) -> Text {
        var result = Text("")

        for inline in inlines {
            let piece = text(for: inline, emojiSize: isJumbo ? 48 : 22)

            result = Text("\(result)\(piece)")
        }

        return result
    }

    private func text(for inline: MessageInline, emojiSize: CGFloat) -> Text {
        switch inline {
        case .text(let string, let style):
            return Text(attributed(string, style: style))
        case .link(let string, let url, let style):
            var attributed = attributed(string, style: style)
            attributed.link = url
            attributed.foregroundColor = Theme.link

            return Text(attributed)
        case .mention(let userId):
            return chip("@\(session.usersById[userId]?.name ?? "unknown-user")", color: Theme.mentionText, background: Theme.mentionBackground)
        case .roleMention(let roleId):
            let role = session.rolesById[roleId]
            let color = role.map { Color(hex: $0.color) } ?? Theme.mentionText

            return chip("@\(role?.name ?? "deleted-role")", color: color, background: color.opacity(0.15))
        case .channel(let channelId):
            return chip("#\(session.channel(channelId)?.name ?? "unknown")", color: Theme.mentionText, background: Theme.mentionBackground)
        case .emoji(let name, let character, let imageSource):
            return emoji(name: name, character: character, imageSource: imageSource, size: emojiSize)
        case .lineBreak:
            return Text("\n")
        }
    }

    private func emoji(name: String, character: String?, imageSource: String?, size: CGFloat) -> Text {
        if let character {
            return Text(character)
        }

        if let url = resolve(imageSource), let image = emojiCache.image(for: url, pointSize: size) {
            return Text("\(Image(uiImage: image))").baselineOffset(-size * 0.2)
        }

        return Text(":\(name):")
    }

    // custom emoji are stored as a server relative /public path
    private func resolve(_ source: String?) -> URL? {
        guard let source else {
            return nil
        }

        // appended rather than resolved, which would drop a server reached under a subpath
        if source.hasPrefix("/"), let address = session.address {
            return URL(string: address.baseURL.absoluteString + source)
        }

        return URL(string: source)
    }

    private func attributed(_ string: String, style: InlineStyle) -> AttributedString {
        var attributed = AttributedString(string)
        var intent: InlinePresentationIntent = []

        if style.contains(.bold) { intent.insert(.stronglyEmphasized) }
        if style.contains(.italic) { intent.insert(.emphasized) }

        if style.contains(.code) {
            attributed.font = .system(.callout, design: .monospaced)
            attributed.backgroundColor = Theme.deepBackground
        }

        attributed.inlinePresentationIntent = intent

        if style.contains(.strikethrough) { attributed.strikethroughStyle = .single }
        if style.contains(.underline) { attributed.underlineStyle = .single }

        return attributed
    }

    private func chip(_ string: String, color: Color, background: Color) -> Text {
        var attributed = AttributedString(string)
        attributed.foregroundColor = color
        attributed.backgroundColor = background
        attributed.inlinePresentationIntent = .stronglyEmphasized

        return Text(attributed)
    }
}

private struct CodeBlockView: View {
    let code: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Theme.text)
                .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.listBackground, in: .rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.deepBackground)
        }
    }
}
