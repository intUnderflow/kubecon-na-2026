import Foundation

// Decoding typed values from a JSONValue with the semantics of the Kotlin app's kotlinx config
// (Repository.json):
//
//     Json { ignoreUnknownKeys = true; explicitNulls = false; coerceInputValues = true; isLenient = true }
//
// - unknown keys are ignored (just don't read them);
// - a missing key, or `null`, for a field with a default gives the default
//   (``JSONFields/value(_:default:)``); for a nullable field gives nil (``JSONFields/optional(_:)``);
// - a missing key or `null` for a required non-null field throws (``JSONFields/required(_:)``);
// - a wrong type throws, except what `isLenient` allows: a number or boolean token where a
//   string is expected gives its literal text, a quoted "true"/"false" is a boolean;
//   and (as kotlinx always does) a quoted number such as "42" is accepted for a number.
//
//     struct EntranceDto: JSONDecodable {
//         let name: String
//         let node: String
//         init(json: JSONValue) throws {
//             let o = try JSONFields(json, "EntranceDto")
//             name = try o.required("name")
//             node = try o.required("node")
//         }
//     }
//     let e = try JSON.decode(EntranceDto.self, from: data)

/// A type that can be built from a ``JSONValue`` (a kotlinx `@Serializable` class's decoder).
protocol JSONDecodable {
    init(json: JSONValue) throws
}

/// A type that can be written as a ``JSONValue`` (for caches and stores).
protocol JSONEncodable {
    func toJSON() -> JSONValue
}

/// A value of the wrong shape for its type. `path` locates it ("$.sessions[3].start").
struct JSONDecodingError: Error, CustomStringConvertible, Equatable {
    /// Path components from the root: ".key" or "[index]".
    var path: [String]
    let message: String

    init(_ message: String, path: [String] = []) {
        self.message = message
        self.path = path
    }

    /// The JSONPath-like location: "$" for the root.
    var location: String { "$" + path.joined() }

    var description: String { "\(location): \(message)" }

    /// The same error one level further down (used while unwinding).
    func prefixed(_ component: String) -> JSONDecodingError {
        JSONDecodingError(message, path: [component] + path)
    }

    static func typeMismatch(_ expected: String, _ found: JSONValue) -> JSONDecodingError {
        let shown: String
        switch found {
        case .array, .object: shown = found.kindName
        default: shown = "\(found.kindName) \(found.primitiveContent ?? "")"
        }
        return JSONDecodingError("Expected \(expected), found \(shown)")
    }
}

/// Reads the members of a JSON object for a DTO initializer (see the file comment).
struct JSONFields {
    /// The object's members.
    let fields: OrderedMap<String, JSONValue>
    /// The DTO type's name (error messages).
    let typeName: String

    /// Fails unless `value` is an object.
    init(_ value: JSONValue, _ typeName: String) throws {
        guard case .object(let o) = value else {
            throw JSONDecodingError.typeMismatch("an object for \(typeName)", value)
        }
        fields = o
        self.typeName = typeName
    }

    /// True when the object has `key` (even with a null value).
    func contains(_ key: String) -> Bool { fields.containsKey(key) }

    /// A required, non-null field (no default in the Kotlin DTO): missing or null throws.
    func required<T: JSONDecodable>(_ key: String, as type: T.Type = T.self) throws -> T {
        guard let v = fields[key] else {
            throw JSONDecodingError("Field '\(key)' is required for type '\(typeName)', but it was missing")
        }
        if case .null = v {
            throw JSONDecodingError("Field '\(key)' of type '\(typeName)' is not nullable, but the value was null", path: [".\(key)"])
        }
        return try decode(key, v)
    }

    /// A field with a Kotlin default: missing or null gives `defaultValue`
    /// (explicitNulls = false + coerceInputValues = true).
    func value<T: JSONDecodable>(_ key: String, default defaultValue: @autoclosure () -> T) throws -> T {
        guard let v = fields[key], !v.isNull else { return defaultValue() }
        return try decode(key, v)
    }

    /// A nullable field (`val x: T? = null`): missing or null gives nil.
    func optional<T: JSONDecodable>(_ key: String, as type: T.Type = T.self) throws -> T? {
        guard let v = fields[key], !v.isNull else { return nil }
        return try decode(key, v)
    }

    private func decode<T: JSONDecodable>(_ key: String, _ v: JSONValue) throws -> T {
        do {
            return try T(json: v)
        } catch let e as JSONDecodingError {
            throw e.prefixed(".\(key)")
        }
    }
}

// MARK: - kotlinx number rules

