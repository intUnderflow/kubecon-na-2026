import Foundation

/// Turns a session description (Sessionize markdown, or Maintainer Summit plain text) into
/// blocks the details screen can render legibly. A superset of the web's `paras()`:
///
/// - paragraphs split on blank lines; single newlines stay line breaks (the web's `<br>`),
/// - list lines become bulleted / numbered items with a hanging indent. Sessionize escapes the
///   markers (`\- item`, `\* item`, `1\. item`), plain `- `, `* `, `+ `, `• `, `– ` work too,
/// - `[text](https://…)` shows `text` as a link, as do `<https://…>` and bare URLs (trailing
///   punctuation and unbalanced brackets stay outside the link),
/// - `**bold**` / `__bold__` are bold, `*italic*` / `_italic_` italic, `\*`-style escapes are literal.
///
/// Pure Foundation (no SwiftUI types) so it is unit-tested on Linux; the SwiftUI layer maps
/// ``Rich`` to an `AttributedString` (see ``Rich/stringRange(_:)``: span offsets are UTF-16
/// units, like Kotlin's string indices).
///
/// Kotlin -> Swift: the scanner works on the UTF-16 units of the text (Kotlin `s[i]`), so
/// offsets and character classes match the Android app for any text.
enum DescriptionFormat {

    /// Text with styled ranges (``Span/start`` inclusive, ``Span/end`` exclusive, in UTF-16
    /// units of `text`).
    struct Rich: Sendable, Hashable {
        let text: String
        let spans: [Span]

        init(_ text: String, _ spans: [Span] = []) {
            self.text = text
            self.spans = spans
        }

        init(text: String, spans: [Span] = []) {
            self.init(text, spans)
        }

        /// The `String.Index` range of `span` in ``text``, for building an `AttributedString`
        /// (`AttributedString.Index(range.lowerBound, within: attributed)`). Nil if the span does
        /// not fit the text (never for spans made by ``DescriptionFormat``, whose boundaries never
        /// split a surrogate pair; they may fall inside a grapheme cluster, e.g. before a
        /// combining mark, which `String.Index` addresses fine).
        func stringRange(_ span: Span) -> Range<String.Index>? {
            let u = text.utf16
            guard span.start >= 0, span.start <= span.end, span.end <= u.count else { return nil }
            let a = u.index(u.startIndex, offsetBy: span.start)
            let b = u.index(a, offsetBy: span.end - span.start)
            return a..<b
        }

        /// ``text`` cut at every span boundary into runs with the styles that cover them (the
        /// Compose code adds one style per span; SwiftUI can concatenate one `AttributedString`
        /// per run instead). Runs are in order, never empty, and join to ``text``. A run inside
        /// two links (`[x <https://a.b>](https://c.d)`) takes the innermost one's URL.
        var runs: [Run] {
            let u = Array(text.utf16)
            if spans.isEmpty { return u.isEmpty ? [] : [Run(text: text, bold: false, italic: false, url: nil)] }
            var cuts = Set([0, u.count])
            for s in spans {
                cuts.insert(Swift.min(Swift.max(0, s.start), u.count))
                cuts.insert(Swift.min(Swift.max(0, s.end), u.count))
            }
            let points = cuts.sorted()
            var out: [Run] = []
            for k in 0..<(points.count - 1) {
                let a = points[k], b = points[k + 1]
                if a >= b { continue }
                var bold = false, italic = false
                var url: String?
                // Spans are sorted by start, then longest first: a later covering link is nested deeper.
                for s in spans where s.start <= a && s.end >= b {
                    switch s {
                    case .bold: bold = true
                    case .italic: italic = true
                    case .link(_, _, let target): url = target
                    }
                }
                out.append(Run(text: String(decoding: u[a..<b], as: UTF16.self), bold: bold, italic: italic, url: url))
            }
            return out
        }
    }

    /// A piece of a ``Rich`` text with uniform style (see ``Rich/runs``).
    struct Run: Sendable, Hashable {
        let text: String
        let bold: Bool
        let italic: Bool
        /// The link target, nil when the run is not a link.
        let url: String?
    }

    /// Kotlin `sealed interface Span` (Bold / Italic / Link), positional like Kotlin:
    /// `.bold(32, 51)`, `.link(4, 12, "https://…")`.
    enum Span: Sendable, Hashable {
        case bold(_ start: Int, _ end: Int)
        case italic(_ start: Int, _ end: Int)
        case link(_ start: Int, _ end: Int, _ url: String)

