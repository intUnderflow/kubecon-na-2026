import Foundation

/// Parser for Sessionize's per-session markdown
/// (`https://sessionize.com/api/v2/uo948i5p/view/markdown/session/<id>`).
///
/// A line-for-line port of `parse()` in scripts/fetch_details.py (the web's `parseMd`), so a
/// live fetch gives exactly what details.json would have held:
///
/// - split on `## ` / `### ` headings (lowercased); keep "description" and "speakers" (or "speaker"),
/// - a speaker is a `- ` / `* ` bullet: `[Name](url) — tagline` (em, en dash or hyphen), or
///   `**Name** — tagline` / `Name – tagline` (em or en dash only).
///
/// Python's `\s` and `str.strip()` are Unicode-aware, so `WS` and ``pyStrip(_:)`` spell out the
/// same character set; `.` becomes `[^\n]` and `$` becomes `\z` (lines never contain `\n`).
enum SessionizeMarkdown {
    /// Python 3 `\s` for str patterns: ASCII whitespace plus every char where `str.isspace()`.
    private static let WS = "[\\t\\n\\u000B\\f\\r \\u001C-\\u001F\\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000]"

    private static let HEADING = KRegex("^#{2,3}\(WS)+([^\\n]+?)\(WS)*\\z")
    private static let BULLET = KRegex("^\(WS)*[-*]\(WS)+")
    private static let LINKED = KRegex("^\\[([^\\]]+)\\]\\([^)]*\\)\(WS)*(?:[—–-]\(WS)*([^\\n]*))?\\z")
    private static let PLAIN = KRegex("^\\**([^—–*]+?)\\**\(WS)*(?:[—–]\(WS)*([^\\n]*))?\\z")

    /// `md` → description (blank-line paragraphs, as written) and speakers with taglines.
    static func parse(_ md: String) -> SessionDetail {
        // Section name -> its lines. A repeated heading starts its section afresh.
        var sections: [String: [String]] = [:]
        var cur: String?
        for line in md.kotlinReplace("\r\n", "\n").kotlinSplit("\n") {
            if let h = HEADING.find(line) {
                let key = h.groupValues[1].lowercased()
                sections[key] = []
                cur = key
            } else if let cur {
                sections[cur, default: []].append(line)
            }
        }
        var speakers: [SpeakerTagline] = []
        for raw in sections["speakers"] ?? sections["speaker"] ?? [] {
            if !BULLET.containsMatchIn(raw) { continue }
            let line = pyStrip(BULLET.replaceFirst(raw, ""))
            if let m = LINKED.find(line) ?? PLAIN.find(line) {
                speakers.append(SpeakerTagline(pyStrip(m.groupValues[1]), pyStrip(m.groupValues[2])))
            } else {
                speakers.append(SpeakerTagline(line, ""))
            }
        }
        let description = pyStrip((sections["description"] ?? []).joined(separator: "\n"))
        return SessionDetail(description: description, speakers: speakers)
    }

    /// Python's `str.strip()` (same whitespace set as `WS`), over UTF-16 units.
    static func pyStrip(_ s: String) -> String {
        let u = Array(s.utf16)
        var a = 0
        var b = u.count
        while a < b && isPySpace(u[a]) { a += 1 }
        while b > a && isPySpace(u[b - 1]) { b -= 1 }
        if a == 0 && b == u.count { return s }
        return String(decoding: u[a..<b], as: UTF16.self)
    }

    private static func isPySpace(_ c: UInt16) -> Bool {
        switch c {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680,
             0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            return true
        case 0x1C...0x1F, 0x2000...0x200A:
            return true
        default:
            return false
        }
    }
}
