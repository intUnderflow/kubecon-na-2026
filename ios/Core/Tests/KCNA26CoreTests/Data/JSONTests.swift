import XCTest
@testable import KCNA26Core

/// The order-preserving JSON parser and serializer (Data/JSON.swift).
final class JSONTests: XCTestCase {

    private func parse(_ s: String) throws -> JSONValue { try JSON.parse(s) }

    private func assertParseError(_ s: String, contains fragment: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try JSON.parse(s), "\(s)", file: file, line: line) { e in
            guard let pe = e as? JSONParseError else { return XCTFail("not a JSONParseError: \(e)", file: file, line: line) }
            if let fragment {
                XCTAssertTrue(pe.description.contains(fragment), "\(pe.description) lacks \(fragment)", file: file, line: line)
            }
        }
    }

    // MARK: Values

    func testScalars() throws {
        XCTAssertEqual(try parse("null"), .null)
        XCTAssertEqual(try parse(" true "), .bool(true))
        XCTAssertEqual(try parse("false"), .bool(false))
        XCTAssertEqual(try parse("\"x\""), .string("x"))
        XCTAssertEqual(try parse("[]"), .array([]))
        XCTAssertEqual(try parse("{}"), .object([:]))
        XCTAssertEqual(try parse("\t\r\n [ 1 , 2 ] \n"), [1, 2])
    }

    func testIntegersAndDoublesStayDistinguishable() throws {
        let v = try parse(#"{"a": 3, "b": 3.0, "c": 3e0, "d": -0, "e": true, "f": "3"}"#)
        let a = try XCTUnwrap(v["a"]?.numberValue)
        XCTAssertTrue(a.isInteger)
        XCTAssertEqual(a.int64Value, 3)
        XCTAssertEqual(a.intValue, 3)
        XCTAssertEqual(a.literal, "3")
        let b = try XCTUnwrap(v["b"]?.numberValue)
        XCTAssertFalse(b.isInteger)
        XCTAssertNil(b.int64Value)
        XCTAssertEqual(b.doubleValue, 3.0)
        XCTAssertEqual(b.literal, "3.0")
        XCTAssertFalse(try XCTUnwrap(v["c"]?.numberValue).isInteger)
        XCTAssertEqual(v["d"]?.int64Value, 0)
        // "-0" is -0.0 as a Double (kotlinx: "-0".toDouble()), and 0 for an integer field.
        XCTAssertEqual(v["d"]?.doubleValue?.sign, .minus)
        XCTAssertEqual(try parse("0").doubleValue?.sign, .plus)
        XCTAssertEqual(try parse("-0.0").doubleValue?.sign, .minus)
        XCTAssertEqual(try Double(json: parse("-0")).sign, .minus)
        XCTAssertEqual(try [Double](json: parse("[-0, 0]")).map(\.sign), [.minus, .plus])
        XCTAssertEqual(try Int(json: parse("-0")), 0)
        XCTAssertNil(v["e"]?.numberValue)
        XCTAssertNil(v["f"]?.numberValue)
        // kotlinx equality: by literal.
        XCTAssertNotEqual(v["a"], v["b"])
        XCTAssertEqual(v["a"], JSONValue.number(JSONNumber(3)))
    }

    func testNumberRangeAndPrecision() throws {
        XCTAssertEqual(try parse("9223372036854775807").int64Value, Int64.max)
        XCTAssertEqual(try parse("-9223372036854775808").int64Value, Int64.min)
        // Too big for Int64: still a number, as a Double.
        let big = try XCTUnwrap(try parse("9223372036854775808").numberValue)
        XCTAssertTrue(big.isInteger)
        XCTAssertNil(big.int64Value)
        XCTAssertEqual(big.doubleValue, 9.223372036854775808e18)
        XCTAssertEqual(try parse("-73.25").doubleValue, -73.25)
        XCTAssertEqual(try parse("1E3").doubleValue, 1000)
        XCTAssertEqual(try parse("2.5e-3").doubleValue, 0.0025)
        XCTAssertEqual(try parse("40.7608").doubleValue, 40.7608)
        XCTAssertEqual(try parse("1e999").doubleValue, .infinity)
    }

    func testStringEscapes() throws {
        XCTAssertEqual(try parse(#""a\"b\\c\/d\b\f\n\r\t""#), .string("a\"b\\c/d\u{8}\u{C}\n\r\t"))
        XCTAssertEqual(try parse(#""é– ""#), .string("é–\u{A0}"))
        XCTAssertEqual(try parse(#""café – ok""#).stringValue, "café – ok")
        // UTF-8 passes through.
        XCTAssertEqual(try parse("\"251 A–C · “quoted” …\"").stringValue, "251 A–C · “quoted” …")
        // Raw control characters inside strings are accepted, like kotlinx.
        XCTAssertEqual(try parse("\"a\nb\"").stringValue, "a\nb")
        // Escapes at the start, the end, and back to back.
        XCTAssertEqual(try parse(#""\n""#).stringValue, "\n")
        XCTAssertEqual(try parse(#""\\\\""#).stringValue, "\\\\")
        XCTAssertEqual(try parse(#""x\"""#).stringValue, "x\"")
        // Escaped quotes before the closing one (the cached quote position must move on).
        XCTAssertEqual(try parse(#""\"\"a\"b\n\"""#).stringValue, "\"\"a\"b\n\"")
        XCTAssertEqual(try parse(#"["a\"b", "c\\", "\"d"]"#), ["a\"b", "c\\", "\"d"])
        XCTAssertThrowsError(try parse(#""abc\""#)) // the only quote is escaped: unterminated
    }

    func testManyEscapesInOneStringParseInLinearTime() throws {
        // 800k escapes (1.6 MB in one string). The parser used to rescan the rest of the string
        // for its closing quote after every escape (quadratic: several seconds here).
        let count = 800_000
        let text = "\"" + String(repeating: "\\n", count: count - 1) + "\\\"\""
        let t0 = Date()
        let s = try XCTUnwrap(try parse(text).stringValue)
        let seconds = Date().timeIntervalSince(t0)
        XCTAssertEqual(s.utf8.count, count)
        XCTAssertTrue(s.hasPrefix("\n\n"))
        XCTAssertTrue(s.hasSuffix("\n\""))
        XCTAssertLessThan(seconds, 3.0)
    }

    func testSurrogatePairs() throws {
        XCTAssertEqual(try parse(#""😀""#).stringValue, "😀")
        XCTAssertEqual(try parse(#""a🎉b""#).stringValue, "a🎉b")
        XCTAssertEqual(try parse("\"😀\"").stringValue, "😀")
        // Lone surrogates cannot exist in a Swift String: U+FFFD (Kotlin would keep the unit).
        XCTAssertEqual(try parse(#""\uD83D""#).stringValue, "\u{FFFD}")
        XCTAssertEqual(try parse(#""\uDE00x""#).stringValue, "\u{FFFD}x")
        XCTAssertEqual(try parse(#""\uD83DA""#).stringValue, "\u{FFFD}A")
    }

    func testInvalidUTF8BecomesReplacementCharacters() throws {
        let bytes: [UInt8] = [0x22, 0x61, 0xFF, 0x62, 0x22] // "a\xFFb"
        XCTAssertEqual(try JSON.parse(Data(bytes)).stringValue, "a\u{FFFD}b")
    }

    func testObjectsKeepKeyOrderAndLastDuplicateWins() throws {
        let v = try parse(#"{"z": 1, "a": 2, "m": {"y": [], "b": null}, "z": 3}"#)
        let o = try XCTUnwrap(v.objectValue)
        XCTAssertEqual(o.keys, ["z", "a", "m"]) // first position...
        XCTAssertEqual(o["z"], 3) // ...last value (LinkedHashMap.put)
        XCTAssertEqual(v["m"]?.objectValue?.keys, ["y", "b"])
        XCTAssertEqual(v["m"]?["b"], .null)
        XCTAssertNil(v["nope"])
        XCTAssertNil(v["m"]?["y"]?[0])
    }

    func testLargeObjectsKeepOrder() throws {
        let keys = (0..<300).map { "k\(299 - $0)" }
        let text = "{" + keys.enumerated().map { "\"\($1)\": \($0)" }.joined(separator: ",") + "}"
        let o = try XCTUnwrap(try parse(text).objectValue)
        XCTAssertEqual(o.keys, keys)
        XCTAssertEqual(o["k0"], 299)
        XCTAssertEqual(o["k299"], 0)
    }

    func testNesting() throws {
        let v = try parse(#"[[[{"a": [1, {"b": [true]}]}]]]"#)
        XCTAssertEqual(v[0]?[0]?[0]?["a"]?[1]?["b"]?[0], true)
        let deep = String(repeating: "[", count: JSON.maxDepth) + String(repeating: "]", count: JSON.maxDepth)
        XCTAssertNoThrow(try parse(deep))
        let tooDeep = String(repeating: "[", count: JSON.maxDepth + 1) + String(repeating: "]", count: JSON.maxDepth + 1)
        assertParseError(tooDeep, contains: "Nesting")
    }

    func testMalformedInputThrowsWithALocation() throws {
        assertParseError("")
        assertParseError("   ")
        assertParseError("{ not json", contains: "quoted key")
        assertParseError("{\"a\" 1}", contains: "':'")
        assertParseError("{\"a\": 1,}", contains: "quoted key")
        assertParseError("[1, 2,]", contains: "expected a value")
        assertParseError("[1 2]", contains: "','")
        assertParseError("{\"a\": 1 \"b\": 2}", contains: "','")
        assertParseError("\"abc", contains: "Unterminated")
        assertParseError(#""a\x""#, contains: "Invalid escaped char")
        assertParseError(#""\u12G4""#, contains: "\\u")
        assertParseError("tru", contains: "true")
        assertParseError("nul", contains: "null")
        assertParseError("01", contains: "trailing")
        assertParseError("-", contains: "digit")
        assertParseError("1.", contains: "digit")
        assertParseError(".5")
        assertParseError("1e", contains: "exponent")
        assertParseError("+1")
        assertParseError("NaN")
        assertParseError("{} {}", contains: "trailing")
        assertParseError("[1]]", contains: "trailing")
        // Line and column.
        do {
            _ = try JSON.parse("{\n  \"a\": 1,\n  \"b\": ?\n}")
            XCTFail("no error")
        } catch let e as JSONParseError {
            XCTAssertEqual(e.line, 3)
            XCTAssertEqual(e.column, 8)
            XCTAssertEqual(e.offset, 19)
        }
    }

    // MARK: Serializer

    func testCompactSerialization() {
        let v: JSONValue = ["b": [1, 2.5, true, nil], "a": "x\"y\\z\n\u{1}é😀", "c": [:], "d": []]
        XCTAssertEqual(JSON.serialize(v), #"{"b":[1,2.5,true,null],"a":"x\"y\\z\n\u0001é😀","c":{},"d":[]}"#)
        XCTAssertEqual(v.description, JSON.serialize(v))
    }

    func testPrettySerialization() {
        let v: JSONValue = ["a": 1, "b": ["x", ["y": false]], "c": []]
        XCTAssertEqual(JSON.serialize(v, pretty: true), """
        {
            "a": 1,
            "b": [
                "x",
                {
                    "y": false
                }
            ],
            "c": []
        }
        """)
    }

    func testNumbersReserializeAsWritten() throws {
        let text = #"{"a":84300.0,"b":-73,"c":1e3,"d":0.1,"e":12345678901234567890}"#
        XCTAssertEqual(JSON.serialize(try parse(text)), text)
        XCTAssertEqual(JSON.serialize(.number(JSONNumber(3.0))), "3.0")
        XCTAssertEqual(JSON.serialize(.number(JSONNumber(Double.nan))), "null")
        XCTAssertEqual(JSON.serialize(.number(JSONNumber(Int64(-7)))), "-7")
    }

    func testRoundTripOfEveryDataFile() throws {
        for name in [Repository.SCHEDULE, Repository.ROOMS, Repository.WAYFINDING, Repository.VENUE, Repository.DETAILS,
                     Repository.SUMMIT_DETAILS, Repository.COLOCATED, Repository.COLOCATED_DETAILS, "manifest.json"] {
            let v = TestData.json(name)
            let compact = try JSON.parse(JSON.serialize(v))
            let pretty = try JSON.parse(JSON.serialize(v, pretty: true))
            XCTAssertEqual(v, compact, name)
            XCTAssertEqual(v, pretty, name)
            // Key order survives too (== on objects ignores order).
            XCTAssertEqual(JSON.serialize(v), JSON.serialize(compact), name)
        }
    }

    func testMatchesPythonsReadingOfTheDataFiles() throws {
        // Spot checks against values a JSON reader with no ordering bugs must see.
        let rooms = try XCTUnwrap(TestData.json(Repository.ROOMS)["rooms"]?.objectValue)
        XCTAssertEqual(rooms.count, 40)
        let way = TestData.json(Repository.WAYFINDING)
        XCTAssertEqual(way["entrances"]?.objectValue?.keys, ["E200S", "EWT", "EHY", "E200W"])
        XCTAssertEqual(way["origin"]?["metersPerDegLon"]?.numberValue?.literal, "84300") // written as an integer...
        XCTAssertEqual(way["origin"]?["metersPerDegLon"]?.doubleValue, 84300.0) // ...read as a Double field
    }

    // MARK: Accessors and literals

    func testAccessors() throws {
        let v = try parse(#"{"s": "x", "i": 7, "d": 7.5, "b": false, "a": [1], "o": {"k": 1}, "n": null}"#)
        XCTAssertEqual(v["s"]?.stringValue, "x")
        XCTAssertEqual(v["i"]?.intValue, 7)
        XCTAssertEqual(v["i"]?.doubleValue, 7)
        XCTAssertNil(v["d"]?.intValue)
        XCTAssertEqual(v["d"]?.doubleValue, 7.5)
        XCTAssertEqual(v["b"]?.boolValue, false)
        XCTAssertEqual(v["a"]?.arrayValue?.count, 1)
        XCTAssertEqual(v["o"]?.objectValue?.count, 1)
        XCTAssertEqual(v["n"]?.isNull, true)
        XCTAssertNil(v["s"]?.intValue)
        XCTAssertEqual(v["i"]?.primitiveContent, "7")
        XCTAssertEqual(v["b"]?.primitiveContent, "false")
        XCTAssertEqual(v["n"]?.primitiveContent, "null")
        XCTAssertNil(v["a"]?.primitiveContent)
        XCTAssertEqual(v["a"]?.kindName, "array")
        XCTAssertNil(v[0])
        XCTAssertNil(v["a"]?[5])
        XCTAssertNil(v["a"]?[-1])
    }
}
