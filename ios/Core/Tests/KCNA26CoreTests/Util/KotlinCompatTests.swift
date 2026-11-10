import XCTest
@testable import KCNA26Core

/// Kotlin/JVM semantics helpers (Util/KotlinCompat.swift).
final class KotlinCompatTests: XCTestCase {

    // MARK: Sorting

    private struct Item: Equatable {
        let key: Int
        let name: String
    }

    func testStableSortKeepsTheOrderOfEqualElements() {
        // Many equal keys: an unstable sort would scramble the names.
        let items = (0..<200).map { Item(key: $0 % 3, name: "n\($0)") }
        let sorted = items.stableSorted(on: { $0.key })
        for k in 0..<3 {
            let names = sorted.filter { $0.key == k }.map(\.name)
            XCTAssertEqual(names, items.filter { $0.key == k }.map(\.name))
        }
        XCTAssertEqual(sorted.map(\.key), items.map(\.key).sorted())
        let byPredicate = items.stableSorted { $0.key < $1.key }
        XCTAssertEqual(byPredicate, sorted)
        let desc = items.stableSortedDescending(on: { $0.key })
        XCTAssertEqual(desc.first, Item(key: 2, name: "n2"))
        XCTAssertEqual(desc.last, Item(key: 0, name: "n198"))
    }

    func testComparatorChains() {
        struct S {
            let start: Int
            let mine: Bool
            let room: String?
            let id: String
        }
        let xs = [
            S(start: 2, mine: false, room: "b", id: "1"),
            S(start: 1, mine: false, room: nil, id: "2"),
            S(start: 1, mine: true, room: "a", id: "3"),
            S(start: 1, mine: false, room: "a", id: "4"),
            S(start: 1, mine: false, room: "a", id: "0"),
        ]
        // compareBy { start }.thenByDescending { mine }.thenBy { room }.thenBy { id }
        let c = KComparator<S>.by { $0.start }.thenByDescending { $0.mine }.thenBy { $0.room }.thenBy { $0.id }
        XCTAssertEqual(xs.stableSorted(with: c).map(\.id), ["3", "2", "0", "4", "1"])
        XCTAssertEqual(xs.stableSorted(with: c.reversed()).map(\.id), ["1", "4", "0", "2", "3"])
        XCTAssertEqual(xs.min(with: KComparator.by { $0.start })?.id, "2") // first minimal
        XCTAssertEqual(xs.max(with: KComparator.by { $0.start })?.id, "1")
        XCTAssertEqual(xs.max(with: KComparator.by { $0.mine })?.id, "3")
        // compareBy(String.CASE_INSENSITIVE_ORDER) { name }
        let names = ["beta", "Alpha", "alpha", "Gamma"]
        XCTAssertEqual(names.stableSorted(with: .caseInsensitiveOrder), ["Alpha", "alpha", "beta", "Gamma"])
        XCTAssertEqual(names.stableSorted(with: KComparator<String>.by(.caseInsensitiveOrder) { $0 }), ["Alpha", "alpha", "beta", "Gamma"])
        XCTAssertEqual(names.javaSorted(), ["Alpha", "Gamma", "alpha", "beta"])
        XCTAssertEqual(compareBy { (s: S) in s.start }.compare(xs[0], xs[1]), 1)
        XCTAssertEqual([3, 1, 2].stableSorted(with: .naturalOrder), [1, 2, 3])
        // The call shapes CONVENTIONS.md documents.
        struct P { let name: String; let level: Int? }
        let people = [P(name: "b", level: 2), P(name: "A", level: nil), P(name: "a", level: 1)]
        XCTAssertEqual(people.stableSorted(with: .by(.caseInsensitiveOrder) { $0.name }).map(\.name), ["A", "a", "b"])
        XCTAssertEqual(people.stableSorted(with: KComparator<P>.by { $0.level }.thenBy(.caseInsensitiveOrder) { $0.name }).map(\.name), ["A", "a", "b"])
        XCTAssertEqual(people.stableSorted { $0.name }.map(\.name), ["A", "a", "b"]) // one-arg closure = sortedBy
        XCTAssertEqual(people.stableSorted(on: { $0.level }).map(\.name), ["A", "a", "b"]) // nil first
        XCTAssertEqual(people.stableSorted { $0.name > $1.name }.map(\.name), ["b", "a", "A"]) // two-arg = predicate
    }

