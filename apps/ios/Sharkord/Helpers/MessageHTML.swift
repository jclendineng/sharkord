import Foundation

struct InlineStyle: OptionSet, Hashable {
    let rawValue: Int

    static let bold = InlineStyle(rawValue: 1 << 0)
    static let italic = InlineStyle(rawValue: 1 << 1)
    static let code = InlineStyle(rawValue: 1 << 2)
}

enum MessageInline: Hashable {
    case text(String, InlineStyle)
    case link(String, URL, InlineStyle)
    case mention(userId: Int)
    case roleMention(roleId: Int)
    case channel(channelId: Int)
    case emoji(name: String, character: String?, imageSource: String?)
    case lineBreak
}

enum MessageBlock: Hashable {
    case paragraph([MessageInline])
    case code(String)
}

// parses the HTML that survives sanitizeMessageHtml on the server: p, br, strong, em, code,
// pre, a, the mention/channel/emoji spans and emoji images. anything else keeps its text
enum MessageHTML {
    private final class Box {
        let blocks: [MessageBlock]

        init(_ blocks: [MessageBlock]) {
            self.blocks = blocks
        }
    }

    private static let cache = NSCache<NSString, Box>()

    static func blocks(for html: String) -> [MessageBlock] {
        if let cached = cache.object(forKey: html as NSString) {
            return cached.blocks
        }

        var parser = Parser()
        let blocks = parser.parse(html)

        cache.setObject(Box(blocks), forKey: html as NSString)

        return blocks
    }

    // a short message made only of emoji renders large, like on the web client
    static func isEmojiOnly(_ blocks: [MessageBlock]) -> Bool {
        var count = 0

        for block in blocks {
            guard case .paragraph(let inlines) = block else {
                return false
            }

            for inline in inlines {
                switch inline {
                case .emoji:
                    count += 1
                case .text(let text, _) where text.trimmingCharacters(in: .whitespaces).isEmpty:
                    continue
                default:
                    return false
                }
            }
        }

        return count > 0 && count <= 10
    }
}

private struct Parser {
    private struct EmojiCapture {
        let name: String
        var character = ""
        var imageSource: String?
    }

    private var blocks: [MessageBlock] = []
    private var current: [MessageInline] = []
    private var boldDepth = 0
    private var italicDepth = 0
    private var codeDepth = 0
    private var links: [URL?] = []
    private var preText: String?
    // mention spans carry a display name we replace with live data, so their text is skipped
    private var skippedSpanDepth = 0
    private var emojiCapture: EmojiCapture?
    private var emojiSpanDepth = 0

    private var style: InlineStyle {
        var style: InlineStyle = []

        if boldDepth > 0 { style.insert(.bold) }
        if italicDepth > 0 { style.insert(.italic) }
        if codeDepth > 0 { style.insert(.code) }

        return style
    }

    mutating func parse(_ html: String) -> [MessageBlock] {
        let tag = #/<(\/?)([a-zA-Z][a-zA-Z0-9-]*)([^>]*?)\/?>/#
        var rest = html[...]

        while let match = rest.firstMatch(of: tag) {
            appendText(String(rest[rest.startIndex..<match.range.lowerBound]))

            let name = match.2.lowercased()

            if match.1.isEmpty {
                open(name, attributes: Self.attributes(String(match.3)))
            } else {
                close(name)
            }

            rest = rest[match.range.upperBound...]
        }

        appendText(String(rest))
        flushParagraph()

        return trimmed(blocks)
    }

