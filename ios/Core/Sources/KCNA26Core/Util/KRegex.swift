import Foundation

/// Kotlin `Regex` on top of `NSRegularExpression` (ICU; also what Android's java.util.regex
/// runs on). Offsets and ranges are UTF-16 code units, like Kotlin's. Thread-safe and
/// `Sendable`, so patterns can be `static let` constants (Kotlin `private val X = Regex(...)`).
///
/// ```swift
/// private static let TRAILING_DASH = KRegex("[\\s]*[-–—]+\\s*$")
/// TRAILING_DASH.replace(text, "")                       // Kotlin replace(input, "")
/// LEVEL_TAIL.replace(s) { m in m.groupValues[1] }       // replace(input) { ... }
/// SAFE_NAME.matches(name)                               // whole input
/// HEADING.find(line)?.groupValues[1]
/// KRegex("Reception|Trivia", options: .ignoreCase).containsMatchIn(title)
/// ```
///
/// Syntax notes (java.util.regex vs ICU): `\p{L}`, `\p{Mn}`, lookarounds, `\z`, `(?i)` are the
/// same. ICU's `\s`, `\w`, `\b`, `\d` are Unicode-aware (`\s` also matches U+00A0 and U+2028);
/// on Android they are ICU too, but the desktop JVM that runs the Kotlin unit tests treats them
/// as ASCII. Write `[ \t\n\x0B\f\r]` where ASCII-only whitespace matters.
final class KRegex: @unchecked Sendable, CustomStringConvertible {
    /// Kotlin `RegexOption`.
    struct Options: OptionSet, Sendable {
        let rawValue: Int
        /// IGNORE_CASE (Unicode-aware, as Kotlin adds UNICODE_CASE).
        static let ignoreCase = Options(rawValue: 1)
        /// MULTILINE: `^` and `$` match at line breaks.
        static let multiline = Options(rawValue: 2)
        /// DOT_MATCHES_ALL.
        static let dotMatchesAll = Options(rawValue: 4)
        /// COMMENTS.
        static let comments = Options(rawValue: 8)
        /// LITERAL.
        static let literal = Options(rawValue: 16)
    }

    let pattern: String
    let options: Options
    private let regex: NSRegularExpression
    /// `\A(?:pattern)\z`, for whole-input ``matches(_:)`` (Java `Matcher.matches()` backtracks to
    /// cover the whole input, which a plain first match may not).
    private let whole: NSRegularExpression
    /// Names of the pattern's `(?<name>...)` groups.
    fileprivate let groupNames: [String]

    /// Compiles `pattern`. Traps on an invalid pattern (Kotlin throws PatternSyntaxException;
    /// patterns are constants, so this is a programming error).
    init(_ pattern: String, options: Options = []) {
        self.pattern = pattern
        self.options = options
        var o: NSRegularExpression.Options = []
        if options.contains(.ignoreCase) { o.insert(.caseInsensitive) }
        if options.contains(.multiline) { o.insert(.anchorsMatchLines) }
        if options.contains(.dotMatchesAll) { o.insert(.dotMatchesLineSeparators) }
        if options.contains(.comments) { o.insert(.allowCommentsAndWhitespace) }
        if options.contains(.literal) { o.insert(.ignoreMetacharacters) }
        do {
            regex = try NSRegularExpression(pattern: pattern, options: o)
            let wrapped = options.contains(.literal) ? NSRegularExpression.escapedPattern(for: pattern) : pattern
            var wo = o
            wo.remove(.ignoreMetacharacters)
            whole = try NSRegularExpression(pattern: "\\A(?:" + wrapped + ")\\z", options: wo)
        } catch {
            preconditionFailure("Invalid regex \(pattern): \(error)")
        }
        groupNames = options.contains(.literal) ? [] : KRegex.namedGroups(in: pattern)
    }