    func testCompareValues() {
        XCTAssertEqual(compareValues(nil as Int?, 1), -1)
        XCTAssertEqual(compareValues(1 as Int?, nil), 1)
        XCTAssertEqual(compareValues(nil as Int?, nil), 0)
        XCTAssertEqual(compareValues(false, true), -1)
        XCTAssertEqual(compareValues(true, true), 0)
        XCTAssertEqual(compareValues("b", "a"), 1)
    }

    private struct Named {
        let s: String
        let name: String?
    }

    func testStringKeysUseUTF16OrderOnEveryPath() {
        // "\u{FF61}" is the unit FF61; "\u{1F600}" is D83D DE00: Kotlin sorts the emoji first
        // ("｡x".compareTo("😀y") = 10020), Swift's String order puts it last.
        let a = Named(s: "\u{FF61}x", name: "\u{FF61}x"), b = Named(s: "\u{1F600}y", name: "\u{1F600}y")
        let emojiFirst = ["\u{1F600}y", "\u{FF61}x"], emojiLast = ["\u{FF61}x", "\u{1F600}y"]
        XCTAssertEqual([a, b].stableSorted(on: { $0.s }).map(\.s), emojiFirst)
        XCTAssertEqual([a, b].stableSorted(on: { $0.name }).map(\.s), emojiFirst) // String? key
        XCTAssertEqual([b, a].stableSortedDescending(on: { $0.s }).map(\.s), emojiLast)
        XCTAssertEqual([b, a].stableSortedDescending(on: { $0.name }).map(\.s), emojiLast)
        XCTAssertEqual([a.s, b.s].stableSorted(with: .naturalOrder), emojiFirst)
        XCTAssertEqual([a.s, b.s].stableSorted(on: { $0 }), emojiFirst)
        XCTAssertEqual([a, b].stableSorted(with: .by { $0.name }).map(\.s), emojiFirst)
        XCTAssertEqual([a, b].stableSorted(with: KComparator<Named>.by { _ in 0 }.thenBy { $0.name }).map(\.s), emojiFirst)
        XCTAssertEqual([b, a].stableSorted(with: KComparator<Named>.by { _ in 0 }.thenByDescending { $0.name }).map(\.s), emojiLast)
        XCTAssertEqual([b, a].stableSorted(with: KComparator<Named>.by { _ in 0 }.thenByDescending { $0.s }).map(\.s), emojiLast)
        XCTAssertEqual([b, a].stableSorted(with: KComparator<Named>.by(\.name)).map(\.s), emojiFirst) // key path
        // Generic code that only knows `K: Comparable` gets Kotlin's order too.
        func sortedGenerically<K: Comparable>(_ xs: [K]) -> [K] { xs.stableSorted(on: { $0 }) }
        XCTAssertEqual(sortedGenerically([a.s, b.s]), emojiFirst)
        XCTAssertLessThan(compareValues(Optional(b.s), Optional(a.s)), 0)
        // No canonical equivalence: e + U+0301 (65 301) sorts before é (E9); Swift calls them equal.
        let nfd = "e\u{301}", nfc = "\u{E9}"
        XCTAssertEqual(nfd, nfc)
        XCTAssertEqual([nfc, nfd].stableSorted(on: { $0 }).map { Array($0.unicodeScalars) }, [Array(nfd.unicodeScalars), Array(nfc.unicodeScalars)])
        XCTAssertEqual([nfc, nfd].stableSorted(on: { Optional($0) }).map(\.utf16.count), [2, 1])
        XCTAssertEqual([nfc, nfd].stableSorted(with: .naturalOrder).map(\.utf16.count), [2, 1])
    }