/// kotlinx `consumeNumericLiteral` (used for Int and Long): `-?digits([eE][+-]?digits)?`; an
/// exponent form must come out whole ("3e2" = 300); a fraction ("3.0") is rejected.
func kotlinxLong(_ text: String) throws -> Int64 {
    let u = Array(text.utf8)
    guard !u.isEmpty else { throw JSONDecodingError("Expected numeric literal, found empty string") }
    var k = 0
    var negative = false
    if u[0] == 0x2D {
        negative = true
        k = 1
    }
    var mantissa: Int64 = 0 // accumulated negatively, to reach Int64.min
    var digits = 0
    while k < u.count, u[k] >= 0x30, u[k] <= 0x39 {
        let (m, o1) = mantissa.multipliedReportingOverflow(by: 10)
        let (s, o2) = m.subtractingReportingOverflow(Int64(u[k] - 0x30))
        if o1 || o2 { throw JSONDecodingError("Numeric value overflow: \(text)") }
        mantissa = s
        digits += 1
        k += 1
    }
    guard digits > 0 else { throw JSONDecodingError("Expected numeric literal, found '\(text)'") }
    var exponent = 0
    var hasExponent = false
    if k < u.count, u[k] == 0x65 || u[k] == 0x45 {
        hasExponent = true
        k += 1
        var expNegative = false
        if k < u.count, u[k] == 0x2B || u[k] == 0x2D {
            expNegative = u[k] == 0x2D
            k += 1
        }
        var expDigits = 0
        while k < u.count, u[k] >= 0x30, u[k] <= 0x39 {
            exponent = Swift.min(exponent * 10 + Int(u[k] - 0x30), 10_000)
            expDigits += 1
            k += 1
        }
        guard expDigits > 0 else { throw JSONDecodingError("Unexpected end of numeric literal '\(text)'") }
        if expNegative { exponent = -exponent }
    }
    guard k == u.count else {
        throw JSONDecodingError("Unexpected symbol '\(Character(UnicodeScalar(u[k])))' in numeric literal '\(text)'")
    }
    if !hasExponent {
        if negative { return mantissa }
        guard mantissa != Int64.min else { throw JSONDecodingError("Numeric value overflow: \(text)") }
        return -mantissa
    }
    // As kotlinx: scale the NEGATIVE accumulator (so -2^63 is reachable), range-check it
    // against Long.MIN_VALUE, convert, then negate for a positive literal; a positive value that
    // comes out as -2^63 ("9223372036854775807e0" rounds to 2^63) overflows. NaN (0e99999) fails
    // the range check. `Int64(_:)` below only ever sees a whole value in [-2^63, 0].
    let scaled = Double(mantissa) * pow(10.0, Double(exponent))
    guard scaled >= -9.223372036854775808e18, scaled <= 0 else {
        throw JSONDecodingError("Numeric value overflow: \(text)")
    }
    guard scaled.rounded(.down) == scaled else {
        throw JSONDecodingError("Can't convert \(negative ? scaled : -scaled) to Long")
    }
    let accumulator = Int64(scaled)
    if negative { return accumulator }
    guard accumulator != Int64.min else { throw JSONDecodingError("Numeric value overflow: \(text)") }
    return -accumulator
}

// MARK: - Conformances: primitives

extension String: JSONDecodable, JSONEncodable {
    /// A string; with isLenient also a number's literal or "true"/"false".
    init(json: JSONValue) throws {
        switch json {
        case .string(let s): self = s
        case .number(let n): self = n.literal
        case .bool(let b): self = b ? "true" : "false"
        default: throw JSONDecodingError.typeMismatch("a string", json)
        }
    }

    func toJSON() -> JSONValue { .string(self) }
}

extension Int64: JSONDecodable, JSONEncodable {
    /// kotlinx `Long`: a number (or quoted number) per ``kotlinxLong(_:)``.
    init(json: JSONValue) throws {
        switch json {
        case .number(let n):
            if let v = n.int64Value { self = v } else { self = try kotlinxLong(n.literal) }
        case .string(let s): self = try kotlinxLong(s)
        default: throw JSONDecodingError.typeMismatch("a number (Long)", json)
        }
    }

    func toJSON() -> JSONValue { .number(JSONNumber(self)) }
}

extension Int: JSONDecodable, JSONEncodable {
    /// kotlinx `Int`: as Long, and it must fit 32 bits (Kotlin `Int`).
    init(json: JSONValue) throws {
        let v = try Int64(json: json)
        guard let i = Int32(exactly: v) else { throw JSONDecodingError("Failed to parse type 'int' for input '\(v)'") }
        self = Int(i)
    }

    func toJSON() -> JSONValue { .number(JSONNumber(self)) }
}

