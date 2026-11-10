import Foundation

// Helpers that reproduce Kotlin / JVM standard-library semantics exactly where Swift's own
// functions differ (sort stability, string order and case folding, rounding, trimming,
// collection builders that keep insertion order). Each one names the Kotlin function it
// mirrors. See CONVENTIONS.md for when to use which.

// MARK: - Comparators and stable sorting

/// The key type of a ``KComparator`` built from a key closure: `Comparable`, and (Swift 6.2+,
/// SE-0470) with a metatype a `@Sendable` closure may use. Every concrete type qualifies.
#if compiler(>=6.2)
typealias KComparable = Comparable & SendableMetatype
#else
typealias KComparable = Comparable
#endif

/// Kotlin `Comparator<T>` (`compareBy`, `thenBy`, `thenByDescending`, `reversed`):
/// `compare(a, b)` is negative, zero or positive.
///
/// ```swift
/// // compareBy<Session> { it.start }.thenBy { it.id }
/// let byStart = KComparator<Session>.by { $0.start }.thenBy { $0.id }
/// sessions.stableSorted(with: byStart)
/// // compareBy(String.CASE_INSENSITIVE_ORDER) { it.name }
/// rooms.stableSorted(with: .by(.caseInsensitiveOrder) { $0.name })
/// // private val NEAREST_FIRST = compareBy<Item>({ it.d ?: Long.MAX_VALUE }, { it.level ?: Int.MAX_VALUE })
/// static let NEAREST_FIRST = KComparator<Item>.by { $0.d ?? Int64.max }.thenBy { $0.level ?? Int.max }
/// ```
///
/// `Sendable` (closures are `@Sendable`), so comparators can be `static let` constants like
/// Kotlin's companion / top-level `val`s. Key closures therefore capture only Sendable values
/// (`let`s, not `var`s); key paths and plain closures need no change.
///
/// Key rules (as in Kotlin `compareValues`, see ``compareValues(_:_:)``): `String` keys
/// compare by UTF-16 code units (``javaCompare(_:_:)``, Kotlin `String.compareTo`), not
/// Swift's Unicode order; `Double` / `Float` keys use Java's total order (`-0.0 < 0.0`, NaN
/// last and equal to itself); `Bool` keys order `false` before `true`; optional keys put `nil`
/// first. This holds for every overload, also when the key type is generic.
struct KComparator<T>: Sendable {
    let compare: @Sendable (T, T) -> Int

    init(_ compare: @escaping @Sendable (T, T) -> Int) {
        self.compare = compare
    }

    func callAsFunction(_ a: T, _ b: T) -> Int { compare(a, b) }

    /// `a` sorts before `b` (for APIs that take a `(T, T) -> Bool`).
    var areInIncreasingOrder: (T, T) -> Bool {
        let c = compare
        return { c($0, $1) < 0 }
    }

    // MARK: by (compareBy)

    /// `compareBy { key }` for a `Comparable` key (Kotlin order for String / Double / Float keys).
    static func by<K: KComparable>(_ key: @escaping @Sendable (T) -> K) -> KComparator<T> {
        KComparator { compareValues(key($0), key($1)) }
    }

    /// `compareBy { key }` for a nullable key: nil sorts first.
    static func by<K: KComparable>(_ key: @escaping @Sendable (T) -> K?) -> KComparator<T> {
        KComparator { compareValues(key($0), key($1)) }
    }

    /// `compareBy { stringKey }`: UTF-16 order, like Kotlin `String.compareTo`.
    static func by(_ key: @escaping @Sendable (T) -> String) -> KComparator<T> {
        KComparator { javaCompare(key($0), key($1)) }
    }

    /// `compareBy { stringKey }` for a nullable string key: nil first, then UTF-16 order.
    static func by(_ key: @escaping @Sendable (T) -> String?) -> KComparator<T> {
        KComparator { compareValues(key($0), key($1)) }
    }

    /// `compareBy { boolKey }`: false before true.
    static func by(_ key: @escaping @Sendable (T) -> Bool) -> KComparator<T> {
        KComparator { compareValues(key($0), key($1)) }
    }

    /// `compareBy(comparator) { key }`.
    static func by<K>(_ comparator: KComparator<K>, _ key: @escaping @Sendable (T) -> K) -> KComparator<T> {
        KComparator { comparator.compare(key($0), key($1)) }
    }

    // MARK: thenBy

    /// `thenComparing(other)`.
    func then(_ other: KComparator<T>) -> KComparator<T> {
        let first = compare
        return KComparator { a, b in
            let c = first(a, b)
            return c != 0 ? c : other.compare(a, b)
        }
    }