        var start: Int {
            switch self {
            case .bold(let s, _), .italic(let s, _), .link(let s, _, _): return s
            }
        }

        var end: Int {
            switch self {
            case .bold(_, let e), .italic(_, let e), .link(_, let e, _): return e
            }
        }

        /// The link target, nil for bold / italic (Kotlin `(span as? Span.Link)?.url`).
        var url: String? {
            if case .link(_, _, let u) = self { return u }
            return nil
        }

        var isLink: Bool { url != nil }
    }

    /// Kotlin `sealed interface Block`.
    enum Block: Sendable, Hashable {
        /// One paragraph; `\n` inside the text is a line break.
        case paragraph(Rich)

        /// Consecutive list items.
        case listBlock([Item])

        /// A `#`-style heading line, shown as a bold paragraph.
        case heading(Rich)
    }

    /// `marker` is "•" for bullets or the number as written ("1.", "2)").
    struct Item: Sendable, Hashable {
        let marker: String
        let text: Rich
        let ordered: Bool

        init(_ marker: String, _ text: Rich, ordered: Bool) {
            self.marker = marker
            self.text = text
            self.ordered = ordered
        }
    }

    private static let BLANK_LINES = KRegex("\\n(?:[ \\t\\u00A0]*\\n)+")
    private static let LIST_ITEM =
        KRegex("^[ \\t]*(?:\\\\?([-*+])|([•·▪◦‣–])|(\\d{1,3})\\\\?([.)]))[ \\t\\u00A0]+(\\S.*)$")
    private static let HEADING = KRegex("^[ \\t]*#{1,6}[ \\t]+(\\S.*?)[ \\t#]*$")
    private static let ESCAPABLE: Set<UInt16> = Set("\\`*_{}[]()#+-.!>~|<\"'".utf16)

    /// Blocks for `description`; empty for nil/blank.
    static func parse(_ description: String?) -> [Block] {
        guard let description, !description.isBlank else { return [] }
        let text = description.kotlinReplace("\r\n", "\n").kotlinReplace("\r", "\n")
        var out: [Block] = []
        for chunk in text.split(BLANK_LINES) {
            if chunk.isBlank { continue }
            parseChunk(chunk, &out)
        }
        return out
    }

    private static func parseChunk(_ chunk: String, _ out: inout [Block]) {
        var para: [String] = []
        var items: [(marker: String, text: String)] = []
        var ordered = false

        func flushPara() {
            if !para.isEmpty {
                out.append(.paragraph(inline(para.joined(separator: "\n"))))
                para.removeAll()
            }
        }

        func flushList() {
            if !items.isEmpty {
                out.append(.listBlock(items.map { m, t in Item(m, inline(t.kotlinTrim()), ordered: m != "•") }))
                items.removeAll()
            }
        }

        for raw in chunk.kotlinSplit("\n") {
            let line = raw.kotlinTrimEnd()
            if line.isBlank { continue }
            let li = LIST_ITEM.find(line)
            let h = li == nil ? HEADING.find(line) : nil
            if let li {
                flushPara()
                let number = li.groupValues[3]
                let isOrdered = !number.isEmpty
                if !items.isEmpty && isOrdered != ordered { flushList() }
                ordered = isOrdered
                let marker = isOrdered ? number + li.groupValues[4] : "•"
                items.append((marker, li.groupValues[5]))
            } else if let h {
                flushPara()
                flushList()
                out.append(.heading(inline(h.groupValues[1])))
            } else if !items.isEmpty && (raw.kotlinStartsWith(" ") || raw.kotlinStartsWith("\t")) {
                // An indented line right after an item continues it.
                items[items.count - 1].text += " " + line.kotlinTrim()
            } else {
                flushList()
                para.append(line.kotlinTrim())
            }
        }
        flushPara()
        flushList()
    }

    /// Inline markdown in `s`: escapes, links, bare URLs, bold and italic.
    static func inline(_ s: String) -> Rich {
        var scanner = InlineScanner(s)
        scanner.inlineInto(0, scanner.s.count)
        let byStart = KComparator<Span>.by { $0.start }.thenByDescending { $0.end }
        let spans = scanner.spans.stableSorted(with: byStart)
        return Rich(String(decoding: scanner.out, as: UTF16.self), spans)
    }

