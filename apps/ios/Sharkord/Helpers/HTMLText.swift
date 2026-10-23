import Foundation

// message content is the HTML the web client's tiptap editor produces. this is a deliberately
// small conversion, rich rendering (mentions, custom emoji, code blocks) comes later
enum HTMLText {
    static func plainText(from html: String) -> String {
        var text = html

        let replacements: [(String, String)] = [
            ("<br\\s*/?>", "\n"),
            ("</p>\\s*<p[^>]*>", "\n"),
            ("<li[^>]*>", "• "),
            ("</li>", "\n"),
            ("<[^>]+>", "")
        ]

        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return decodeEntities(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // text from the composer with a placeholder where each picked mention sits, made into
    // html and then each placeholder into its mention's span
    static func messageHTML(fromMarkdown text: String, mentions: [ComposerMention]) -> String {
        var html = messageHTML(fromMarkdown: text)

        for (index, mention) in mentions.enumerated() {
            html = html.replacingOccurrences(of: ComposerMention.placeholder(index), with: mention.html)
        }

        return html
    }

    // discord's markdown as typed in the app, made into the html the web editor writes for it:
    // **bold**, *italic* or _italic_, __underline__, ~~strike~~, `code`, ``` blocks ```, lines
    // starting "> " as a quote, "- " or "* " as a list and "1. " as a numbered one
    static func messageHTML(fromMarkdown text: String) -> String {
        var html = ""
        var codeLines: [String]?
        var listTag: String?
        var quoteLines: [String] = []

        func closeList() {
            if let tag = listTag {
                html += "</\(tag)>"
                listTag = nil
            }
        }

        func closeQuote() {
            if !quoteLines.isEmpty {
                html += "<blockquote>" + quoteLines.map { "<p>\(inline($0))</p>" }.joined() + "</blockquote>"
                quoteLines = []
            }
        }

        for line in text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if let lines = codeLines {
                    html += "<pre><code>\(escape(lines.joined(separator: "\n")))</code></pre>"
                    codeLines = nil
                } else {
                    closeList()
                    closeQuote()
                    codeLines = []
                }
                continue
            }

            if codeLines != nil {
                codeLines?.append(line)
                continue
            }

            if let quoted = line.firstMatch(of: /^>\s?(.*)$/) {
                closeList()
                quoteLines.append(String(quoted.1))
                continue
            }

            closeQuote()

            let bullet = line.firstMatch(of: /^\s*[-*]\s+(.+)$/)
            let numbered = line.firstMatch(of: /^\s*\d+[.)]\s+(.+)$/)

            if let item = bullet?.1 ?? numbered?.1 {
                let tag = bullet != nil ? "ul" : "ol"

                if listTag != tag {
                    closeList()
                    html += "<\(tag)>"
                    listTag = tag
                }

                html += "<li><p>\(inline(String(item)))</p></li>"
                continue
            }

            closeList()
            html += "<p>\(inline(line))</p>"
        }

        // an unclosed fence keeps what was typed as code rather than dropping it
        if let lines = codeLines {
            html += "<pre><code>\(escape(lines.joined(separator: "\n")))</code></pre>"
        }

        closeList()
        closeQuote()

        return html
    }

    // the reverse, so editing a message starts from markdown and keeps its formatting
    static func markdown(from html: String) -> String {
        // numbered first, the generic rule below would make every item a bullet
        var text = html.replacing(/<ol[^>]*>(.*?)<\/ol>/.dotMatchesNewlines()) { list in
            var number = 0

            return String(list.1).replacing(/<li[^>]*>\s*(<p[^>]*>)?/) { _ in
                number += 1

                return "\(number). "
            }
        }

        let replacements: [(String, String)] = [
            ("<pre[^>]*>\\s*<code[^>]*>", "```\n"),
            ("</code>\\s*</pre>", "\n```"),
            ("<strong>|</strong>", "**"),
            ("<em>|</em>", "*"),
            ("<u>|</u>", "__"),
            ("<s>|</s>", "~~"),
            ("<code>|</code>", "`"),
            ("<blockquote>\\s*<p[^>]*>", "> "),
            ("</blockquote>", "\n"),
            ("<li[^>]*>\\s*(<p[^>]*>)?", "- "),
            ("</li>", "\n"),
            ("<br\\s*/?>", "\n"),
            ("</p>\\s*<p[^>]*>", "\n"),
            ("<[^>]+>", "")
        ]

        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }

        return decodeEntities(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // a line's inline markdown. code spans are taken out first so nothing inside them is
    // formatted, and the rest is linked and escaped before the markers become tags
    private static func inline(_ line: String) -> String {
        var html = ""
        var rest = line[...]

        while let match = rest.firstMatch(of: /`([^`]+)`/) {
            html += formatted(linked(String(rest[rest.startIndex..<match.range.lowerBound])))
            html += "<code>\(escape(String(match.1)))</code>"
            rest = rest[match.range.upperBound...]
        }

        return html + formatted(linked(String(rest)))
    }

    // only text between tags is touched, so a link's address keeps its underscores
    private static func formatted(_ html: String) -> String {
        var result = ""
        var rest = html[...]

        while let tag = rest.firstMatch(of: /<[^>]+>/) {
            result += markers(String(rest[rest.startIndex..<tag.range.lowerBound]))
            result += String(tag.0)
            rest = rest[tag.range.upperBound...]
        }

        return result + markers(String(rest))
    }

    // icu patterns, swift's own regex has no lookbehind. a single * or _ only counts with no
    // word character against its outside, so snake_case and 2*3*4 stay as typed
    private static let markerPatterns: [(String, String)] = [
        ("\\*\\*(.+?)\\*\\*", "<strong>$1</strong>"),
        ("__(.+?)__", "<u>$1</u>"),
        ("~~(.+?)~~", "<s>$1</s>"),
        ("(?<![\\w*])\\*(?!\\s)(.+?)(?<!\\s)\\*(?![\\w*])", "<em>$1</em>"),
        ("(?<![\\w_])_(?!\\s)(.+?)(?<!\\s)_(?![\\w_])", "<em>$1</em>")
    ]

    private static func markers(_ text: String) -> String {
        markerPatterns.reduce(text) { result, pattern in
            result.replacingOccurrences(of: pattern.0, with: pattern.1, options: .regularExpression)
        }
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    // web links typed in a message become links, a bare domain included, as the web client's
    // editor does it, so they show as links and the server's link search finds them
    private static func linked(_ line: String) -> String {
        guard let linkDetector else {
            return escape(line)
        }

        let text = line as NSString
        var html = ""
        var position = 0

        for match in linkDetector.matches(in: line, range: NSRange(location: 0, length: text.length)) {
            guard let url = match.url, url.scheme == "http" || url.scheme == "https" else {
                continue
            }

            let written = text.substring(with: match.range)
            // the detector gives a bare domain http, nearly every site is https now
            let href = written.lowercased().hasPrefix("http") ? url.absoluteString : "https://\(written)"

            html += escape(text.substring(with: NSRange(location: position, length: match.range.location - position)))
            html += "<a href=\"\(escape(href))\">\(escape(written))</a>"
            position = match.range.location + match.range.length
        }

        return html + escape(text.substring(from: position))
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func decodeEntities(_ text: String) -> String {
        let named = [
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " "
        ]

        var result = text

        for (entity, character) in named {
            result = result.replacingOccurrences(of: entity, with: character)
        }

        result = result.replacing(/&#(\d+);/) { match in
            UInt32(match.1).flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ""
        }

        // last, so "&amp;lt;" decodes to the literal text "&lt;"
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}
