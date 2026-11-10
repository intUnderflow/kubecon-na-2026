import Foundation

// An order-preserving JSON parser and serializer: the port of kotlinx-serialization's
// `Json.parseToJsonElement` / `JsonElement.toString()` (and the decoding side, in
// JSONDecoding.swift, of `Json { ignoreUnknownKeys; explicitNulls = false; coerceInputValues;
// isLenient }.decodeFromString`). `JSONDecoder` is not used for the data files: it loses
// object key order, which the app depends on (rooms, entrances, nodes, categories...).
//
//     let root = try JSON.parse(data)                  // JSONValue
//     root["sessions"]?.arrayValue?.count
//     let dto = try JSON.decode(ScheduleFileDto.self, from: data)
//     JSON.serialize(root)                             // compact, like JsonElement.toString()
//     JSON.serialize(root, pretty: true)               // 4-space indent, like prettyPrint

/// A parsed JSON value. Objects keep their key order (``OrderedMap``); a key repeated in one
/// object keeps its first position and its last value (like kotlinx's `LinkedHashMap`).
enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(JSONNumber)
    case string(String)
    case array([JSONValue])
    case object(OrderedMap<String, JSONValue>)
}

/// A JSON number, kept as written (like kotlinx's `JsonLiteral.content`), so `3`, `3.0` and
/// `3e0` stay distinguishable and re-serialize unchanged. Equality compares the literal text
/// (as kotlinx does): `3` != `3.0`.
struct JSONNumber: Sendable, Hashable, CustomStringConvertible {
    /// The number as written in the source ("84300.0", "-73", "1e3").
    let literal: String
    /// True when written as a plain integer (no fraction, no exponent).
    let isInteger: Bool
    /// The value when written as a plain integer that fits Int64; nil otherwise.
    let int64Value: Int64?
    /// The value as a Double (always set; `inf` only for absurd literals like 1e999).
    let doubleValue: Double

    init(_ value: Int) {
        literal = String(value)
        isInteger = true
        int64Value = Int64(value)
        doubleValue = Double(value)
    }

    init(_ value: Int64) {
        literal = String(value)
        isInteger = true
        int64Value = value
        doubleValue = Double(value)
    }

    /// A double; written with Swift's shortest round-trip form ("3.0", "0.1", "1e+20").
    /// A non-finite value is written as `null` (JSON has no NaN/Infinity), like JS JSON.stringify.
    init(_ value: Double) {
        literal = value.isFinite ? value.description : "null"
        isInteger = false
        int64Value = nil
        doubleValue = value
    }

    /// Parsed from source (the literal is already validated).
    fileprivate init(validLiteral: String, isInteger: Bool, int64Value: Int64?, doubleValue: Double) {
        literal = validLiteral
        self.isInteger = isInteger
        self.int64Value = int64Value
        self.doubleValue = doubleValue
    }

    /// The value as an Int when written as an integer that fits.
    var intValue: Int? { int64Value.flatMap { Int(exactly: $0) } }

    var description: String { literal }

    static func == (a: JSONNumber, b: JSONNumber) -> Bool { a.literal == b.literal }
    func hash(into hasher: inout Hasher) { hasher.combine(literal) }
}

// MARK: - Accessors

extension JSONValue {
    /// The string, if this is a JSON string.
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// The boolean, if this is `true` / `false`.
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// The number, if this is a JSON number.
    var numberValue: JSONNumber? {
        if case .number(let n) = self { return n }
        return nil
    }

    /// The value of a number written as an integer that fits `Int` (3 -> 3; 3.0 -> nil).
    var intValue: Int? { numberValue?.intValue }

    /// The value of a number written as an integer that fits `Int64`.
    var int64Value: Int64? { numberValue?.int64Value }

    /// Any number as a Double (3 -> 3.0).
    var doubleValue: Double? { numberValue?.doubleValue }