    /// Names of `(?<name>...)` groups in a pattern.
    private static func namedGroups(in pattern: String) -> [String] {
        guard pattern.contains("(?<") else { return [] }
        let finder = try! NSRegularExpression(pattern: "\\(\\?<([A-Za-z][A-Za-z0-9]*)>", options: [])
        let units = Array(pattern.utf16)
        return finder.matches(in: pattern, options: [], range: NSRange(location: 0, length: units.count)).map { r in
            let g = r.range(at: 1)
            return String(decoding: units[g.location..<(g.location + g.length)], as: UTF16.self)
        }
    }

    var description: String { pattern }

    /// Kotlin `Regex.escape(literal)`: a pattern matching `literal` exactly.
    static func escape(_ literal: String) -> String { NSRegularExpression.escapedPattern(for: literal) }

    private static func nsRange(_ s: String, from start: Int = 0) -> NSRange {
        let n = s.utf16.count
        let a = Swift.min(Swift.max(0, start), n)
        return NSRange(location: a, length: n - a)
    }

    /// Kotlin `matches(input)`: the WHOLE input matches.
    func matches(_ input: String) -> Bool {
        whole.firstMatch(in: input, options: [], range: KRegex.nsRange(input)) != nil
    }

    /// Kotlin `containsMatchIn(input)`.
    func containsMatchIn(_ input: String) -> Bool {
        regex.firstMatch(in: input, options: [], range: KRegex.nsRange(input)) != nil
    }

    /// Kotlin `find(input, startIndex)`: the first match at or after UTF-16 offset `startIndex`.
    func find(_ input: String, startIndex: Int = 0) -> KMatch? {
        guard let m = regex.firstMatch(in: input, options: [], range: KRegex.nsRange(input, from: startIndex)) else { return nil }
        return KMatch(m, Array(input.utf16), regex: self)
    }

    /// Kotlin `findAll(input, startIndex)`.
    func findAll(_ input: String, startIndex: Int = 0) -> [KMatch] {
        let units = Array(input.utf16)
        return regex.matches(in: input, options: [], range: KRegex.nsRange(input, from: startIndex)).map { KMatch($0, units, regex: self) }
    }

    /// Kotlin `replace(input, replacement)`: every match. `replacement` has Java's
    /// `Matcher.appendReplacement` syntax, implemented here (NSRegularExpression templates
    /// differ: no `${name}`, and they never reject a bad reference):
    /// `$n` (a group number: the first digit always, further digits while the number stays a
    /// valid group), `${name}` (a named group), `\x` (x literally, e.g. `\$`); an unmatched
    /// group adds nothing. An invalid reference (`$` at the end, `$x`, `${nope}`, `$5` with
    /// fewer groups, a trailing `\`) traps, where Kotlin throws IllegalArgumentException /
    /// IndexOutOfBoundsException (replacements are constants, so it is a programming error);
    /// like Java, the replacement is only examined when there is a match. Use
    /// ``replace(_:transform:)`` for computed replacements and ``escapeReplacement(_:)`` for a
    /// literal one.
    func replace(_ input: String, _ replacement: String) -> String {
        let units = Array(input.utf16)
        let ms = regex.matches(in: input, options: [], range: KRegex.nsRange(input))
        if ms.isEmpty { return input }
        let template = parseReplacement(replacement)
        var out: [UInt16] = []
        out.reserveCapacity(units.count)
        var last = 0
        for m in ms {
            out.append(contentsOf: units[last..<m.range.location])
            expand(template, m, units, into: &out)
            last = m.range.location + m.range.length
        }
        out.append(contentsOf: units[last...])
        return String(decoding: out, as: UTF16.self)
    }

    /// Kotlin `Regex.escapeReplacement(literal)`: a replacement that inserts `literal` as is.
    static func escapeReplacement(_ literal: String) -> String {
        guard literal.utf16.contains(where: { $0 == 0x5C || $0 == 0x24 }) else { return literal }
        var out: [UInt16] = []
        for c in literal.utf16 {
            if c == 0x5C || c == 0x24 { out.append(0x5C) }
            out.append(c)
        }
        return String(decoding: out, as: UTF16.self)
    }