    func testDoubleKeysUseJavaTotalOrder() {
        // Kotlin sortedBy { it.d }: Double.compareTo, -0.0 < 0.0, NaN last (and equal to itself).
        let keys: [Double] = [0.0, -0.0, .nan, 1, -1, .infinity, -.infinity]
        let sorted = keys.stableSorted(on: { $0 })
        XCTAssertEqual(sorted.map(\.description), ["-inf", "-1.0", "-0.0", "0.0", "1.0", "inf", "nan"])
        XCTAssertEqual(keys.stableSortedDescending(on: { $0 }).map(\.description), ["nan", "inf", "1.0", "0.0", "-0.0", "-1.0", "-inf"])
        XCTAssertEqual(keys.stableSorted(with: .naturalOrder).map(\.description), sorted.map(\.description))
        XCTAssertEqual(keys.stableSorted(with: .by { $0 }).map(\.description), sorted.map(\.description))
        XCTAssertEqual(keys.map { Optional($0) }.stableSorted(on: { $0 }).map(\.!.description), sorted.map(\.description))
        // A NaN key no longer scrambles the rest of the list.
        let low: [Double] = (0..<50).map { Double(($0 * 37) % 50) }
        let high: [Double] = (0..<50).map { Double(($0 * 37) % 50) + 0.5 }
        let many: [Double] = low + [Double.nan] + high
        let s = many.stableSorted(on: { $0 })
        XCTAssertTrue(s.last!.isNaN)
        XCTAssertEqual(Array(s.dropLast()), many.filter { !$0.isNaN }.sorted())
        XCTAssertEqual(compareValues(Double.nan, 1.0), 1)
        XCTAssertEqual(compareValues(Double.nan, .infinity), 1)
        XCTAssertEqual(compareValues(Double.nan, Double.nan), 0)
        XCTAssertEqual(compareValues(-Double.nan, Double.nan), 0) // every NaN is the canonical NaN
        XCTAssertEqual(compareValues(-0.0, 0.0), -1)
        XCTAssertEqual(compareValues(0.0, -0.0), 1)
        XCTAssertEqual(compareValues(2.5, 2.5), 0)
        XCTAssertEqual(compareValues(nil, Double.nan), -1)
        XCTAssertEqual(javaDoubleCompare(-.infinity, -Double.greatestFiniteMagnitude), -1)
        // Float: Float.compare.
        XCTAssertEqual(compareValues(Float.nan, Float(1)), 1)
        XCTAssertEqual(compareValues(Float(-0.0), Float(0.0)), -1)
        XCTAssertEqual(([Float(0), -0.0, .nan, -1] as [Float]).stableSorted(on: { $0 }).map(\.description), ["-1.0", "-0.0", "0.0", "nan"])
    }

    private struct Distance {
        let d: Int64?
        let level: Int?
        let name: String
    }

    /// FromMenu.kt: `private val NEAREST_FIRST = compareBy<FromMenuItem>(...)`.
    private enum ComparatorConstants {
        static let NEAREST_FIRST = KComparator<Distance>.by { $0.d ?? Int64.max }.thenBy { $0.level ?? Int.max }
        static let BY_NAME = KComparator<Distance>.by(\.name).thenByDescending { $0.level }
    }