    /// The inline scanner: Kotlin's `inlineInto` / `mdLink` / `emphasis` over UTF-16 units,
    /// appending to `out` (Kotlin's StringBuilder) and `spans`.
    private struct InlineScanner {
        let s: [UInt16]
        var out: [UInt16] = []
        var spans: [Span] = []

        init(_ text: String) {
            s = Array(text.utf16)
            out.reserveCapacity(s.count)
        }

        private static let backslash = UInt16(UInt8(ascii: "\\"))
        private static let lbracket = UInt16(UInt8(ascii: "["))
        private static let rbracket = UInt16(UInt8(ascii: "]"))
        private static let lparen = UInt16(UInt8(ascii: "("))
        private static let rparen = UInt16(UInt8(ascii: ")"))
        private static let lt = UInt16(UInt8(ascii: "<"))
        private static let gt = UInt16(UInt8(ascii: ">"))
        private static let star = UInt16(UInt8(ascii: "*"))
        private static let underscore = UInt16(UInt8(ascii: "_"))
        private static let newline = UInt16(UInt8(ascii: "\n"))
        private static let quote = UInt16(UInt8(ascii: "\""))
        private static let h = UInt16(UInt8(ascii: "h"))
        private static let H = UInt16(UInt8(ascii: "H"))

        mutating func inlineInto(_ from: Int, _ to: Int) {
            var i = from
            while i < to {
                let c = s[i]
                if c == Self.backslash && i + 1 < to && ESCAPABLE.contains(s[i + 1]) {
                    out.append(s[i + 1])
                    i += 2
                } else if c == Self.lbracket {
                    let end = mdLink(i, to)
                    if end > 0 {
                        i = end
                    } else {
                        out.append(c)
                        i += 1
                    }
                } else if c == Self.lt {
                    let close = indexOf(Self.gt, i + 1)
                    let url: [UInt16]? = (close >= i + 1 && close < to) ? Array(s[(i + 1)..<close]) : nil
                    if let url, isUrl(url), !url.contains(where: isKotlinWhitespace) {
                        let start = out.count
                        out.append(contentsOf: url)
                        spans.append(.link(start, out.count, string(url)))
                        i = close + 1
                    } else {
                        out.append(c)
                        i += 1
                    }
                } else if (c == Self.star || c == Self.underscore) && i + 1 < to && s[i + 1] == c {
                    let end = emphasis(i, to, 2)
                    if end > 0 {
                        i = end
                    } else {
                        out.append(c)
                        out.append(c)
                        i += 2
                    }
                } else if c == Self.star || c == Self.underscore {
                    let end = emphasis(i, to, 1)
                    if end > 0 {
                        i = end
                    } else {
                        out.append(c)
                        i += 1
                    }
                } else if (c == Self.h || c == Self.H) && startsUrl(i) && (i == from || !isLetterOrDigit(s[i - 1])) {
                    let end = bareUrlEnd(i, to)
                    let url = Array(s[i..<end])
                    let start = out.count
                    out.append(contentsOf: url)
                    spans.append(.link(start, out.count, string(url)))
                    i = end
                } else {
                    out.append(c)
                    i += 1
                }
            }
        }

        /// `[text](url)` at `i`; returns the index after it, or -1 if it isn't a link.
        private mutating func mdLink(_ i: Int, _ to: Int) -> Int {
            var j = i + 1
            while j < to && s[j] != Self.rbracket && s[j] != Self.newline {
                if s[j] == Self.backslash { j += 1 }
                j += 1
            }
            if j >= to || s[j] != Self.rbracket || j == i + 1 || j + 1 >= to || s[j + 1] != Self.lparen { return -1 }
            let close = indexOf(Self.rparen, j + 2)
            if close < 0 || close >= to { return -1 }
            let url = string(Array(s[(j + 2)..<close])).kotlinTrim().substringBefore(" ")
            let u = Array(url.utf16)
            if !isUrl(u) && !url.kotlinStartsWith("mailto:") { return -1 }
            let start = out.count
            inlineInto(i + 1, j)
            spans.append(.link(start, out.count, url))
            return close + 1
        }

