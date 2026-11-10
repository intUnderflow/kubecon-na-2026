import Foundation

/// Case- and diacritic-insensitive matching for search ("krepinsky" finds
/// "Filip Křepinský", "255 a-c" finds "255 A–C", "o'leary" finds "O’Leary").
/// Pure Foundation.
///
/// Kotlin -> Swift: `lowercase(Locale.ROOT)` -> `lowercased()`; `Normalizer.normalize(NFD)` ->
/// `decomposedStringWithCanonicalMapping`; the fold table and `contains` work on UTF-16 units,
/// like Kotlin's `Char`s and `String.contains`.
enum TextMatch {
    private static let MARKS = KRegex("\\p{Mn}+")
    private static let SPACES = KRegex("\\s+")

    /// Letters that NFD doesn't split into base + mark (keys are single UTF-16 units, like
    /// Kotlin's `Char` keys).
    private static let FOLD: [UInt16: [UInt16]] = {
        let pairs: [(String, String)] = [
            ("ł", "l"), ("ø", "o"), ("æ", "ae"), ("œ", "oe"), ("ß", "ss"), ("đ", "d"), ("ð", "d"),
            ("þ", "th"), ("ı", "i"), ("ħ", "h"), ("ŀ", "l"),
            ("’", "'"), ("‘", "'"), ("ʼ", "'"), ("“", "\""), ("”", "\""),
            ("–", "-"), ("—", "-"), ("‑", "-"), ("−", "-"),
        ]
        var out: [UInt16: [UInt16]] = [:]
        for (k, v) in pairs {
            let units = Array(k.utf16)
            precondition(units.count == 1, "FOLD keys are single UTF-16 units")
            out[units[0]] = Array(v.utf16)
        }
        return out
    }()

    /// Lower-cases, strips diacritics and folds look-alike punctuation.
    static func normalize(_ s: String) -> String {
        if s.isEmpty { return s }
        let lower = s.lowercased()
        let stripped = MARKS.replace(lower.decomposedStringWithCanonicalMapping, "")
        let units = Array(stripped.utf16)
        if !units.contains(where: { FOLD[$0] != nil }) { return stripped }
        var out: [UInt16] = []
        out.reserveCapacity(units.count + 4)
        for c in units {
            if let f = FOLD[c] {
                out.append(contentsOf: f)
            } else {
                out.append(c)
            }
        }
        return String(decoding: out, as: UTF16.self)
    }

    /// The web's `q.toLowerCase().split(/\s+/).filter(Boolean)`, normalised.
    static func terms(_ query: String) -> [String] {
        normalize(query.kotlinTrim()).split(SPACES).filter { !$0.isEmpty }
    }

    /// True when every term occurs in `normalizedHaystack` (already passed through ``normalize(_:)``).
    /// UTF-16 containment (Kotlin `String.contains`), not Swift's Character matching.
    static func matchesAll(_ normalizedHaystack: String, _ terms: [String]) -> Bool {
        if terms.isEmpty { return true }
        let h = Array(normalizedHaystack.utf16)
        return terms.allSatisfy { containsUnits(h, Array($0.utf16)) }
    }

    /// `needle` occurs in `haystack` (UTF-16 units; an empty needle always does).
    private static func containsUnits(_ haystack: [UInt16], _ needle: [UInt16]) -> Bool {
        if needle.isEmpty { return true }
        if needle.count > haystack.count { return false }
        let first = needle[0]
        var i = 0
        let last = haystack.count - needle.count
        while i <= last {
            if haystack[i] == first {
                var k = 1
                while k < needle.count && haystack[i + k] == needle[k] { k += 1 }
                if k == needle.count { return true }
            }
            i += 1
        }
        return false
    }
}