    func testComparatorsCanBeStaticConstants() {
        // KComparator is Sendable: a `static let` compiles under Swift 6 strict concurrency.
        let xs = [Distance(d: nil, level: 1, name: "c"), Distance(d: 5, level: nil, name: "b"), Distance(d: 5, level: 2, name: "a")]
        XCTAssertEqual(xs.stableSorted(with: ComparatorConstants.NEAREST_FIRST).map(\.name), ["a", "b", "c"])
        XCTAssertEqual(xs.stableSorted(with: ComparatorConstants.BY_NAME).map(\.name), ["a", "b", "c"])
        let sendable: any Sendable = ComparatorConstants.NEAREST_FIRST
        XCTAssertNotNil(sendable as? KComparator<Distance>)
    }

    // MARK: String order and case

    func testJavaCompareIsUTF16Order() {
        XCTAssertEqual(javaCompare("a", "b"), -1)
        XCTAssertEqual(javaCompare("abc", "ab"), 1)
        XCTAssertEqual(javaCompare("ab", "abcd"), -2)
        XCTAssertEqual(javaCompare("", ""), 0)
        XCTAssertEqual(javaCompare("B", "a"), Int(UInt16(UInt8(ascii: "B"))) - Int(UInt16(UInt8(ascii: "a"))))
        // UTF-16 order differs from code-point order for supplementary characters:
        // U+1F600 is D83D DE00, which sorts before U+FF5E.
        XCTAssertLessThan(javaCompare("😀", "～"), 0)
        XCTAssertGreaterThan("😀", "～") // Swift's order is by scalar value
        // No Unicode equivalence: precomposed é (E9) vs e + combining acute.
        XCTAssertNotEqual(javaCompare("é", "e\u{301}"), 0)
    }

    func testJavaCaseInsensitiveOrder() {
        XCTAssertEqual(javaCaseInsensitiveCompare("abc", "ABC"), 0)
        XCTAssertLessThan(javaCaseInsensitiveCompare("apple", "Banana"), 0)
        XCTAssertGreaterThan(javaCaseInsensitiveCompare("b", "A"), 0)
        XCTAssertLessThan(javaCaseInsensitiveCompare("ab", "ABC"), 0)
        // Non-ASCII letters fold too.
        XCTAssertEqual(javaCaseInsensitiveCompare("ÉCOLE", "école"), 0)
        XCTAssertEqual(javaCaseInsensitiveCompare("Straße", "STRASSE".lowercased()) == 0, false) // no ß -> ss
        XCTAssertEqual(javaCaseInsensitiveCompare("ΣΊΣΥΦΟΣ", "σίσυφος"), 0)
        XCTAssertEqual(javaCaseInsensitiveCompare("İ", "i"), 0) // U+0130 lowercases (simply) to i
        // Differences compare as lowercased units: "_" (5F) vs "a": upper 'A' (41) differs, lower 'a' (61) > 5F.
        XCTAssertLessThan(javaCaseInsensitiveCompare("_", "a"), 0)
        // Sorting speaker names like the Settings picker: case-insensitive, else stable ("de " < "dec": space < c).
        let names = ["de Vries", "Decheng Dai", "Ángel", "Zoë", "abe", "Abe"]
        XCTAssertEqual(names.stableSorted(with: .caseInsensitiveOrder), ["abe", "Abe", "de Vries", "Decheng Dai", "Zoë", "Ángel"])
        XCTAssertTrue(kotlinEqualsIgnoreCase("Hello", "hELLO"))
        XCTAssertFalse(kotlinEqualsIgnoreCase("Hello", "Hell"))
        XCTAssertEqual(javaToUpperCase(UInt16(UInt8(ascii: "q"))), UInt16(UInt8(ascii: "Q")))
        XCTAssertEqual(javaToUpperCase(0xDF), 0xDF) // ß has no single-char uppercase
        XCTAssertEqual(javaToUpperCase(0x1FB3), 0x1FBC) // ᾳ -> ᾼ (simple mapping)
        XCTAssertEqual(javaToLowerCase(0x130), 0x69)
        XCTAssertEqual(javaToUpperCase(0xD83D), 0xD83D) // a surrogate half is unchanged
    }

    // MARK: Trim and blank