    /// One piece of a parsed replacement: literal UTF-16 text or a group reference.
    private enum ReplacementPart {
        case text([UInt16])
        case group(Int)
        case named(String)
    }

    /// Java `Matcher.appendExpandedReplacement`'s parser (see ``replace(_:_:)``).
    private func parseReplacement(_ replacement: String) -> [ReplacementPart] {
        let r = Array(replacement.utf16)
        var parts: [ReplacementPart] = []
        var text: [UInt16] = []
        func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
        func isAlnum(_ c: UInt16) -> Bool { isDigit(c) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) }
        let groupCount = regex.numberOfCaptureGroups
        var k = 0
        while k < r.count {
            let c = r[k]
            if c == 0x5C { // backslash: the next char literally
                k += 1
                precondition(k < r.count, "character to be escaped is missing (replacement \(replacement))")
                text.append(r[k])
                k += 1
            } else if c == 0x24 { // $
                k += 1
                precondition(k < r.count, "Illegal group reference: group index is missing (replacement \(replacement))")
                if !text.isEmpty {
                    parts.append(.text(text))
                    text = []
                }
                if r[k] == 0x7B { // {name}
                    k += 1
                    let nameStart = k
                    while k < r.count, isAlnum(r[k]) { k += 1 }
                    let name = String(decoding: r[nameStart..<k], as: UTF16.self)
                    precondition(!name.isEmpty, "named capturing group has 0 length name (replacement \(replacement))")
                    precondition(k < r.count && r[k] == 0x7D, "named capturing group is missing trailing '}' (replacement \(replacement))")
                    precondition(!isDigit(r[nameStart]), "capturing group name {\(name)} starts with digit character")
                    precondition(groupNames.contains(name), "No group with name {\(name)}")
                    k += 1
                    parts.append(.named(name))
                } else {
                    precondition(isDigit(r[k]), "Illegal group reference (replacement \(replacement))")
                    var ref = Int(r[k] - 0x30)
                    k += 1
                    while k < r.count, isDigit(r[k]) {
                        let next = ref * 10 + Int(r[k] - 0x30)
                        if next > groupCount { break }
                        ref = next
                        k += 1
                    }
                    precondition(ref <= groupCount, "No group \(ref) (replacement \(replacement))")
                    parts.append(.group(ref))
                }
            } else {
                text.append(c)
                k += 1
            }
        }
        if !text.isEmpty { parts.append(.text(text)) }
        return parts
    }

    private func expand(_ parts: [ReplacementPart], _ m: NSTextCheckingResult, _ units: [UInt16], into out: inout [UInt16]) {
        for part in parts {
            let range: NSRange
            switch part {
            case .text(let t):
                out.append(contentsOf: t)
                continue
            case .group(let g): range = m.range(at: g)
            case .named(let name): range = m.range(withName: name)
            }
            if range.location != NSNotFound {
                out.append(contentsOf: units[range.location..<(range.location + range.length)])
            }
        }
    }

    /// Kotlin `replace(input) { match -> ... }`: the transform's result is used literally.
    func replace(_ input: String, transform: (KMatch) throws -> String) rethrows -> String {
        let units = Array(input.utf16)
        let ms = regex.matches(in: input, options: [], range: KRegex.nsRange(input))
        if ms.isEmpty { return input }
        var out: [UInt16] = []
        out.reserveCapacity(units.count)
        var last = 0
        for m in ms {
            out.append(contentsOf: units[last..<m.range.location])
            out.append(contentsOf: Array(try transform(KMatch(m, units, regex: self)).utf16))
            last = m.range.location + m.range.length
        }
        out.append(contentsOf: units[last...])
        return String(decoding: out, as: UTF16.self)
    }

    /// Kotlin `replaceFirst(input, replacement)` (same replacement syntax as ``replace(_:_:)``).
    func replaceFirst(_ input: String, _ replacement: String) -> String {
        guard let m = regex.firstMatch(in: input, options: [], range: KRegex.nsRange(input)) else { return input }
        let units = Array(input.utf16)
        var out: [UInt16] = []
        out.reserveCapacity(units.count)
        out.append(contentsOf: units[0..<m.range.location])
        expand(parseReplacement(replacement), m, units, into: &out)
        out.append(contentsOf: units[(m.range.location + m.range.length)...])
        return String(decoding: out, as: UTF16.self)
    }

    /// Kotlin `split(input, limit)`: unlike Java's String.split, empty strings (also trailing
    /// ones) are kept. `limit` 0 = no limit.
    func split(_ input: String, limit: Int = 0) -> [String] {
        precondition(limit >= 0, "Limit must be non-negative, but was \(limit)")
        let units = Array(input.utf16)
        let ms = regex.matches(in: input, options: [], range: KRegex.nsRange(input))
        if limit == 1 || ms.isEmpty { return [input] }
        var out: [String] = []
        var last = 0
        for m in ms {
            out.append(String(decoding: units[last..<m.range.location], as: UTF16.self))
            last = m.range.location + m.range.length
            if limit > 0 && out.count == limit - 1 { break }
        }
        out.append(String(decoding: units[last...], as: UTF16.self))
        return out
    }

}