    /// The elements, if this is an array.
    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// The members, in file order, if this is an object.
    var objectValue: OrderedMap<String, JSONValue>? {
        if case .object(let o) = self { return o }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Kotlin `jsonPrimitive.content`: a string's text, a number's literal, "true"/"false",
    /// "null"; nil for arrays and objects.
    var primitiveContent: String? {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n.literal
        case .string(let s): return s
        case .array, .object: return nil
        }
    }

    /// `object[key]`; nil when this is not an object or has no such key.
    subscript(key: String) -> JSONValue? { objectValue?[key] }

    /// `array[i]`; nil when this is not an array or `i` is out of range.
    subscript(index: Int) -> JSONValue? {
        guard case .array(let a) = self, index >= 0, index < a.count else { return nil }
        return a[index]
    }

    /// "object", "array", "string", "number", "boolean" or "null" (for error messages).
    var kindName: String {
        switch self {
        case .null: return "null"
        case .bool: return "boolean"
        case .number: return "number"
        case .string: return "string"
        case .array: return "array"
        case .object: return "object"
        }
    }

    /// Compact JSON (`JsonElement.toString()`).
    var compactString: String { JSON.serialize(self) }

    /// Pretty JSON with a 4-space indent (kotlinx `prettyPrint`).
    var prettyString: String { JSON.serialize(self, pretty: true) }
}

extension JSONValue: CustomStringConvertible {
    var description: String { compactString }
}

// MARK: - Literals

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    init(nilLiteral: ()) { self = .null }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .number(JSONNumber(value)) }
    init(floatLiteral value: Double) { self = .number(JSONNumber(value)) }
    init(stringLiteral value: String) { self = .string(value) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    /// Keeps the literal's key order.
    init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(OrderedMap(elements)) }
}

// MARK: - Errors

/// Malformed JSON text.
struct JSONParseError: Error, CustomStringConvertible, Equatable {
    let message: String
    /// Byte offset of the problem in the UTF-8 input.
    let offset: Int
    /// 1-based line and column (in bytes) of the problem.
    let line: Int
    let column: Int

    var description: String { "JSON parse error at line \(line), column \(column) (offset \(offset)): \(message)" }
}

// MARK: - Entry points

/// JSON parsing and writing (the shared `Repository.json` of the Kotlin code).
enum JSON {
    /// Maximum nesting depth of arrays/objects; deeper input is rejected (protects the stack).
    static let maxDepth = 200

    /// Parses UTF-8 JSON. Invalid UTF-8 inside strings becomes U+FFFD (like Kotlin's
    /// `toString(Charsets.UTF_8)`); any grammar error throws ``JSONParseError``.
    static func parse(_ data: Data) throws -> JSONValue {
        try data.withUnsafeBytes { raw -> JSONValue in
            let buf = raw.bindMemory(to: UInt8.self)
            return try parse(buf)
        }
    }

    /// Parses JSON text.
    static func parse(_ text: String) throws -> JSONValue {
        var t = text
        return try t.withUTF8 { try parse($0) }
    }

    /// Parses UTF-8 bytes.
    static func parse(_ bytes: UnsafeBufferPointer<UInt8>) throws -> JSONValue {
        guard let base = bytes.baseAddress, bytes.count > 0 else {
            throw JSONParseError(message: "Unexpected end of input, expected a value", offset: 0, line: 1, column: 1)
        }
        var p = JSONParser(base: base, count: bytes.count)
        let v = try p.parseValue()
        p.skipWhitespace()
        if p.i != p.n { throw p.error("Unexpected trailing content '\(p.charDescription(p.i))' after the JSON value") }
        return v
    }

    /// Parses and decodes (kotlinx `Json.decodeFromString`).
    static func decode<T: JSONDecodable>(_ type: T.Type, from data: Data) throws -> T {
        try T(json: parse(data))
    }

    /// Parses and decodes text.
    static func decode<T: JSONDecodable>(_ type: T.Type, from text: String) throws -> T {
        try T(json: parse(text))
    }