    func testKotlinTrimAndBlank() {
        XCTAssertEqual("  a b \n".kotlinTrim(), "a b")
        // Kotlin trim() also strips NBSP and other Unicode spaces (Char.isWhitespace)...
        XCTAssertEqual("\u{A0}\u{2007}x\u{3000}\u{202F}".kotlinTrim(), "x")
        // ...but not zero-width space, BOM or NEL.
        XCTAssertEqual("\u{200B}x\u{FEFF}".kotlinTrim(), "\u{200B}x\u{FEFF}")
        XCTAssertEqual("\u{85}x".kotlinTrim(), "\u{85}x")
        // Java String.trim() strips only chars <= U+0020 (including control characters).
        XCTAssertEqual("\u{1}\u{A0}x ".javaTrim(), "\u{A0}x")
        XCTAssertEqual("  x  ".kotlinTrimStart(), "x  ")
        XCTAssertEqual("  x  ".kotlinTrimEnd(), "  x")
        XCTAssertEqual("".kotlinTrim(), "")
        XCTAssertTrue("".isBlank)
        XCTAssertTrue(" \t\n\u{A0}\u{2028}".isBlank)
        XCTAssertFalse(" x ".isBlank)
        XCTAssertFalse("\u{200B}".isBlank)
        XCTAssertTrue("a".isNotBlank)
        XCTAssertNil("  ".takeIfNotBlank())
        XCTAssertEqual(" a ".takeIfNotBlank(), " a ")
        XCTAssertEqual(" ".ifBlank { "d" }, "d")
        XCTAssertEqual("".ifEmpty { "d" }, "d")
        XCTAssertTrue(isKotlinWhitespace(0x1C))
        XCTAssertFalse(isKotlinWhitespace(0x0))
    }

    // MARK: UTF-16 string helpers

    func testStringEqualityAndSearchAreByUTF16Units() {
        // Kotlin compares UTF-16 units; Swift's ==, Hashable, hasPrefix and contains use canonical
        // equivalence and whole Characters.
        let nfd = "Jose\u{301}", nfc = "Jos\u{E9}"
        XCTAssertTrue(nfc == nfd) // Swift
        XCTAssertEqual(Set([nfc, nfd]).count, 1) // Swift
        XCTAssertFalse(kotlinEquals(nfc, nfd))
        XCTAssertTrue(kotlinEquals(nfd, "Jose\u{301}"))
        XCTAssertFalse(nfd.hasPrefix("Jose")) // Swift
        XCTAssertTrue(nfd.kotlinStartsWith("Jose"))
        XCTAssertFalse(nfc.kotlinStartsWith(nfd))
        XCTAssertTrue(nfd.kotlinStartsWith(""))
        XCTAssertFalse("Jo".kotlinStartsWith("Jose"))
        XCTAssertFalse(nfd.contains("e")) // Swift
        XCTAssertTrue(nfd.kotlinContains("e"))
        XCTAssertTrue(nfd.kotlinContains(""))
        XCTAssertFalse(nfc.kotlinContains("e"))
        XCTAssertTrue("a😀".kotlinEndsWith("😀"))
        XCTAssertTrue(nfd.kotlinEndsWith("\u{301}"))
        XCTAssertFalse(nfc.kotlinEndsWith("e\u{301}"))
        XCTAssertFalse("x".kotlinEndsWith("xx"))
        XCTAssertTrue("x".kotlinEndsWith(""))
        // lowercase(Locale.ROOT) turns a word-final Σ into ς (U+03C2); Swift's lowercased() does not.
        XCTAssertEqual("ΟΔΟΣ".lowercased().unicodeScalars.last?.value, 0x3C3)
    }