        /// `**x**` / `__x__` (`n` = 2) or `*x*` / `_x_` (`n` = 1) at `i`. Opening delimiters must be
        /// followed by non-space and closers preceded by non-space; `_` must also sit on word
        /// boundaries (so snake_case stays literal). Returns the index after the closer, or -1.
        private mutating func emphasis(_ i: Int, _ to: Int, _ n: Int) -> Int {
            let d = s[i]
            let open = i + n
            if open >= to || isKotlinWhitespace(s[open]) || s[open] == d { return -1 }
            if d == Self.underscore && i > 0 && isLetterOrDigit(s[i - 1]) { return -1 }
            var j = open + 1
            while j + n <= to {
                if s[j] == Self.backslash {
                    j += 2
                    continue
                }
                var allD = true
                for k in 0..<n where s[j + k] != d { allD = false }
                let isCloser = allD && !isKotlinWhitespace(s[j - 1]) &&
                    (n == 2 || j + 1 >= to || s[j + 1] != d)
                if isCloser && (d != Self.underscore || j + n >= to || !isLetterOrDigit(s[j + n])) {
                    let start = out.count
                    inlineInto(open, j)
                    spans.append(n == 2 ? .bold(start, out.count) : .italic(start, out.count))
                    return j + n
                }
                if s[j] == Self.newline && j + 1 < to && s[j + 1] == Self.newline { return -1 }
                j += 1
            }
            return -1
        }

        private func startsUrl(_ i: Int) -> Bool {
            regionMatchesIgnoreCase(s, i, Self.https) || regionMatchesIgnoreCase(s, i, Self.http)
        }

        private static let https = Array("https://".utf16)
        private static let http = Array("http://".utf16)

        private func isUrl(_ u: [UInt16]) -> Bool {
            (regionMatchesIgnoreCase(u, 0, Self.https) && u.count > 8) ||
                (regionMatchesIgnoreCase(u, 0, Self.http) && u.count > 7)
        }

        /// End of a bare URL starting at `i`: up to whitespace, minus trailing punctuation / unbalanced closers.
        private func bareUrlEnd(_ i: Int, _ to: Int) -> Int {
            var e = i
            while e < to && !isKotlinWhitespace(s[e]) && s[e] != Self.lt && s[e] != Self.gt && s[e] != Self.quote { e += 1 }
            while e > i {
                let last = s[e - 1]
                let drop: Bool
                if Self.trailingPunctuation.contains(last) {
                    drop = true
                } else if last == Self.rparen {
                    drop = count(Self.rparen, i, e) > count(Self.lparen, i, e)
                } else if last == Self.rbracket {
                    drop = count(Self.rbracket, i, e) > count(Self.lbracket, i, e)
                } else {
                    drop = false
                }
                if !drop { break }
                e -= 1
            }
            return e
        }

        private static let trailingPunctuation: Set<UInt16> = Set(".,;:!?'*_’”".utf16)

        private func count(_ c: UInt16, _ a: Int, _ b: Int) -> Int {
            var n = 0
            for k in a..<b where s[k] == c { n += 1 }
            return n
        }

        /// Kotlin `s.indexOf(c, from)` (whole string, not bounded by `to`).
        private func indexOf(_ c: UInt16, _ from: Int) -> Int {
            var k = Swift.max(0, from)
            while k < s.count {
                if s[k] == c { return k }
                k += 1
            }
            return -1
        }

        private func string(_ units: [UInt16]) -> String { String(decoding: units, as: UTF16.self) }
    }
}

/// Java `String.regionMatches(true, offset, prefix, 0, prefix.length)` (Kotlin
/// `startsWith(prefix, offset, ignoreCase = true)`): per UTF-16 unit, equal, or equal after
/// uppercasing, or after lowercasing the uppercased units.
private func regionMatchesIgnoreCase(_ s: [UInt16], _ offset: Int, _ prefix: [UInt16]) -> Bool {
    guard offset >= 0, offset + prefix.count <= s.count else { return false }
    for k in 0..<prefix.count {
        let a = s[offset + k], b = prefix[k]
        if a == b { continue }
        let ua = javaToUpperCase(a), ub = javaToUpperCase(b)
        if ua == ub { continue }
        if javaToLowerCase(ua) == javaToLowerCase(ub) { continue }
        return false
    }
    return true
}

/// Kotlin `Char.isLetterOrDigit()` on one UTF-16 unit (Java `Character.isLetterOrDigit(char)`):
/// general category L* or Nd; surrogate halves are neither.
private func isLetterOrDigit(_ c: UInt16) -> Bool {
    if c < 0x80 {
        return (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
    }
    guard let scalar = Unicode.Scalar(c) else { return false }
    switch scalar.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
        return true
    default:
        return false
    }
}