    /// Writes `value` as JSON text: compact (`{"a":1,"b":[true,null]}`) or pretty (4-space
    /// indent, `"key": value`, one member per line; empty containers as `{}` / `[]`).
    /// Strings escape `"`, `\` and control characters only (non-ASCII is written as is).
    static func serialize(_ value: JSONValue, pretty: Bool = false) -> String {
        var w = JSONWriter(pretty: pretty)
        w.write(value, level: 0)
        return String(decoding: w.out, as: UTF8.self)
    }

    /// As ``serialize(_:pretty:)``, as UTF-8 data.
    static func serializedData(_ value: JSONValue, pretty: Bool = false) -> Data {
        var w = JSONWriter(pretty: pretty)
        w.write(value, level: 0)
        return Data(w.out)
    }

    /// Encodes and writes (kotlinx `Json.encodeToString`).
    static func encode<T: JSONEncodable>(_ value: T, pretty: Bool = false) -> String {
        serialize(value.toJSON(), pretty: pretty)
    }
}

// MARK: - Parser

private struct JSONParser {
    let p: UnsafePointer<UInt8>
    let n: Int
    var i = 0
    var depth = 0

    init(base: UnsafePointer<UInt8>, count: Int) {
        p = base
        n = count
    }

    // Byte constants.
    private static let quote: UInt8 = 0x22, backslash: UInt8 = 0x5C, slash: UInt8 = 0x2F
    private static let comma: UInt8 = 0x2C, colon: UInt8 = 0x3A
    private static let lbrace: UInt8 = 0x7B, rbrace: UInt8 = 0x7D, lbracket: UInt8 = 0x5B, rbracket: UInt8 = 0x5D
    private static let minus: UInt8 = 0x2D, plus: UInt8 = 0x2B, dot: UInt8 = 0x2E
    private static let zero: UInt8 = 0x30, nine: UInt8 = 0x39

    func error(_ message: String, at offset: Int? = nil) -> JSONParseError {
        let off = Swift.min(offset ?? i, n)
        var line = 1, col = 1
        var k = 0
        while k < off {
            if p[k] == 0x0A { line += 1; col = 1 } else { col += 1 }
            k += 1
        }
        return JSONParseError(message: message, offset: off, line: line, column: col)
    }

    func charDescription(_ at: Int) -> String {
        guard at < n else { return "EOF" }
        let c = p[at]
        if c >= 0x20 && c < 0x7F { return String(UnicodeScalar(c)) }
        return String(format: "0x%02X", c)
    }

    @inline(__always)
    mutating func skipWhitespace() {
        while i < n {
            let c = p[i]
            if c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 { i += 1 } else { return }
        }
    }

    mutating func parseValue() throws -> JSONValue {
        skipWhitespace()
        guard i < n else { throw error("Unexpected end of input, expected a value") }
        switch p[i] {
        case Self.lbrace: return try parseObject()
        case Self.lbracket: return try parseArray()
        case Self.quote: return .string(try parseString())
        case 0x74: try expectWord("true"); return .bool(true) // t
        case 0x66: try expectWord("false"); return .bool(false) // f
        case 0x6E: try expectWord("null"); return .null // n
        case Self.minus, Self.zero...Self.nine: return .number(try parseNumber())
        default: throw error("Unexpected character '\(charDescription(i))', expected a value")
        }
    }

    private mutating func expectWord(_ word: StaticString) throws {
        let len = word.utf8CodeUnitCount
        let w = word.utf8Start
        guard i + len <= n else { throw error("Unexpected end of input, expected '\(word)'") }
        for k in 0..<len where p[i + k] != w[k] {
            throw error("Unexpected character '\(charDescription(i + k))', expected '\(word)'", at: i + k)
        }
        i += len
    }

    private mutating func enter() throws {
        depth += 1
        if depth > JSON.maxDepth { throw error("Nesting deeper than \(JSON.maxDepth) levels") }
    }