extension Double: JSONDecodable, JSONEncodable {
    /// kotlinx `Double`: any number literal, or a string that parses as one; must be finite.
    init(json: JSONValue) throws {
        let v: Double
        switch json {
        case .number(let n): v = n.doubleValue
        case .string(let s):
            guard let d = Double(s.javaTrim()) else { throw JSONDecodingError("Failed to parse type 'double' for input '\(s)'") }
            v = d
        default: throw JSONDecodingError.typeMismatch("a number (Double)", json)
        }
        guard v.isFinite else {
            throw JSONDecodingError("Unexpected special floating-point value \(v). By default, non-finite floating point values are prohibited")
        }
        self = v
    }

    func toJSON() -> JSONValue { .number(JSONNumber(self)) }
}

extension Bool: JSONDecodable, JSONEncodable {
    /// `true` / `false`; with isLenient also a quoted "true"/"false" (any letter case).
    init(json: JSONValue) throws {
        switch json {
        case .bool(let b): self = b
        case .string(let s) where s.lowercased() == "true": self = true
        case .string(let s) where s.lowercased() == "false": self = false
        default: throw JSONDecodingError.typeMismatch("a boolean", json)
        }
    }

    func toJSON() -> JSONValue { .bool(self) }
}

extension JSONValue: JSONDecodable, JSONEncodable {
    /// Any value as is (a kotlinx `JsonElement` field).
    init(json: JSONValue) throws { self = json }

    func toJSON() -> JSONValue { self }
}

// MARK: - Conformances: containers

extension Array: JSONDecodable where Element: JSONDecodable {
    /// A JSON array; a `null` element of a non-null type throws, like kotlinx.
    init(json: JSONValue) throws {
        guard case .array(let a) = json else { throw JSONDecodingError.typeMismatch("an array", json) }
        var out: [Element] = []
        out.reserveCapacity(a.count)
        for (i, e) in a.enumerated() {
            do {
                out.append(try Element(json: e))
            } catch let err as JSONDecodingError {
                throw err.prefixed("[\(i)]")
            }
        }
        self = out
    }
}

extension Array: JSONEncodable where Element: JSONEncodable {
    func toJSON() -> JSONValue { .array(map { $0.toJSON() }) }
}

extension OrderedMap: JSONDecodable where Key == String, Value: JSONDecodable {
    /// A JSON object as a `Map<String, V>`, in file order.
    init(json: JSONValue) throws {
        guard case .object(let o) = json else { throw JSONDecodingError.typeMismatch("an object (Map)", json) }
        self = try o.mapValuesWithKey { k, v in
            do {
                return try Value(json: v)
            } catch let err as JSONDecodingError {
                throw err.prefixed(".\(k)")
            }
        }
    }
}

extension OrderedMap: JSONEncodable where Key == String, Value: JSONEncodable {
    func toJSON() -> JSONValue { .object(mapValues { $0.toJSON() }) }
}

extension Optional: JSONDecodable where Wrapped: JSONDecodable {
    /// `null` -> nil, anything else decodes as `Wrapped` (a `List<String?>` element).
    init(json: JSONValue) throws {
        if case .null = json { self = nil } else { self = try Wrapped(json: json) }
    }
}

extension Optional: JSONEncodable where Wrapped: JSONEncodable {
    func toJSON() -> JSONValue { self?.toJSON() ?? .null }
}

// MARK: - Writing objects

/// Builds a JSON object for a cache/store file the way kotlinx's `encodeToString` would with
/// the app's config: `explicitNulls = false` drops nil fields (``putIfNotNil(_:_:)``) and the
/// default `encodeDefaults = false` drops fields equal to their default
/// (``put(_:_:unlessEqualTo:)``).
///
/// ```swift
/// var o = JSONObjectBuilder()
/// o.put("description", d.description)
/// o.put("speakers", d.speakers.map { $0.toJSON() }, unlessEqualTo: [])
/// o.putIfNotNil("slides", d.slides)
/// let text = JSON.serialize(o.value)
/// ```
struct JSONObjectBuilder {
    private(set) var fields = OrderedMap<String, JSONValue>()

    init() {}

    /// Always written.
    mutating func put<T: JSONEncodable>(_ key: String, _ value: T) {
        fields.updateValue(value.toJSON(), forKey: key)
    }

    /// Written unless nil (explicitNulls = false).
    mutating func putIfNotNil<T: JSONEncodable>(_ key: String, _ value: T?) {
        if let value { fields.updateValue(value.toJSON(), forKey: key) }
    }

    /// Written unless equal to the Kotlin default (encodeDefaults = false).
    mutating func put<T: JSONEncodable & Equatable>(_ key: String, _ value: T, unlessEqualTo defaultValue: T) {
        if value != defaultValue { fields.updateValue(value.toJSON(), forKey: key) }
    }

    /// The object.
    var value: JSONValue { .object(fields) }
}