    func thenBy<K: KComparable>(_ key: @escaping @Sendable (T) -> K) -> KComparator<T> { then(.by(key)) }
    func thenBy<K: KComparable>(_ key: @escaping @Sendable (T) -> K?) -> KComparator<T> { then(.by(key)) }
    func thenBy(_ key: @escaping @Sendable (T) -> String) -> KComparator<T> { then(.by(key)) }
    func thenBy(_ key: @escaping @Sendable (T) -> String?) -> KComparator<T> { then(.by(key)) }
    func thenBy(_ key: @escaping @Sendable (T) -> Bool) -> KComparator<T> { then(.by(key)) }
    /// `thenBy(comparator) { key }`.
    func thenBy<K>(_ comparator: KComparator<K>, _ key: @escaping @Sendable (T) -> K) -> KComparator<T> {
        then(.by(comparator, key))
    }

    func thenByDescending<K: KComparable>(_ key: @escaping @Sendable (T) -> K) -> KComparator<T> { then(KComparator.by(key).reversed()) }
    func thenByDescending<K: KComparable>(_ key: @escaping @Sendable (T) -> K?) -> KComparator<T> { then(KComparator.by(key).reversed()) }
    func thenByDescending(_ key: @escaping @Sendable (T) -> String) -> KComparator<T> { then(KComparator.by(key).reversed()) }
    func thenByDescending(_ key: @escaping @Sendable (T) -> String?) -> KComparator<T> { then(KComparator.by(key).reversed()) }
    func thenByDescending(_ key: @escaping @Sendable (T) -> Bool) -> KComparator<T> { then(KComparator.by(key).reversed()) }

    /// `reversed()`.
    func reversed() -> KComparator<T> {
        let c = compare
        return KComparator { c($1, $0) }
    }
}

extension KComparator where T: KComparable {
    /// `naturalOrder()`: Kotlin `compareTo` (UTF-16 order for strings, Java's total order for
    /// doubles), via ``compareValues(_:_:)``.
    static var naturalOrder: KComparator<T> { KComparator { compareValues($0, $1) } }
}

extension KComparator where T == String {
    /// `String.CASE_INSENSITIVE_ORDER` (see ``javaCaseInsensitiveCompare(_:_:)``).
    static var caseInsensitiveOrder: KComparator<String> { KComparator { javaCaseInsensitiveCompare($0, $1) } }

    /// Kotlin `naturalOrder<String>()` / `String.compareTo`: UTF-16 code-unit order (the same
    /// as ``naturalOrder``).
    static var javaOrder: KComparator<String> { KComparator { javaCompare($0, $1) } }
}

/// Kotlin `compareBy { key }` as a free function.
func compareBy<T, K: KComparable>(_ key: @escaping @Sendable (T) -> K) -> KComparator<T> { .by(key) }

/// Kotlin `compareValues(a, b)` for `Comparable` values: -1, 0 or 1, with Kotlin's
/// `compareTo` for the types whose Swift `<` differs: `String` by UTF-16 units
/// (``javaCompare(_:_:)``), `Double` / `Float` by Java's total order
/// (``javaDoubleCompare(_:_:)``). The check is on the type, so generic callers (`by<K>`,
/// `stableSorted(on:)`, `naturalOrder`, optional keys) get Kotlin's order too. Any other type
/// uses its `<`.
func compareValues<K: Comparable>(_ a: K, _ b: K) -> Int {
    if K.self == String.self { return javaCompare(a as! String, b as! String).signum() }
    if K.self == Double.self { return javaDoubleCompare(a as! Double, b as! Double) }
    if K.self == Float.self { return javaFloatCompare(a as! Float, b as! Float) }
    return a < b ? -1 : (b < a ? 1 : 0)
}

/// Kotlin `compareValues(a, b)` for nullable values: nil is less than any value.
func compareValues<K: Comparable>(_ a: K?, _ b: K?) -> Int {
    switch (a, b) {
    case (nil, nil): return 0
    case (nil, _): return -1
    case (_, nil): return 1
    case let (x?, y?): return compareValues(x, y)
    }
}

/// `compareValues` for strings: UTF-16 order (Kotlin `String.compareTo`).
func compareValues(_ a: String, _ b: String) -> Int { javaCompare(a, b).signum() }

/// `compareValues` for nullable strings: nil first, then UTF-16 order.
func compareValues(_ a: String?, _ b: String?) -> Int {
    switch (a, b) {
    case (nil, nil): return 0
    case (nil, _): return -1
    case (_, nil): return 1
    case let (x?, y?): return javaCompare(x, y).signum()
    }
}

/// `compareValues` for booleans (Kotlin `Boolean.compareTo`): false < true.
func compareValues(_ a: Bool, _ b: Bool) -> Int { a == b ? 0 : (a ? 1 : -1) }

