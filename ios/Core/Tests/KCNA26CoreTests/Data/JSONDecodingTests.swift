import XCTest
@testable import KCNA26Core

/// Decoding with the Kotlin app's kotlinx config: { ignoreUnknownKeys, explicitNulls = false,
/// coerceInputValues, isLenient } (Data/JSONDecoding.swift, Data/Dto.swift).
final class JSONDecodingTests: XCTestCase {

    private func decode<T: JSONDecodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSON.decode(T.self, from: text)
    }

    private func assertDecodingError<T: JSONDecodable>(_ type: T.Type, _ text: String, contains fragment: String,
                                                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try JSON.decode(T.self, from: text), file: file, line: line) { e in
            guard let de = e as? JSONDecodingError else { return XCTFail("not a JSONDecodingError: \(e)", file: file, line: line) }
            XCTAssertTrue(de.description.contains(fragment), "'\(de.description)' lacks '\(fragment)'", file: file, line: line)
        }
    }

    private let minimalSession = #""id": "1", "event": "kubecon", "day": "mon", "start": "2026-11-09T09:00:00-07:00", "room": "151", "title": "T", "category": "talk""#

    func testMissingKeysGiveTheDefaultsAndUnknownKeysAreIgnored() throws {
        let s = try decode(SessionDto.self, "{\(minimalSession), \"surprise\": [1, {\"x\": 2}]}")
        XCTAssertNil(s.end)
        XCTAssertFalse(s.endIsEstimate)
        XCTAssertEqual(s.speakers, [])
        XCTAssertEqual(s.officialUrl, "")
        XCTAssertEqual(s.coloEvents, [])
        XCTAssertFalse(s.sponsored)
        XCTAssertNil(s.group)
        let sch = try decode(ScheduleFileDto.self, "{}")
        XCTAssertEqual(sch.timeZone, "America/Denver")
        XCTAssertEqual(sch.me, "Lucy Sweet")
        XCTAssertTrue(sch.sessions.isEmpty)
    }

    func testNullForAFieldWithADefaultGivesTheDefault() throws {
        // coerceInputValues + explicitNulls = false.
        let s = try decode(SessionDto.self, "{\(minimalSession), \"speakers\": null, \"endIsEstimate\": null, \"officialUrl\": null, \"end\": null}")
        XCTAssertEqual(s.speakers, [])
        XCTAssertFalse(s.endIsEstimate)
        XCTAssertEqual(s.officialUrl, "")
        XCTAssertNil(s.end)
    }

    func testRequiredFieldsMustBePresentAndNonNull() {
        assertDecodingError(SessionDto.self, #"{"event": "kubecon"}"#, contains: "Field 'id' is required for type 'SessionDto'")
        assertDecodingError(SessionDto.self, "{\(minimalSession.replacingOccurrences(of: "\"title\": \"T\"", with: "\"title\": null"))}",
                            contains: "'title'")
        assertDecodingError(DayDto.self, #"{"key": "sun", "date": "2026-11-08", "label": "Sunday, Nov 8"}"#, contains: "'short'")
    }

    func testWrongTypesThrowWithAPath() {
        assertDecodingError(SessionDto.self, "{\(minimalSession), \"speakers\": \"Lucy\"}", contains: "$.speakers: Expected an array")
        assertDecodingError(SessionDto.self, "{\(minimalSession), \"speakers\": [\"a\", null]}", contains: "$.speakers[1]: Expected a string, found null")
        assertDecodingError(SessionDto.self, "{\(minimalSession), \"group\": [1]}", contains: "$.group: Expected an object for GroupDto")
        assertDecodingError(SessionDto.self, "{\(minimalSession), \"endIsEstimate\": 1}", contains: "$.endIsEstimate: Expected a boolean")
        assertDecodingError(ScheduleFileDto.self, #"{"sessions": [{"id": "x"}]}"#, contains: "$.sessions[0]: Field 'event' is required")
        assertDecodingError(RoomsFileDto.self, #"{"rooms": {"A": {"name": "A", "level": "two"}}}"#, contains: "$.rooms.A.level")
        assertDecodingError(SessionDto.self, "[]", contains: "Expected an object for SessionDto, found array")
    }

    func testLenientStringsAndQuotedNumbers() throws {
        // isLenient: an unquoted number or boolean where a string is expected gives its text.
        let s = try decode(SessionDto.self, "{\(minimalSession.replacingOccurrences(of: "\"id\": \"1\"", with: "\"id\": 1311951")), \"note\": true, \"level\": 2.50}")
        XCTAssertEqual(s.id, "1311951")
        XCTAssertEqual(s.note, "true")
        XCTAssertEqual(s.level, "2.50")
        // kotlinx always accepts a quoted number for a number, and (lenient) a quoted boolean.
        let r = try decode(RoomDto.self, #"{"name": "R", "level": "2", "x": "-73.5"}"#)
        XCTAssertEqual(r.level, 2)
        XCTAssertEqual(r.x, -73.5)
        let e = try decode(ColoEventDto.self, #"{"key": "k", "name": "n", "mainRoom": "151", "start": "s", "end": "e", "halfDay": "TRUE", "talkCount": "12"}"#)
        XCTAssertTrue(e.halfDay)
        XCTAssertEqual(e.talkCount, 12)
    }

    func testIntegerFieldsFollowKotlinx() throws {
        // kotlinx Int: integer literals; whole exponent forms; no fraction, no booleans, 32-bit.
        XCTAssertEqual(try Int(json: JSON.parse("3")), 3)
        XCTAssertEqual(try Int(json: JSON.parse("-3")), -3)
        XCTAssertEqual(try Int(json: JSON.parse("3e2")), 300)
        XCTAssertEqual(try Int(json: JSON.parse("\"42\"")), 42)
        XCTAssertThrowsError(try Int(json: JSON.parse("3.0")))
        XCTAssertThrowsError(try Int(json: JSON.parse("true")))
        XCTAssertThrowsError(try Int(json: JSON.parse("15e-1")))
        XCTAssertThrowsError(try Int(json: JSON.parse("2147483648")))
        XCTAssertEqual(try Int(json: JSON.parse("2147483647")), 2_147_483_647)
        XCTAssertEqual(try Int64(json: JSON.parse("2147483648")), 2_147_483_648)
        XCTAssertThrowsError(try Int64(json: JSON.parse("9223372036854775808")))
        XCTAssertThrowsError(try Int(json: JSON.parse("\" 42\"")))
        XCTAssertThrowsError(try Int(json: JSON.parse("\"\"")))
        // Doubles: any number, a numeric string; never non-finite.
        XCTAssertEqual(try Double(json: JSON.parse("3")), 3.0)
        XCTAssertEqual(try Double(json: JSON.parse("\"2.5\"")), 2.5)
        XCTAssertThrowsError(try Double(json: JSON.parse("1e999")))
        XCTAssertThrowsError(try Double(json: JSON.parse("\"NaN\"")))
        XCTAssertThrowsError(try Double(json: JSON.parse("false")))
    }

    func testMapsKeepFileOrder() throws {
        let m = try JSON.decode(OrderedMap<String, String>.self, from: #"{"z": "1", "a": "2", "m": "3"}"#)
        XCTAssertEqual(m.keys, ["z", "a", "m"])
        XCTAssertThrowsError(try JSON.decode(OrderedMap<String, String>.self, from: #"{"z": {}}"#))
    }

    func testOptionalElementsAndJSONValueFields() throws {
        XCTAssertEqual(try [String?](json: JSON.parse(#"["a", null]"#)), ["a", nil])
        XCTAssertEqual(try JSONValue(json: JSON.parse("[1]")), [1])
    }

    func testObjectBuilderDropsNilsAndDefaults() {
        var o = JSONObjectBuilder()
        o.put("description", "D")
        o.put("speakers", [String](), unlessEqualTo: [])
        o.put("count", 3, unlessEqualTo: 0)
        o.putIfNotNil("slides", nil as String?)
        o.putIfNotNil("link", "https://x" as String?)
        XCTAssertEqual(JSON.serialize(o.value), #"{"description":"D","count":3,"link":"https://x"}"#)
        XCTAssertEqual(JSON.encode(["a": 1] as OrderedMap<String, Int>), #"{"a":1}"#)
    }

    func testKotlinxLongGrammar() throws {
        XCTAssertEqual(try kotlinxLong("0"), 0)
        XCTAssertEqual(try kotlinxLong("-9223372036854775808"), Int64.min)
        XCTAssertEqual(try kotlinxLong("1E+3"), 1000)
        XCTAssertEqual(try kotlinxLong("20e-1"), 2)
        XCTAssertThrowsError(try kotlinxLong("25e-1")) // 2.5: "Can't convert"
        XCTAssertThrowsError(try kotlinxLong("+1"))
        XCTAssertThrowsError(try kotlinxLong("1-"))
        XCTAssertThrowsError(try kotlinxLong("1e"))
        XCTAssertThrowsError(try kotlinxLong("1e30")) // overflow
    }

    func testKotlinxLongExponentFormsAtTheInt64Limits() throws {
        // The exponent form goes through a Double: 2^63 must throw (kotlinx "Numeric value
        // overflow"), never trap; -2^63 is Long.MIN_VALUE.
        for bad in ["92233720368547758e2", "9223372036854775807e0", "9223372036854775808e0", "1e19", "0e99999"] {
            XCTAssertThrowsError(try kotlinxLong(bad), bad)
            XCTAssertThrowsError(try Int64(json: JSON.parse(bad)), bad)
            XCTAssertThrowsError(try Int(json: JSON.parse(bad)), bad)
            XCTAssertThrowsError(try Int64(json: .string(bad)), bad)
        }
        XCTAssertEqual(try kotlinxLong("-92233720368547758e2"), Int64.min)
        XCTAssertEqual(try kotlinxLong("-9223372036854775808e0"), Int64.min)
        XCTAssertEqual(try Int64(json: JSON.parse("-92233720368547758e2")), Int64.min)
        XCTAssertEqual(try kotlinxLong("4611686018427387904e0"), 4_611_686_018_427_387_904) // 2^62
        XCTAssertEqual(try kotlinxLong("-4611686018427387904e0"), -4_611_686_018_427_387_904)
        XCTAssertEqual(try kotlinxLong("0e-99999"), 0)
        XCTAssertEqual(try kotlinxLong("-0e5"), 0)
        XCTAssertThrowsError(try kotlinxLong("-15e-1")) // -1.5
    }
}