    private mutating func open(_ name: String, attributes: [String: String]) {
        if skippedSpanDepth > 0 {
            if name == "span" { skippedSpanDepth += 1 }
            return
        }

        if emojiCapture != nil {
            if name == "span" {
                emojiSpanDepth += 1
            } else if name == "img" {
                emojiCapture?.imageSource = attributes["src"]
            }
            return
        }

        switch name {
        case "p":
            flushParagraph()
        case "br":
            if preText != nil {
                preText? += "\n"
            } else {
                current.append(.lineBreak)
            }
        case "strong", "b":
            boldDepth += 1
        case "em", "i":
            italicDepth += 1
        case "code":
            if preText == nil { codeDepth += 1 }
        case "pre":
            flushParagraph()
            preText = ""
        case "a":
            links.append(attributes["href"].flatMap(URL.init(string:)))
        case "img":
            let alt = attributes["alt"] ?? "emoji"

            current.append(.emoji(name: alt.trimmingCharacters(in: CharacterSet(charactersIn: ":")), character: nil, imageSource: attributes["src"]))
        case "span":
            openSpan(attributes)
        default:
            break
        }
    }

    private mutating func openSpan(_ attributes: [String: String]) {
        let type = attributes["data-type"]

        if type == "emoji" {
            emojiCapture = EmojiCapture(name: attributes["data-name"] ?? "")
            emojiSpanDepth = 1
            return
        }

        let inline: MessageInline?

        switch type {
        case "mention":
            inline = attributes["data-user-id"].flatMap(Int.init).map { .mention(userId: $0) }
        case "role-mention":
            inline = attributes["data-role-id"].flatMap(Int.init).map { .roleMention(roleId: $0) }
        case "channel-reference":
            inline = attributes["data-channel-id"].flatMap(Int.init).map { .channel(channelId: $0) }
        default:
            inline = nil
        }

        if let inline {
            current.append(inline)
            skippedSpanDepth = 1
        }
    }

    private mutating func close(_ name: String) {
        if skippedSpanDepth > 0 {
            if name == "span" { skippedSpanDepth -= 1 }
            return
        }

        if let capture = emojiCapture {
            if name == "span" {
                emojiSpanDepth -= 1
            }

            if emojiSpanDepth == 0 {
                let character = capture.character.trimmingCharacters(in: .whitespacesAndNewlines)

                current.append(.emoji(
                    name: capture.name,
                    character: character.isEmpty ? nil : character,
                    imageSource: capture.imageSource
                ))
                emojiCapture = nil
            }
            return
        }

        switch name {
        case "p":
            flushParagraph(keepEmpty: true)
        case "strong", "b":
            boldDepth = max(0, boldDepth - 1)
        case "em", "i":
            italicDepth = max(0, italicDepth - 1)
        case "code":
            if preText == nil { codeDepth = max(0, codeDepth - 1) }
        case "pre":
            if let preText {
                blocks.append(.code(preText.trimmingCharacters(in: .newlines)))
            }

            preText = nil
        case "a":
            _ = links.popLast()
        default:
            break
        }
    }

    private mutating func appendText(_ raw: String) {
        guard !raw.isEmpty, skippedSpanDepth == 0 else {
            return
        }

        let text = HTMLText.decodeEntities(raw)

        if emojiCapture != nil {
            emojiCapture?.character += text
        } else if preText != nil {
            preText? += text
        } else if let link = links.last, let url = link {
            current.append(.link(text, url, style))
        } else {
            current.append(.text(text, style))
        }
    }

    private mutating func flushParagraph(keepEmpty: Bool = false) {
        if !current.isEmpty || keepEmpty {
            blocks.append(.paragraph(current))
        }

        current = []
    }

    // tiptap leaves empty paragraphs around the content when the user hits enter at the ends
    private func trimmed(_ blocks: [MessageBlock]) -> [MessageBlock] {
        let isEmpty: (MessageBlock) -> Bool = { block in
            if case .paragraph(let inlines) = block {
                return inlines.isEmpty
            }

            return false
        }

        var result = blocks[...]

        while let first = result.first, isEmpty(first) { result = result.dropFirst() }
        while let last = result.last, isEmpty(last) { result = result.dropLast() }

        return Array(result)
    }

    private static func attributes(_ text: String) -> [String: String] {
        var attributes: [String: String] = [:]

        for match in text.matches(of: #/([a-zA-Z-]+)\s*=\s*"([^"]*)"/#) {
            attributes[match.1.lowercased()] = HTMLText.decodeEntities(String(match.2))
        }

        return attributes
    }
}