    private mutating func parseObject() throws -> JSONValue {
        try enter()
        i += 1 // {
        var map = OrderedMap<String, JSONValue>()
        skipWhitespace()
        if i < n && p[i] == Self.rbrace {
            i += 1
            depth -= 1
            return .object(map)
        }
        while true {
            skipWhitespace()
            guard i < n else { throw error("Unexpected end of input in an object") }
            guard p[i] == Self.quote else {
                throw error("Expected a quoted key, found '\(charDescription(i))'")
            }
            let key = try parseString()
            skipWhitespace()
            guard i < n, p[i] == Self.colon else { throw error("Expected ':' after key \"\(key)\", found '\(charDescription(i))'") }
            i += 1
            let value = try parseValue()
            map.updateValue(value, forKey: key)
            skipWhitespace()
            guard i < n else { throw error("Unexpected end of input in an object, expected ',' or '}'") }
            let c = p[i]
            i += 1
            if c == Self.comma { continue }
            if c == Self.rbrace { break }
            throw error("Expected ',' or '}' in an object, found '\(charDescription(i - 1))'", at: i - 1)
        }
        depth -= 1
        return .object(map)
    }

    private mutating func parseArray() throws -> JSONValue {
        try enter()
        i += 1 // [
        var items: [JSONValue] = []
        skipWhitespace()
        if i < n && p[i] == Self.rbracket {
            i += 1
            depth -= 1
            return .array(items)
        }
        while true {
            items.append(try parseValue())
            skipWhitespace()
            guard i < n else { throw error("Unexpected end of input in an array, expected ',' or ']'") }
            let c = p[i]
            i += 1
            if c == Self.comma { continue }
            if c == Self.rbracket { break }
            throw error("Expected ',' or ']' in an array, found '\(charDescription(i - 1))'", at: i - 1)
        }
        depth -= 1
        return .array(items)
    }

    /// Offset of the next `byte` at or after `from`, or nil (memchr: fast even in debug builds).
    @inline(__always)
    private func find(_ byte: UInt8, from: Int, to end: Int) -> Int? {
        guard from < end, let r = memchr(p + from, Int32(byte), end - from) else { return nil }
        return UnsafePointer<UInt8>(r.assumingMemoryBound(to: UInt8.self)) - p
    }

    /// Parses a string starting at its opening quote. Raw control characters are accepted
    /// (kotlinx accepts them too). Linear in the string's length: the next quote is searched
    /// again only once an escape (`\"`) has consumed it.
    private mutating func parseString() throws -> String {
        let open = i
        i += 1
        let start = i
        var buffer: [UInt8]? = nil
        var nextQuote: Int? = nil
        while true {
            if nextQuote == nil || nextQuote! < i { nextQuote = find(Self.quote, from: i, to: n) }
            guard let q = nextQuote else {
                throw error("Unterminated string", at: open)
            }
            if let b = find(Self.backslash, from: i, to: q) {
                if buffer == nil {
                    buffer = []
                    buffer!.reserveCapacity(q - start + 16)
                }
                buffer!.append(contentsOf: UnsafeBufferPointer(start: p + i, count: b - i))
                i = b + 1
                try parseEscape(into: &buffer!)
                continue
            }
            // No escape before the closing quote.
            let s: String
            if var buf = buffer {
                buf.append(contentsOf: UnsafeBufferPointer(start: p + i, count: q - i))
                s = String(decoding: buf, as: UTF8.self)
            } else {
                s = String(decoding: UnsafeBufferPointer(start: p + start, count: q - start), as: UTF8.self)
            }
            i = q + 1
            return s
        }
    }