/// Kotlin `MatchResult`.
struct KMatch: Sendable {
    /// The matched text (Kotlin `value`).
    let value: String
    /// UTF-16 offsets, half-open: Kotlin `range.first` = `range.lowerBound`,
    /// `range.last` = `range.upperBound - 1`.
    let range: Range<Int>
    /// Group texts, [0] = the whole match; "" for a group that did not participate
    /// (Kotlin `groupValues`).
    let groupValues: [String]
    /// Group texts, nil for a group that did not participate (Kotlin `groups[i]?.value`).
    let groups: [String?]
    /// Group ranges (UTF-16), nil when the group did not participate.
    let groupRanges: [Range<Int>?]
    private let named: [String: String?]

    fileprivate init(_ m: NSTextCheckingResult, _ units: [UInt16], regex: KRegex) {
        func text(_ r: NSRange) -> (String, Range<Int>)? {
            guard r.location != NSNotFound else { return nil }
            let range = r.location..<(r.location + r.length)
            return (String(decoding: units[range], as: UTF16.self), range)
        }
        var gs: [String?] = []
        var rs: [Range<Int>?] = []
        for i in 0..<m.numberOfRanges {
            let t = text(m.range(at: i))
            gs.append(t?.0)
            rs.append(t?.1)
        }
        groups = gs
        groupRanges = rs
        groupValues = gs.map { $0 ?? "" }
        value = gs.first.flatMap { $0 } ?? ""
        range = rs.first.flatMap { $0 } ?? 0..<0
        var nm: [String: String?] = [:]
        for name in regex.groupNames {
            nm[name] = text(m.range(withName: name))?.0
        }
        named = nm
    }

    /// Kotlin `groups[name]?.value`: a named group's text, nil if absent or unmatched.
    func group(named name: String) -> String? { named[name] ?? nil }
}

extension String {
    /// Kotlin `split(regex, limit)`: empty parts (also trailing ones) are kept.
    func split(_ regex: KRegex, limit: Int = 0) -> [String] { regex.split(self, limit: limit) }

    /// Kotlin `split(delimiter)` for one literal delimiter: empty parts are kept
    /// (`components(separatedBy:)` with UTF-16 matching).
    func kotlinSplit(_ delimiter: String) -> [String] {
        precondition(!delimiter.isEmpty, "use a non-empty delimiter")
        let h = Array(utf16), n = Array(delimiter.utf16)
        var out: [String] = []
        var last = 0, i = 0
        while i + n.count <= h.count {
            if h[i] == n[0] && Array(h[i..<(i + n.count)]) == n {
                out.append(String(decoding: h[last..<i], as: UTF16.self))
                i += n.count
                last = i
            } else {
                i += 1
            }
        }
        out.append(String(decoding: h[last...], as: UTF16.self))
        return out
    }
}