/// Java `Double.compare(a, b)` (Kotlin `Double.compareTo` on boxed / generic values, which
/// `sortedBy`, `compareBy` and `maxByOrNull` use): a total order with `-0.0 < 0.0` and NaN
/// greater than everything (`+infinity` included) and equal to itself. Swift's `<` is IEEE:
/// NaN is unordered and `-0.0 == 0.0`, which scrambles a sort with a NaN key.
func javaDoubleCompare(_ a: Double, _ b: Double) -> Int {
    if a < b { return -1 }
    if a > b { return 1 }
    // Equal, a zero pair, or a NaN involved: Double.doubleToLongBits order (canonical NaN).
    let x = a.isNaN ? Int64(0x7FF8_0000_0000_0000) : Int64(bitPattern: a.bitPattern)
    let y = b.isNaN ? Int64(0x7FF8_0000_0000_0000) : Int64(bitPattern: b.bitPattern)
    return x == y ? 0 : (x < y ? -1 : 1)
}

/// Java `Float.compare(a, b)` (see ``javaDoubleCompare(_:_:)``).
func javaFloatCompare(_ a: Float, _ b: Float) -> Int {
    if a < b { return -1 }
    if a > b { return 1 }
    let x = a.isNaN ? Int32(0x7FC0_0000) : Int32(bitPattern: a.bitPattern)
    let y = b.isNaN ? Int32(0x7FC0_0000) : Int32(bitPattern: b.bitPattern)
    return x == y ? 0 : (x < y ? -1 : 1)
}

extension Sequence {
    /// Kotlin `sortedWith(comparator)`: a STABLE sort (equal elements keep their order).
    /// For an ad-hoc comparator: `stableSorted(with: KComparator { a, b in ... })`.
    func stableSorted(with comparator: KComparator<Element>) -> [Element] {
        stableSortedComparing(comparator.compare)
    }

    /// Stable sort with an Int-returning comparator (shared implementation).
    fileprivate func stableSortedComparing(_ compare: (Element, Element) throws -> Int) rethrows -> [Element] {
        // Tie-break on the original position, which makes any sort algorithm stable.
        try enumerated().sorted { a, b in
            let c = try compare(a.element, b.element)
            return c != 0 ? c < 0 : a.offset < b.offset
        }.map(\.element)
    }

