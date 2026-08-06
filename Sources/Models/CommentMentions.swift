import Foundation
import SwiftUI

/// Penpot's comment-mention wire format: mentions live *inside* the comment `content` as
/// `@[Fullname](profile-uuid)` — the same markup the web client writes and the backend
/// parses (frontend and backend share the regex). The RPC additionally takes a `mentions`
/// param with the profile ids, which the web client derives from the content; helpers
/// here mirror that so views only ever deal with display text.
enum CommentMention {

    /// A mention chosen in the composer (or recovered from existing markup).
    struct Pick: Equatable {
        let name: String
        let id: String
    }

    /// Hard server limit on the *serialized* content length.
    static let maxContentLength = 750

    // `@[name](id)` — group 1 = display name, group 2 = profile id.
    private static let regex = try! NSRegularExpression(pattern: #"@\[([^\]]*)\]\(([^)]*)\)"#)

    private static func isUUID(_ candidate: String) -> Bool {
        UUID(uuidString: candidate) != nil
    }

    private struct Match {
        let range: Range<String.Index>
        let name: String
        let id: String
    }

    /// All well-formed mentions in `content`, in order. Tokens whose id is not a UUID are
    /// left alone (rendered literally), matching the web client.
    private static func matches(in content: String) -> [Match] {
        let full = NSRange(content.startIndex..., in: content)
        return regex.matches(in: content, range: full).compactMap { result in
            guard let range = Range(result.range, in: content),
                  let nameRange = Range(result.range(at: 1), in: content),
                  let idRange = Range(result.range(at: 2), in: content) else { return nil }
            let id = String(content[idRange])
            guard isUUID(id) else { return nil }
            return Match(range: range, name: String(content[nameRange]), id: id)
        }
    }

    /// The mentioned profile ids, deduped, in order of first appearance — the value of the
    /// RPC `mentions` param.
    static func extractIDs(from content: String) -> [String] {
        var seen = Set<String>()
        return matches(in: content).map(\.id).filter { seen.insert($0).inserted }
    }

    /// `content` with mention markup reduced to plain `@Name` text.
    static func displayText(from content: String) -> String {
        var result = ""
        var cursor = content.startIndex
        for match in matches(in: content) {
            result += content[cursor..<match.range.lowerBound]
            result += "@\(match.name)"
            cursor = match.range.upperBound
        }
        result += content[cursor...]
        return result
    }

    /// `content` rendered for display: mentions as accent-colored, semibold `@Name` runs.
    static func attributedString(from content: String) -> AttributedString {
        var result = AttributedString()
        var cursor = content.startIndex
        for match in matches(in: content) {
            result += AttributedString(String(content[cursor..<match.range.lowerBound]))
            var mention = AttributedString("@\(match.name)")
            mention.foregroundColor = .penpotAccent
            mention.inlinePresentationIntent = .stronglyEmphasized
            result += mention
            cursor = match.range.upperBound
        }
        result += AttributedString(String(content[cursor...]))
        return result
    }

    /// Display text + the picks needed to re-serialize it — seeds editing an existing comment.
    static func displayRepresentation(of content: String) -> (text: String, mentions: [Pick]) {
        var picks: [Pick] = []
        for match in matches(in: content) {
            let pick = Pick(name: match.name, id: match.id)
            if !picks.contains(pick) { picks.append(pick) }
        }
        return (displayText(from: content), picks)
    }

    /// Converts composer text back to wire markup by replacing each pick's `@Name` with
    /// `@[Name](id)`. Longest names first so "@Ann Lee" can't be half-eaten by a pick named
    /// "@Ann"; picks whose `@Name` no longer appears are dropped. Two members sharing the
    /// exact same name are ambiguous — first pick wins, same as the web client.
    static func serialize(display: String, mentions: [Pick]) -> String {
        var result = display
        for pick in mentions.sorted(by: { $0.name.count > $1.name.count }) where !pick.name.isEmpty {
            result = result.replacingOccurrences(of: "@\(pick.name)", with: "@[\(pick.name)](\(pick.id))")
        }
        return result
    }
}