    func testUTF16StringHelpers() {
        let s = "a😀b–c"
        XCTAssertEqual(s.kotlinLength, 6) // a, 2 surrogates, b, –, c
        XCTAssertEqual(s.kotlinSubstring(1, 3), "😀")
        XCTAssertEqual(s.kotlinSubstring(3), "b–c")
        XCTAssertEqual(s.kotlinTake(3), "a😀")
        XCTAssertEqual(s.kotlinTake(99), s)
        XCTAssertEqual(s.kotlinTakeLast(2), "–c")
        XCTAssertEqual(s.kotlinDrop(3), "b–c")
        XCTAssertEqual(s.kotlinDrop(99), "")
        XCTAssertEqual(s.kotlinIndexOf("b"), 3)
        XCTAssertEqual(s.kotlinIndexOf("x"), -1)
        XCTAssertEqual(s.kotlinIndexOf(""), 0)
        XCTAssertEqual("abab".kotlinIndexOf("ab", from: 1), 2)
        XCTAssertEqual("abab".kotlinLastIndexOf("ab"), 2)
        XCTAssertEqual("Sun 8".substringBefore(" "), "Sun")
        XCTAssertEqual("Sun".substringBefore(" "), "Sun")
        XCTAssertEqual("a.b.c".substringAfter("."), "b.c")
        XCTAssertEqual("a.b.c".substringBeforeLast("."), "a.b")
        XCTAssertEqual("a.b.c".substringAfterLast("."), "c")
        XCTAssertEqual("abc".substringAfter("x", missing: "-"), "-")
        XCTAssertEqual("#C2255B".removePrefix("#"), "C2255B")
        XCTAssertEqual("C2255B".removePrefix("#"), "C2255B")
        XCTAssertEqual("file.json".removeSuffix(".json"), "file")
        XCTAssertEqual("5".padStart(2, "0"), "05")
        XCTAssertEqual("123".padStart(2, "0"), "123")
        XCTAssertEqual("5".padEnd(3), "5  ")
        XCTAssertEqual("x-y-x".replaceFirst("x", "z"), "z-y-x")
        XCTAssertEqual("x-y-x".kotlinReplace("x", "zz"), "zz-y-zz")
        XCTAssertEqual("aaa".kotlinReplace("aa", "b"), "ba")
        XCTAssertEqual("ab".kotlinReplace("", "-"), "-a-b-")
    }

    // MARK: Numbers

    func testRoundToIntIsHalfUpLikeMathRound() {
        XCTAssertEqual(2.5.kotlinRoundToInt(), 3)
        XCTAssertEqual((-2.5).kotlinRoundToInt(), -2) // Swift's rounded() gives -3
        XCTAssertEqual((-2.5).rounded(), -3)
        XCTAssertEqual((-2.51).kotlinRoundToInt(), -3)
        XCTAssertEqual((-0.5).kotlinRoundToInt(), 0)
        XCTAssertEqual(0.49999999999999994.kotlinRoundToInt(), 0) // Java 7+ Math.round
        XCTAssertEqual(1.4999999999999998.kotlinRoundToInt(), 1)
        XCTAssertEqual(Double.nan.kotlinRoundToInt(), 0)
        XCTAssertEqual(1e12.kotlinRoundToInt(), Int(Int32.max)) // Kotlin Int saturates
        XCTAssertEqual((-1e12).kotlinRoundToInt(), Int(Int32.min))
        XCTAssertEqual(1e12.kotlinRoundToLong(), 1_000_000_000_000)
        XCTAssertEqual((-3.5).kotlinRoundToLong(), -3)
        XCTAssertEqual(Double.infinity.kotlinRoundToLong(), Int64.max)
        XCTAssertEqual(Float(-2.5).kotlinRoundToInt(), -2)
        XCTAssertEqual(Float(2.5).kotlinRoundToInt(), 3)
    }