    /// A STABLE sort with a Swift-style `areInIncreasingOrder` predicate (Kotlin
    /// `sortedWith(compareBy(...))` written as tuples: `stableSorted { ($0.a, $0.b) < ($1.a, $1.b) }`).
    func stableSorted(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> [Element] {
        try enumerated().sorted { a, b in
            if try areInIncreasingOrder(a.element, b.element) { return true }
            if try areInIncreasingOrder(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Kotlin `sortedBy { key }` (stable; Kotlin order for String / Double / Float keys, see
    /// ``compareValues(_:_:)``).
    func stableSorted<K: Comparable>(on key: (Element) throws -> K) rethrows -> [Element] {
        try stableSortedComparing { compareValues(try key($0), try key($1)) }
    }

    /// Kotlin `sortedBy { key }` with a nullable key (stable, nil first).
    func stableSorted<K: Comparable>(on key: (Element) throws -> K?) rethrows -> [Element] {
        try stableSortedComparing { compareValues(try key($0), try key($1)) }
    }

    /// Kotlin `sortedBy { stringKey }` (stable, UTF-16 order).
    func stableSorted(on key: (Element) throws -> String) rethrows -> [Element] {
        try stableSortedComparing { javaCompare(try key($0), try key($1)) }
    }

    /// Kotlin `sortedByDescending { key }` (stable; Kotlin order, as ``stableSorted(on:)``).
    func stableSortedDescending<K: Comparable>(on key: (Element) throws -> K) rethrows -> [Element] {
        try stableSortedComparing { compareValues(try key($1), try key($0)) }
    }

    /// Kotlin `sortedByDescending { key }` with a nullable key (stable, nil last).
    func stableSortedDescending<K: Comparable>(on key: (Element) throws -> K?) rethrows -> [Element] {
        try stableSortedComparing { compareValues(try key($1), try key($0)) }
    }

    /// Kotlin `sortedByDescending { stringKey }` (stable, UTF-16 order).
    func stableSortedDescending(on key: (Element) throws -> String) rethrows -> [Element] {
        try stableSortedComparing { javaCompare(try key($1), try key($0)) }
    }

    /// Kotlin `minWithOrNull(comparator)`: the FIRST minimal element.
    func min(with comparator: KComparator<Element>) -> Element? {
        var best: Element?
        for e in self {
            if let b = best {
                if comparator.compare(e, b) < 0 { best = e }
            } else {
                best = e
            }
        }
        return best
    }

    /// Kotlin `maxWithOrNull(comparator)`: the FIRST maximal element.
    func max(with comparator: KComparator<Element>) -> Element? {
        var best: Element?
        for e in self {
            if let b = best {
                if comparator.compare(e, b) > 0 { best = e }
            } else {
                best = e
            }
        }
        return best
    }
}

extension Sequence where Element == String {
    /// Kotlin `sorted()` on strings: stable, UTF-16 order.
    func javaSorted() -> [String] { stableSorted(with: .javaOrder) }
}

// MARK: - String order and case

/// Kotlin/Java `String.compareTo`: lexicographic over UTF-16 code units; the difference of the
/// first differing units, else the difference of the lengths.
func javaCompare(_ a: String, _ b: String) -> Int {
    var i1 = a.utf16.makeIterator()
    var i2 = b.utf16.makeIterator()
    while true {
        switch (i1.next(), i2.next()) {
        case (nil, nil): return 0
        case (nil, _): return -1 - remaining(&i2)
        case (_, nil): return 1 + remaining(&i1)
        case let (c1?, c2?):
            if c1 != c2 { return Int(c1) - Int(c2) }
        }
    }
}

private func remaining(_ it: inout String.UTF16View.Iterator) -> Int {
    var n = 0
    while it.next() != nil { n += 1 }
    return n
}

/// `String.CASE_INSENSITIVE_ORDER` (Android's implementation): per UTF-16 unit, compare as is,
/// then uppercased, then lowercased of the uppercased (Java `Character.toUpperCase(char)` /
/// `toLowerCase(char)`, simple one-to-one case mapping); else the length difference.
///
/// Unlike Swift's `caseInsensitiveCompare` / `localizedStandardCompare`, there is no locale,
/// no normalization and no grapheme logic: "é" (U+00E9) and "e\u{301}" are different.
func javaCaseInsensitiveCompare(_ a: String, _ b: String) -> Int {
    var i1 = a.utf16.makeIterator()
    var i2 = b.utf16.makeIterator()
    while true {
        switch (i1.next(), i2.next()) {
        case (nil, nil): return 0
        case (nil, _): return -1 - remaining(&i2)
        case (_, nil): return 1 + remaining(&i1)
        case let (c1?, c2?):
            if c1 == c2 { continue }
            let u1 = javaToUpperCase(c1), u2 = javaToUpperCase(c2)
            if u1 == u2 { continue }
            let l1 = javaToLowerCase(u1), l2 = javaToLowerCase(u2)
            if l1 != l2 { return Int(l1) - Int(l2) }
        }
    }
}

/// Kotlin `a == b` for strings: the same UTF-16 units. Swift's `==` (and `Hashable`, so `Set`,
/// dictionary keys, `distinct()`, `OrderedMap`) treats canonically equivalent strings as equal:
/// "Jos\u{E9}" == "Jose\u{301}" in Swift, not in Kotlin.
func kotlinEquals(_ a: String, _ b: String) -> Bool { a.utf16.elementsEqual(b.utf16) }

/// Kotlin `a.equals(b, ignoreCase = true)` (per UTF-16 unit, simple case mapping).
func kotlinEqualsIgnoreCase(_ a: String, _ b: String) -> Bool {
    a.utf16.count == b.utf16.count && javaCaseInsensitiveCompare(a, b) == 0
}

/// Java `Character.toUpperCase(char)`: the simple uppercase mapping of one UTF-16 unit
/// (unchanged when there is none, or when it is not a single BMP unit; surrogates unchanged).
func javaToUpperCase(_ c: UInt16) -> UInt16 {
    if c < 0x80 {
        return (c >= 0x61 && c <= 0x7A) ? c - 0x20 : c
    }
    guard let s = Unicode.Scalar(c) else { return c } // a surrogate half
    return singleBMP(s.properties.uppercaseMapping)
        ?? singleBMP(s.properties.titlecaseMapping) // e.g. U+1FB3: full "ΑΙ", simple U+1FBC
        ?? c
}

/// Java `Character.toLowerCase(char)`: the simple lowercase mapping of one UTF-16 unit.
func javaToLowerCase(_ c: UInt16) -> UInt16 {
    if c < 0x80 {
        return (c >= 0x41 && c <= 0x5A) ? c + 0x20 : c
    }
    guard let s = Unicode.Scalar(c) else { return c }
    let m = s.properties.lowercaseMapping
    if let one = singleBMP(m) { return one }
    // Only U+0130 has a multi-scalar lowercase ("i̇"); its simple mapping is the first ("i").
    if let first = m.unicodeScalars.first, first.value < 0x10000, m.unicodeScalars.count > 1, c == 0x130 {
        return UInt16(first.value)
    }
    return c
}

private func singleBMP(_ s: String) -> UInt16? {
    let u = s.utf16
    guard u.count == 1, let c = u.first else { return nil }
    return c
}

// MARK: - Whitespace, trim, blank

/// Kotlin `Char.isWhitespace()` on the JVM/Android: `Character.isWhitespace(c) ||
/// Character.isSpaceChar(c)`, i.e. U+0009–U+000D, U+001C–U+001F and every space/line/paragraph
/// separator (U+0020, U+00A0, U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000).
/// Not U+0085, U+200B or U+FEFF.
func isKotlinWhitespace(_ c: UInt16) -> Bool {
    switch c {
    case 0x09...0x0D, 0x1C...0x20: return true
    case 0x00A0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000: return true
    default: return false
    }
}

extension String {
    /// Kotlin `String.trim()`: removes leading and trailing chars for which Kotlin
    /// `Char.isWhitespace()` is true (``isKotlinWhitespace(_:)``, includes NBSP).
    ///
    /// NOTE: this is Kotlin's `trim()`, not Java's `String.trim()` (which strips chars <= U+0020
    /// only: see ``javaTrim()``). Kotlin code calling `s.trim()` gets Kotlin's.
    func kotlinTrim() -> String {
        trimmingUTF16(isKotlinWhitespace)
    }

    /// Kotlin `trimStart()`.
    func kotlinTrimStart() -> String {
        let u = Array(utf16)
        var i = 0
        while i < u.count, isKotlinWhitespace(u[i]) { i += 1 }
        return i == 0 ? self : String(decoding: u[i...], as: UTF16.self)
    }

    /// Kotlin `trimEnd()`.
    func kotlinTrimEnd() -> String {
        let u = Array(utf16)
        var j = u.count
        while j > 0, isKotlinWhitespace(u[j - 1]) { j -= 1 }
        return j == u.count ? self : String(decoding: u[..<j], as: UTF16.self)
    }

    /// Java `java.lang.String.trim()`: strips leading and trailing chars <= U+0020.
    func javaTrim() -> String {
        trimmingUTF16 { $0 <= 0x20 }
    }

    private func trimmingUTF16(_ strip: (UInt16) -> Bool) -> String {
        let u = Array(utf16)
        var i = 0, j = u.count
        while i < j, strip(u[i]) { i += 1 }
        while j > i, strip(u[j - 1]) { j -= 1 }
        if i == 0 && j == u.count { return self }
        return String(decoding: u[i..<j], as: UTF16.self)
    }

    /// Kotlin `isBlank()`: empty, or every char is Kotlin whitespace.
    var isBlank: Bool { utf16.allSatisfy(isKotlinWhitespace) }

    /// Kotlin `isNotBlank()`.
    var isNotBlank: Bool { !isBlank }

    /// Kotlin `s.takeIf { it.isNotBlank() }`.
    func takeIfNotBlank() -> String? { isBlank ? nil : self }

    /// Kotlin `ifBlank { default }`.
    func ifBlank(_ defaultValue: () -> String) -> String { isBlank ? defaultValue() : self }

    /// Kotlin `ifEmpty { default }`.
    func ifEmpty(_ defaultValue: () -> String) -> String { isEmpty ? defaultValue() : self }
}

// MARK: - UTF-16 string helpers (Kotlin indexes UTF-16 code units)

extension String {
    /// Kotlin `length`: the number of UTF-16 code units.
    var kotlinLength: Int { utf16.count }

    /// Kotlin `substring(startIndex, endIndex)` over UTF-16 offsets. Traps when out of range,
    /// like Kotlin throws `StringIndexOutOfBoundsException`.
    func kotlinSubstring(_ startIndex: Int, _ endIndex: Int? = nil) -> String {
        let u = Array(utf16)
        let end = endIndex ?? u.count
        precondition(startIndex >= 0 && startIndex <= end && end <= u.count,
                     "begin \(startIndex), end \(end), length \(u.count)")
        return String(decoding: u[startIndex..<end], as: UTF16.self)
    }

    /// Kotlin `take(n)`: the first `n` UTF-16 units (all of them if shorter).
    func kotlinTake(_ n: Int) -> String {
        precondition(n >= 0, "Requested character count \(n) is less than zero.")
        let u = Array(utf16)
        return n >= u.count ? self : String(decoding: u[..<n], as: UTF16.self)
    }

    /// Kotlin `takeLast(n)`.
    func kotlinTakeLast(_ n: Int) -> String {
        precondition(n >= 0, "Requested character count \(n) is less than zero.")
        let u = Array(utf16)
        return n >= u.count ? self : String(decoding: u[(u.count - n)...], as: UTF16.self)
    }

    /// Kotlin `drop(n)`.
    func kotlinDrop(_ n: Int) -> String {
        precondition(n >= 0, "Requested character count \(n) is less than zero.")
        let u = Array(utf16)
        return n >= u.count ? "" : String(decoding: u[n...], as: UTF16.self)
    }

    /// Kotlin `indexOf(other, startIndex)`: the UTF-16 offset of the first occurrence, or -1.
    /// An empty `other` is found at `startIndex` (clamped to 0...length).
    func kotlinIndexOf(_ other: String, from startIndex: Int = 0) -> Int {
        let h = Array(utf16), n = Array(other.utf16)
        let start = Swift.max(0, startIndex)
        if n.isEmpty { return Swift.min(start, h.count) }
        guard n.count <= h.count else { return -1 }
        var i = start
        while i <= h.count - n.count {
            if h[i] == n[0] {
                var k = 1
                while k < n.count && h[i + k] == n[k] { k += 1 }
                if k == n.count { return i }
            }
            i += 1
        }
        return -1
    }

    /// Kotlin `lastIndexOf(other)`: UTF-16 offset of the last occurrence, or -1.
    func kotlinLastIndexOf(_ other: String) -> Int {
        let h = Array(utf16), n = Array(other.utf16)
        if n.isEmpty { return h.count }
        guard n.count <= h.count else { return -1 }
        var i = h.count - n.count
        while i >= 0 {
            if Array(h[i..<(i + n.count)]) == n { return i }
            i -= 1
        }
        return -1
    }

    /// Kotlin `substringBefore(delimiter, missingDelimiterValue = this)`.
    func substringBefore(_ delimiter: String, missing: String? = nil) -> String {
        let i = kotlinIndexOf(delimiter)
        return i < 0 ? (missing ?? self) : kotlinSubstring(0, i)
    }

    /// Kotlin `substringAfter(delimiter, missingDelimiterValue = this)`.
    func substringAfter(_ delimiter: String, missing: String? = nil) -> String {
        let i = kotlinIndexOf(delimiter)
        return i < 0 ? (missing ?? self) : kotlinSubstring(i + delimiter.utf16.count)
    }

    /// Kotlin `substringBeforeLast(delimiter, missingDelimiterValue = this)`.
    func substringBeforeLast(_ delimiter: String, missing: String? = nil) -> String {
        let i = kotlinLastIndexOf(delimiter)
        return i < 0 ? (missing ?? self) : kotlinSubstring(0, i)
    }

    /// Kotlin `substringAfterLast(delimiter, missingDelimiterValue = this)`.
    func substringAfterLast(_ delimiter: String, missing: String? = nil) -> String {
        let i = kotlinLastIndexOf(delimiter)
        return i < 0 ? (missing ?? self) : kotlinSubstring(i + delimiter.utf16.count)
    }

    /// Kotlin `replaceFirst(oldValue, newValue)`: replaces the first literal occurrence
    /// (UTF-16 match, no Unicode equivalence).
    func replaceFirst(_ oldValue: String, _ newValue: String) -> String {
        let i = kotlinIndexOf(oldValue)
        guard i >= 0 else { return self }
        return kotlinSubstring(0, i) + newValue + kotlinSubstring(i + oldValue.utf16.count)
    }

    /// Kotlin `replace(oldValue, newValue)`: replaces every literal occurrence, left to right
    /// (UTF-16 match, no Unicode equivalence).
    func kotlinReplace(_ oldValue: String, _ newValue: String) -> String {
        let h = Array(utf16), n = Array(oldValue.utf16), r = Array(newValue.utf16)
        var out: [UInt16] = []
        out.reserveCapacity(h.count)
        if n.isEmpty {
            // Kotlin inserts newValue before every char and at the end.
            for c in h { out += r; out.append(c) }
            out += r
            return String(decoding: out, as: UTF16.self)
        }
        var i = 0
        while i < h.count {
            if i + n.count <= h.count && h[i] == n[0] && Array(h[i..<(i + n.count)]) == n {
                out += r
                i += n.count
            } else {
                out.append(h[i])
                i += 1
            }
        }
        return String(decoding: out, as: UTF16.self)
    }

    /// Kotlin `startsWith(prefix)`: compares UTF-16 units. Swift's `hasPrefix` compares
    /// Characters with canonical equivalence: `"Jose\u{301}".hasPrefix("Jose")` is false, Kotlin's
    /// `startsWith` is true; `"Jos\u{E9}".hasPrefix("Jose\u{301}")` is true, Kotlin's false.
    func kotlinStartsWith(_ prefix: String) -> Bool { utf16.starts(with: prefix.utf16) }

    /// Kotlin `endsWith(suffix)` (UTF-16 units; see ``kotlinStartsWith(_:)``).
    func kotlinEndsWith(_ suffix: String) -> Bool {
        let n = suffix.utf16.count
        return n <= utf16.count && utf16.suffix(n).elementsEqual(suffix.utf16)
    }

    /// Kotlin `contains(other)` / `other in s` for strings (UTF-16 units). Swift's
    /// `contains(_: StringProtocol)` matches whole Characters: `"Jose\u{301}".contains("e")` is
    /// false there, true in Kotlin.
    func kotlinContains(_ other: String) -> Bool { kotlinIndexOf(other) >= 0 }

    /// Kotlin `removePrefix(prefix)`.
    func removePrefix(_ prefix: String) -> String {
        utf16.starts(with: prefix.utf16) ? kotlinDrop(prefix.utf16.count) : self
    }

    /// Kotlin `removeSuffix(suffix)`.
    func removeSuffix(_ suffix: String) -> String {
        let u = Array(utf16), s = Array(suffix.utf16)
        guard s.count <= u.count, Array(u[(u.count - s.count)...]) == s else { return self }
        return String(decoding: u[..<(u.count - s.count)], as: UTF16.self)
    }

    /// Kotlin `padStart(length, padChar)`: pads to `length` UTF-16 units.
    func padStart(_ length: Int, _ padChar: Character = " ") -> String {
        let n = length - utf16.count
        return n <= 0 ? self : String(repeating: String(padChar), count: n) + self
    }

    /// Kotlin `padEnd(length, padChar)`.
    func padEnd(_ length: Int, _ padChar: Character = " ") -> String {
        let n = length - utf16.count
        return n <= 0 ? self : self + String(repeating: String(padChar), count: n)
    }
}

// MARK: - Numbers

extension Double {
    /// Kotlin `roundToInt()` (Java `Math.round`): rounds half UP, also for negatives
    /// (-2.5 -> -2, 2.5 -> 3), saturating at the Int32 range (Kotlin `Int` is 32-bit).
    /// Kotlin throws for NaN; this returns 0 instead (never crash the UI on a bad reading).
    func kotlinRoundToInt() -> Int {
        guard !isNaN else { return 0 }
        let r = javaRoundHalfUp(self)
        if r >= Double(Int32.max) { return Int(Int32.max) }
        if r <= Double(Int32.min) { return Int(Int32.min) }
        return Int(r)
    }

    /// Kotlin `roundToLong()` (Java `Math.round(double)`): half up, saturating at Int64.
    /// NaN -> 0 (Kotlin throws).
    func kotlinRoundToLong() -> Int64 {
        guard !isNaN else { return 0 }
        let r = javaRoundHalfUp(self)
        if r >= 9.223372036854775807e18 { return Int64.max }
        if r <= -9.223372036854775808e18 { return Int64.min }
        return Int64(r)
    }

    /// Kotlin `kotlin.math.round(x)` (Java `Math.rint`): half to EVEN (2.5 -> 2.0, 3.5 -> 4.0).
    func kotlinRound() -> Double { rounded(.toNearestOrEven) }

    /// Kotlin `Double.toInt()`: truncates toward zero, saturates at the Int32 range, NaN -> 0.
    func kotlinToInt() -> Int {
        if isNaN { return 0 }
        if self >= Double(Int32.max) { return Int(Int32.max) }
        if self <= Double(Int32.min) { return Int(Int32.min) }
        return Int(self)
    }

    /// Kotlin `Double.toLong()`: truncates toward zero, saturates at Int64, NaN -> 0.
    func kotlinToLong() -> Int64 {
        if isNaN { return 0 }
        if self >= 9.223372036854775807e18 { return Int64.max }
        if self <= -9.223372036854775808e18 { return Int64.min }
        return Int64(self)
    }
}

extension Float {
    /// Kotlin `Float.roundToInt()` (Java `Math.round(float)`): half up, saturating at Int32,
    /// NaN -> 0 (Kotlin throws).
    func kotlinRoundToInt() -> Int {
        guard !isNaN else { return 0 }
        let f = rounded(.down)
        let r = (self - f) >= 0.5 ? f + 1 : f
        if r >= Float(Int32.max) { return Int(Int32.max) }
        if r <= Float(Int32.min) { return Int(Int32.min) }
        return Int(r)
    }
}

/// `floor(x + 0.5)` computed without the `x + 0.5` rounding error (Java 7+ `Math.round`:
/// 0.49999999999999994 rounds to 0, not 1).
private func javaRoundHalfUp(_ x: Double) -> Double {
    let f = x.rounded(.down)
    return (x - f) >= 0.5 ? f + 1 : f
}

/// Java `Math.floorMod(x, y)`: the remainder with the sign of `y` (floorMod(-1, 60) == 59).
func floorMod<T: BinaryInteger>(_ x: T, _ y: T) -> T {
    let r = x % y
    return (r != 0 && ((r < 0) != (y < 0))) ? r + y : r
}

/// Java `Math.floorDiv(x, y)`: division rounding toward negative infinity.
func floorDiv<T: BinaryInteger>(_ x: T, _ y: T) -> T {
    let q = x / y
    return (x % y != 0 && ((x < 0) != (y < 0))) ? q - 1 : q
}

extension Comparable {
    /// Kotlin `coerceIn(range)`.
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }

    /// Kotlin `coerceIn(min, max)`. Kotlin throws when `min > max`; this traps.
    func coerceIn(_ minimum: Self, _ maximum: Self) -> Self {
        precondition(minimum <= maximum, "Cannot coerce value to an empty range: maximum \(maximum) is less than minimum \(minimum).")
        return Swift.min(Swift.max(self, minimum), maximum)
    }

    /// Kotlin `coerceAtLeast(min)`.
    func coerceAtLeast(_ minimum: Self) -> Self { Swift.max(self, minimum) }

    /// Kotlin `coerceAtMost(max)`.
    func coerceAtMost(_ maximum: Self) -> Self { Swift.min(self, maximum) }
}

// MARK: - Collections

extension Sequence where Element: Hashable {
    /// Kotlin `distinct()`: first occurrences, in order.
    func distinct() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Sequence {
    /// Kotlin `distinctBy { key }`: the first element for each key, in order.
    func distinctBy<K: Hashable>(_ key: (Element) throws -> K) rethrows -> [Element] {
        var seen = Set<K>()
        var out: [Element] = []
        for e in self where seen.insert(try key(e)).inserted { out.append(e) }
        return out
    }

    /// Kotlin `associateBy { key }`: LAST element wins for a repeated key (at the key's first
    /// position).
    func associateBy<K: Hashable>(_ key: (Element) throws -> K) rethrows -> OrderedMap<K, Element> {
        var out = OrderedMap<K, Element>()
        for e in self { out.updateValue(e, forKey: try key(e)) }
        return out
    }

    /// Kotlin `associateBy({ key }, { value })` (last wins).
    func associateBy<K: Hashable, V>(_ key: (Element) throws -> K, _ value: (Element) throws -> V) rethrows -> OrderedMap<K, V> {
        var out = OrderedMap<K, V>()
        for e in self { out.updateValue(try value(e), forKey: try key(e)) }
        return out
    }

    /// Kotlin `associate { k to v }` (last wins).
    func associate<K: Hashable, V>(_ transform: (Element) throws -> (K, V)) rethrows -> OrderedMap<K, V> {
        var out = OrderedMap<K, V>()
        for e in self {
            let (k, v) = try transform(e)
            out.updateValue(v, forKey: k)
        }
        return out
    }

    /// Kotlin `groupBy { key }`: keys in first-seen order, elements in order.
    func groupBy<K: Hashable>(_ key: (Element) throws -> K) rethrows -> OrderedMap<K, [Element]> {
        var out = OrderedMap<K, [Element]>()
        for e in self {
            let k = try key(e)
            if let i = out.index(forKey: k) {
                var list = out.element(at: i).value
                list.append(e)
                out.updateValue(list, forKey: k)
            } else {
                out.updateValue([e], forKey: k)
            }
        }
        return out
    }

    /// Kotlin `partition { predicate }`: (matching, not matching), both in order.
    func kotlinPartition(_ predicate: (Element) throws -> Bool) rethrows -> (first: [Element], second: [Element]) {
        var a: [Element] = [], b: [Element] = []
        for e in self {
            if try predicate(e) { a.append(e) } else { b.append(e) }
        }
        return (a, b)
    }
}

extension Sequence where Element: Hashable {
    /// Kotlin `associateWith { value }` (keys are the elements; last wins).
    func associateWith<V>(_ value: (Element) throws -> V) rethrows -> OrderedMap<Element, V> {
        var out = OrderedMap<Element, V>()
        for e in self { out.updateValue(try value(e), forKey: e) }
        return out
    }
}

extension Array {
    /// Kotlin `getOrNull(index)`.
    func getOrNull(_ index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }

    /// Kotlin `zipWithNext()`: each element with its successor.
    func zipWithNext() -> [(Element, Element)] {
        guard count >= 2 else { return [] }
        return (0..<(count - 1)).map { (self[$0], self[$0 + 1]) }
    }

    /// Kotlin `zipWithNext { a, b -> ... }`.
    func zipWithNext<R>(_ transform: (Element, Element) throws -> R) rethrows -> [R] {
        guard count >= 2 else { return [] }
        return try (0..<(count - 1)).map { try transform(self[$0], self[$0 + 1]) }
    }

    /// Kotlin `windowed(size, step, partialWindows)`.
    func windowed(_ size: Int, step: Int = 1, partialWindows: Bool = false) -> [[Element]] {
        precondition(size > 0 && step > 0, "size \(size) and step \(step) must be greater than zero.")
        var out: [[Element]] = []
        var i = 0
        while i < count {
            let end = i + size
            if end > count {
                if partialWindows { out.append(Array(self[i..<count])) } else { break }
            } else {
                out.append(Array(self[i..<end]))
            }
            i += step
        }
        return out
    }

    /// Kotlin `chunked(size)`.
    func chunked(_ size: Int) -> [[Element]] { windowed(size, step: size, partialWindows: true) }

    /// Kotlin `ifEmpty { default }`.
    func ifEmpty(_ defaultValue: () -> [Element]) -> [Element] { isEmpty ? defaultValue() : self }
}
