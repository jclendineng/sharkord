import Foundation
import SwiftUI

// a mention picked in the composer: the name the field shows for it, the way Messages shows
// one, and the span the web client's editor writes for it, which is what makes it a mention
nonisolated struct ComposerMention: Hashable, Sendable, Codable {
    let label: String
    let html: String

    // the span keeps the @ inside, as the web editor writes it, so the web still reads @name
    @MainActor static func user(_ user: PublicUser) -> ComposerMention {
        ComposerMention(
            label: user.name,
            html: "<span data-type=\"mention\" data-user-id=\"\(user.id)\" class=\"mention\">@\(HTMLText.escape(user.name))</span>"
        )
    }

    @MainActor static func role(_ role: Role) -> ComposerMention {
        ComposerMention(
            label: role.name,
            html: "<span data-type=\"role-mention\" data-role-id=\"\(role.id)\" class=\"role-mention\">@\(HTMLText.escape(role.name))</span>"
        )
    }

    // the web editor writes a channel reference empty, the chip finds the name itself
    @MainActor static func channel(_ channel: Channel) -> ComposerMention {
        ComposerMention(
            label: "#\(channel.name)",
            html: "<span data-type=\"channel-reference\" data-channel-id=\"\(channel.id)\" class=\"channel-reference\"></span>"
        )
    }

    // the mention as it sits in the field, one run the field tints and drops when it is edited
    var fieldText: AttributedString {
        var text = AttributedString(label)
        text[ComposerMentionAttribute.self] = self
        text.foregroundColor = Theme.mentionTint

        return text
    }

    // a private use character pair, which no markdown, linking or escaping touches, stands in
    // for a mention while the text goes through them
    static func placeholder(_ index: Int) -> String {
        "\u{E000}\(index)\u{E001}"
    }

    // the field as text for the markdown conversion, a placeholder where each mention sits
    static func draft(of field: AttributedString) -> (text: String, mentions: [ComposerMention]) {
        var text = ""
        var mentions: [ComposerMention] = []

        for (mention, range) in field.runs[ComposerMentionAttribute.self] {
            if let mention {
                text += placeholder(mentions.count)
                mentions.append(mention)
            } else {
                text += String(field[range].characters)
            }
        }

        return (text, mentions)
    }

    // what each member, role and channel reads as typed out, longest first
    @MainActor static func typedCandidates(in session: SessionStore) -> [(typed: String, mention: ComposerMention)] {
        var candidates: [(typed: String, mention: ComposerMention)] = []

        for user in session.usersById.values where !user.isDeleted {
            candidates.append((typed: "@\(user.name)", mention: Self.user(user)))
        }

        for role in session.rolesById.values {
            candidates.append((typed: "@\(role.name)", mention: Self.role(role)))
        }

        for channel in session.channels where !channel.isDm {
            candidates.append((typed: "#\(channel.name)", mention: Self.channel(channel)))
        }

        candidates.sort { $0.typed.count > $1.typed.count }

        return candidates
    }

    // the mention an @name or #name typed out in full names, case aside
    @MainActor static func matching(_ typed: String, in session: SessionStore) -> ComposerMention? {
        let candidates = typedCandidates(in: session)

        guard let candidate = candidates.first(where: { $0.typed.caseInsensitiveCompare(typed) == .orderedSame }) else {
            return nil
        }

        return candidate.mention
    }

    // an @name or #name typed out in full rather than picked is a mention too, when it names a
    // member, role or channel exactly, case aside. longest first, so @joel does not take the
    // start of @joel.c
    @MainActor static func resolvingTyped(in draft: (text: String, mentions: [ComposerMention]), session: SessionStore) -> (text: String, mentions: [ComposerMention]) {
        var text = draft.text
        var mentions = draft.mentions

        for (typed, mention) in typedCandidates(in: session) where text.localizedCaseInsensitiveContains(typed) {
            let pattern = "(?<![\\w@#])\(NSRegularExpression.escapedPattern(for: typed))(?!\\w)"
            let placeholder = placeholder(mentions.count)

            text = text.replacingOccurrences(of: pattern, with: placeholder, options: [.regularExpression, .caseInsensitive])

            if text.contains(placeholder) {
                mentions.append(mention)
            }
        }

        return (text, mentions)
    }

    // text with placeholders back into a field, each placeholder its mention's run
    static func field(from text: String, mentions: [ComposerMention]) -> AttributedString {
        var field = AttributedString()
        var rest = text[...]

        while let match = rest.firstMatch(of: /\u{E000}(\d+)\u{E001}/) {
            field += AttributedString(String(rest[rest.startIndex..<match.range.lowerBound]))

            if let index = Int(match.1), mentions.indices.contains(index) {
                field += mentions[index].fieldText
            }

            rest = rest[match.range.upperBound...]
        }

        return field + AttributedString(String(rest))
    }

    // a message being edited: each mention span becomes a placeholder and its mention, so the
    // field shows it as picked and saving keeps it. one whose user, role or channel is gone
    // stays as the span, which the markdown conversion makes its text
    @MainActor static func editable(from html: String, in session: SessionStore) -> (html: String, mentions: [ComposerMention]) {
        var mentions: [ComposerMention] = []

        let replaced = html.replacing(/<span[^>]*data-type="(mention|role-mention|channel-reference)"[^>]*>.*?<\/span>/) { match in
            let span = String(match.0)
            var mention: ComposerMention?

            if let idMatch = span.firstMatch(of: /data-(?:user|role|channel)-id="(\d+)"/), let id = Int(idMatch.1) {
                switch match.1 {
                case "mention":
                    mention = session.usersById[id].map(Self.user)
                case "role-mention":
                    mention = session.rolesById[id].map(Self.role)
                default:
                    mention = session.channel(id).map(Self.channel)
                }
            }

            guard let mention else {
                return span
            }

            mentions.append(mention)

            return placeholder(mentions.count - 1)
        }

        return (replaced, mentions)
    }
}

// added text never takes the mention on, and changing a mention's text drops it, so typing
// next to one or deleting into it leaves plain text. the field keeps its text in uikit, so the
// mention crosses into an NSAttributedString and back as json, or the first edit loses it
nonisolated enum ComposerMentionAttribute: CodableAttributedStringKey, ObjectiveCConvertibleAttributedStringKey {
    typealias Value = ComposerMention
    typealias ObjectiveCValue = NSString

    static let name = "sharkord.composerMention"
    static let inheritedByAddedText = false
    static let invalidationConditions: Set<AttributedString.AttributeInvalidationCondition>? = [.textChanged]

    static func objectiveCValue(for value: ComposerMention) throws -> NSString {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self) as NSString
    }

    static func value(for object: NSString) throws -> ComposerMention {
        try JSONDecoder().decode(ComposerMention.self, from: Data((object as String).utf8))
    }
}

extension AttributeScopes {
    // all the field keeps: what someone pastes or formats from the edit menu is left out, the
    // composer's formatting is the markdown typed
    nonisolated struct ComposerAttributes: AttributeScope {
        let composerMention: ComposerMentionAttribute
        let foregroundColor: AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
    }
}