    /// After a backslash at i-1.
    private mutating func parseEscape(into out: inout [UInt8]) throws {
        guard i < n else { throw error("Unexpected end of input in an escape sequence") }
        let c = p[i]
        i += 1
        switch c {
        case Self.quote: out.append(0x22)
        case Self.backslash: out.append(0x5C)
        case Self.slash: out.append(0x2F)
        case 0x62: out.append(0x08) // b
        case 0x66: out.append(0x0C) // f
        case 0x6E: out.append(0x0A) // n
        case 0x72: out.append(0x0D) // r
        case 0x74: out.append(0x09) // t
        case 0x75: // u
            let u1 = try hex4()
            var scalar: UInt32
            if u1 >= 0xD800 && u1 <= 0xDBFF {
                // A high surrogate: combine with a following \uDC00-\uDFFF, else U+FFFD.
                if i + 6 <= n, p[i] == Self.backslash, p[i + 1] == 0x75, let u2 = hex4(at: i + 2), u2 >= 0xDC00 && u2 <= 0xDFFF {
                    i += 6
                    scalar = 0x10000 + ((UInt32(u1) - 0xD800) << 10) + (UInt32(u2) - 0xDC00)
                } else {
                    scalar = 0xFFFD // lone high surrogate (Kotlin keeps it; Swift strings cannot)
                }
            } else if u1 >= 0xDC00 && u1 <= 0xDFFF {
                scalar = 0xFFFD // lone low surrogate
            } else {
                scalar = UInt32(u1)
            }
            appendUTF8(scalar, to: &out)
        default:
            throw error("Invalid escaped char '\(charDescription(i - 1))'", at: i - 1)
        }
    }

    private mutating func hex4() throws -> UInt16 {
        guard let v = hex4(at: i) else {
            throw error("Invalid \\u escape: expected 4 hex digits", at: i)
        }
        i += 4
        return v
    }

    private func hex4(at k: Int) -> UInt16? {
        guard k + 4 <= n else { return nil }
        var v: UInt16 = 0
        for j in 0..<4 {
            let c = p[k + j]
            let d: UInt16
            switch c {
            case 0x30...0x39: d = UInt16(c - 0x30)
            case 0x41...0x46: d = UInt16(c - 0x41 + 10)
            case 0x61...0x66: d = UInt16(c - 0x61 + 10)
            default: return nil
            }
            v = v << 4 | d
        }
        return v
    }

    private func appendUTF8(_ v: UInt32, to out: inout [UInt8]) {
        switch v {
        case 0..<0x80:
            out.append(UInt8(v))
        case 0x80..<0x800:
            out.append(UInt8(0xC0 | (v >> 6)))
            out.append(UInt8(0x80 | (v & 0x3F)))
        case 0x800..<0x10000:
            out.append(UInt8(0xE0 | (v >> 12)))
            out.append(UInt8(0x80 | ((v >> 6) & 0x3F)))
            out.append(UInt8(0x80 | (v & 0x3F)))
        default:
            out.append(UInt8(0xF0 | (v >> 18)))
            out.append(UInt8(0x80 | ((v >> 12) & 0x3F)))
            out.append(UInt8(0x80 | ((v >> 6) & 0x3F)))
            out.append(UInt8(0x80 | (v & 0x3F)))
        }
    }

    @inline(__always)
    private func isDigit(_ k: Int) -> Bool { k < n && p[k] >= Self.zero && p[k] <= Self.nine }

