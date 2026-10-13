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

    // the server sanitizes whatever it receives, escaping here keeps typed angle brackets as text
    static func paragraphs(from text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { "<p>\(escape($0))</p>" }
            .joined()
    }

    private static func escape(_ text: String) -> String {
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