    func testRoundIsHalfEvenAndToIntTruncates() {
        XCTAssertEqual(2.5.kotlinRound(), 2)
        XCTAssertEqual(3.5.kotlinRound(), 4)
        XCTAssertEqual((-2.5).kotlinRound(), -2)
        XCTAssertEqual(2.7.kotlinToInt(), 2)
        XCTAssertEqual((-2.7).kotlinToInt(), -2)
        XCTAssertEqual(Double.nan.kotlinToInt(), 0)
        XCTAssertEqual(1e20.kotlinToInt(), Int(Int32.max))
        XCTAssertEqual(1e20.kotlinToLong(), Int64.max)
        XCTAssertEqual((-1e20).kotlinToLong(), Int64.min)
    }

    func testFloorModAndClamp() {
        XCTAssertEqual(floorMod(-1, 60), 59)
        XCTAssertEqual(floorMod(61, 60), 1)
        XCTAssertEqual(floorMod(5, -3), -1)
        XCTAssertEqual(floorMod(Int64(-15_001), Int64(15_000)), 14_999)
        XCTAssertEqual(floorDiv(-1, 60), -1)
        XCTAssertEqual(floorDiv(7, 2), 3)
        XCTAssertEqual(floorDiv(-7, 2), -4)
        XCTAssertEqual(5.clamped(to: 0...3), 3)
        XCTAssertEqual((-1.5).clamped(to: 0...1), 0)
        XCTAssertEqual(2.coerceIn(0, 3), 2)
        XCTAssertEqual(2.coerceAtLeast(5), 5)
        XCTAssertEqual(2.coerceAtMost(1), 1)
    }

    // MARK: Collections

    func testCollectionBuilders() {
        XCTAssertEqual([3, 1, 3, 2, 1].distinct(), [3, 1, 2])
        XCTAssertEqual(["aa", "b", "cc", "d"].distinctBy { $0.count }, ["aa", "b"])
        let assoc = ["x1", "y1", "x2"].associateBy { String($0.prefix(1)) }
        XCTAssertEqual(assoc.keys, ["x", "y"])
        XCTAssertEqual(assoc["x"], "x2") // last wins
        XCTAssertEqual(["x1", "y1"].associateBy({ String($0.prefix(1)) }, { $0.count })["x"], 2)
        XCTAssertEqual(["a", "bb"].associate { ($0, $0.count) }.values, [1, 2])
        XCTAssertEqual(["a", "bb"].associateWith { $0.count }["bb"], 2)
        let g = [1, 2, 3, 4, 5, 6].groupBy { $0 % 3 }
        XCTAssertEqual(g.keys, [1, 2, 0])
        XCTAssertEqual(g[1], [1, 4])
        XCTAssertEqual(g[0], [3, 6])
        let (even, odd) = [1, 2, 3, 4].kotlinPartition { $0 % 2 == 0 }
        XCTAssertEqual(even, [2, 4])
        XCTAssertEqual(odd, [1, 3])
        XCTAssertEqual([1, 2, 3].zipWithNext().map { $0.0 * 10 + $0.1 }, [12, 23])
        XCTAssertEqual([1, 2, 3].zipWithNext { $1 - $0 }, [1, 1])
        XCTAssertEqual([1].zipWithNext().count, 0)
        XCTAssertEqual([1, 2, 3, 4, 5].windowed(2), [[1, 2], [2, 3], [3, 4], [4, 5]])
        XCTAssertEqual([1, 2, 3, 4, 5].windowed(3, step: 2), [[1, 2, 3], [3, 4, 5]])
        XCTAssertEqual([1, 2, 3, 4].windowed(3, step: 2, partialWindows: true), [[1, 2, 3], [3, 4]])
        XCTAssertEqual([1, 2, 3, 4, 5].chunked(2), [[1, 2], [3, 4], [5]])
        XCTAssertEqual([1, 2].getOrNull(1), 2)
        XCTAssertNil([1, 2].getOrNull(2))
        XCTAssertNil([1, 2].getOrNull(-1))
        XCTAssertEqual([Int]().ifEmpty { [7] }, [7])
    }
}