    /// RFC 8259 number: -?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?
    private mutating func parseNumber() throws -> JSONNumber {
        let start = i
        var negative = false
        if p[i] == Self.minus {
            negative = true
            i += 1
        }
        guard isDigit(i) else { throw error("Expected a digit in a number, found '\(charDescription(i))'") }
        // Integer part, accumulated (negatively, to reach Int64.min) while it fits.
        var acc: Int64 = 0
        var fits = true
        if p[i] == Self.zero {
            i += 1
        } else {
            while isDigit(i) {
                let d = Int64(p[i] - Self.zero)
                if fits {
                    let (m, o1) = acc.multipliedReportingOverflow(by: 10)
                    let (s, o2) = m.subtractingReportingOverflow(d)
                    if o1 || o2 { fits = false } else { acc = s }
                }
                i += 1
            }
        }
        var isInteger = true
        if i < n && p[i] == Self.dot {
            isInteger = false
            i += 1
            guard isDigit(i) else { throw error("Expected a digit after '.' in a number, found '\(charDescription(i))'") }
            while isDigit(i) { i += 1 }
        }
        if i < n && (p[i] == 0x65 || p[i] == 0x45) { // e E
            isInteger = false
            i += 1
            if i < n && (p[i] == Self.plus || p[i] == Self.minus) { i += 1 }
            guard isDigit(i) else { throw error("Expected a digit in a number's exponent, found '\(charDescription(i))'") }
            while isDigit(i) { i += 1 }
        }
        let literal = String(decoding: UnsafeBufferPointer(start: p + start, count: i - start), as: UTF8.self)
        var int64: Int64? = nil
        if isInteger && fits {
            if negative {
                int64 = acc
            } else if acc != Int64.min {
                int64 = -acc
            }
        }
        let dbl: Double
        if let v = int64, v != 0 || !negative {
            dbl = Double(v)
        } else if int64 != nil {
            dbl = -0.0 // "-0": kotlinx's "-0".toDouble() is -0.0 (int64Value stays 0)
        } else {
            dbl = Double(literal) ?? (negative ? -.infinity : .infinity)
        }
        return JSONNumber(validLiteral: literal, isInteger: isInteger, int64Value: int64, doubleValue: dbl)
    }
}

// MARK: - Writer

private struct JSONWriter {
    var out: [UInt8] = []
    let pretty: Bool

    init(pretty: Bool) {
        self.pretty = pretty
        out.reserveCapacity(1024)
    }

    private mutating func newline(_ level: Int) {
        out.append(0x0A)
        for _ in 0..<(level * 4) { out.append(0x20) }
    }

    mutating func write(_ v: JSONValue, level: Int) {
        switch v {
        case .null: out.append(contentsOf: "null".utf8)
        case .bool(let b): out.append(contentsOf: (b ? "true" : "false").utf8)
        case .number(let num): out.append(contentsOf: num.literal.utf8)
        case .string(let s): writeString(s)
        case .array(let a):
            if a.isEmpty {
                out.append(contentsOf: "[]".utf8)
                return
            }
            out.append(0x5B)
            for (k, e) in a.enumerated() {
                if k > 0 { out.append(0x2C) }
                if pretty { newline(level + 1) }
                write(e, level: level + 1)
            }
            if pretty { newline(level) }
            out.append(0x5D)
        case .object(let o):
            if o.isEmpty {
                out.append(contentsOf: "{}".utf8)
                return
            }
            out.append(0x7B)
            var first = true
            for (key, e) in o {
                if !first { out.append(0x2C) }
                first = false
                if pretty { newline(level + 1) }
                writeString(key)
                out.append(0x3A)
                if pretty { out.append(0x20) }
                write(e, level: level + 1)
            }
            if pretty { newline(level) }
            out.append(0x7D)
        }
    }

    private mutating func writeString(_ s: String) {
        out.append(0x22)
        for c in s.utf8 {
            switch c {
            case 0x22: out.append(0x5C); out.append(0x22)
            case 0x5C: out.append(0x5C); out.append(0x5C)
            case 0x0A: out.append(0x5C); out.append(0x6E)
            case 0x0D: out.append(0x5C); out.append(0x72)
            case 0x09: out.append(0x5C); out.append(0x74)
            case 0x08: out.append(0x5C); out.append(0x62)
            case 0x0C: out.append(0x5C); out.append(0x66)
            case 0..<0x20:
                let hex = Array("0123456789abcdef".utf8)
                out.append(contentsOf: "\\u00".utf8)
                out.append(hex[Int(c >> 4)])
                out.append(hex[Int(c & 0xF)])
            default: out.append(c)
            }
        }
        out.append(0x22)
    }
}
