import Foundation

/// An insertion-ordered dictionary: the port of Kotlin's `LinkedHashMap` (what `mapOf`,
/// `associate`, `toMap()` and kotlinx-serialization's `Map` decoding all produce).
///
/// Iteration order is insertion order, and code depends on it (rooms.json order is the web's
/// room sort order, the entrances order is the From menu's, the nodes order is the router's).
/// Use it wherever Kotlin iterates a map; a plain `[K: V]` is fine only for pure lookups.
///
/// Semantics follow `LinkedHashMap`:
/// - `map[k] = v` on an existing key replaces the value and keeps the key's position;
///   on a new key it appends. `map[k] = nil` removes the key (O(n)).
/// - `init(_ pairs:)` / `ExpressibleByDictionaryLiteral`: a repeated key keeps its FIRST
///   position and its LAST value (`toMap()`, `associate`, `put` in a loop).
/// - `==` ignores order, like Kotlin's `Map.equals` (use ``orderedEquals(_:)`` when order
///   matters); `hash(into:)` is order-independent to match.
///
/// Lookup is O(1): small maps (the vast majority of parsed JSON objects) scan their keys
/// linearly, larger ones keep a `[Key: Int]` index.
///
/// ```swift
/// var m: OrderedMap = ["E200S": 1, "EWT": 2]
/// m["EHY"] = 3                       // appended
/// m.keys                             // ["E200S", "EWT", "EHY"]
/// for (k, v) in m { ... }            // in insertion order
/// ```
struct OrderedMap<Key: Hashable, Value> {
    /// Keys in insertion order.
    private(set) var keys: [Key]
    /// Values, parallel to ``keys``.
    private(set) var values: [Value]
    /// key -> position; nil while the map is small enough for a linear scan.
    private var index: [Key: Int]?

    /// Maps up to this size use a linear scan instead of a hash index.
    private static var linearScanLimit: Int { 12 }

    /// An empty map.
    init() {
        keys = []
        values = []
        index = nil
    }

    /// Builds a map from `(key, value)` pairs; a repeated key keeps its first position and
    /// its last value (Kotlin `toMap()` / `associate`).
    init<S: Sequence>(_ pairs: S) where S.Element == (Key, Value) {
        self.init()
        for (k, v) in pairs { self[k] = v }
    }

    /// Builds a map from labelled `(key:, value:)` pairs (e.g. another map's elements).
    init<S: Sequence>(_ pairs: S) where S.Element == (key: Key, value: Value) {
        self.init()
        for (k, v) in pairs { self[k] = v }
    }

    /// Reserves room for `n` entries.
    mutating func reserveCapacity(_ n: Int) {
        keys.reserveCapacity(n)
        values.reserveCapacity(n)
        if n > Self.linearScanLimit { buildIndex(capacity: n) }
    }

    // MARK: Lookup

    /// Number of entries.
    var count: Int { keys.count }

    /// True when there are no entries.
    var isEmpty: Bool { keys.isEmpty }

    /// Position of `key` in iteration order, or nil.
    func index(forKey key: Key) -> Int? {
        if let index { return index[key] }
        // Linear scan (small maps).
        var i = 0
        let n = keys.count
        while i < n {
            if keys[i] == key { return i }
            i += 1
        }
        return nil
    }

    /// True when `key` is present (Kotlin `containsKey` / `key in map`).
    func containsKey(_ key: Key) -> Bool { index(forKey: key) != nil }

    /// The value for `key`, or nil. Setting nil removes the key; setting a value on an existing
    /// key replaces it in place, on a new key appends it.
    subscript(key: Key) -> Value? {
        get {
            guard let i = index(forKey: key) else { return nil }
            return values[i]
        }
        set {
            if let newValue {
                updateValue(newValue, forKey: key)
            } else {
                removeValue(forKey: key)
            }
        }
    }

    /// The value for `key`, or `defaultValue` (Kotlin `getOrElse` / `getOrDefault`).
    subscript(key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
        guard let i = index(forKey: key) else { return defaultValue() }
        return values[i]
    }

    /// The `(key, value)` pair at position `i` in iteration order.
    func element(at i: Int) -> (key: Key, value: Value) { (keys[i], values[i]) }

    /// All entries in iteration order.
    var elements: [(key: Key, value: Value)] { Array(self) }

    /// The first entry, or nil.
    var first: (key: Key, value: Value)? { isEmpty ? nil : (keys[0], values[0]) }

    // MARK: Mutation

    /// Sets the value for `key` (`LinkedHashMap.put`): replaces in place, or appends.
    /// Returns the previous value.
    @discardableResult
    mutating func updateValue(_ value: Value, forKey key: Key) -> Value? {
        if let i = index(forKey: key) {
            let old = values[i]
            values[i] = value
            return old
        }
        keys.append(key)
        values.append(value)
        if index != nil {
            index![key] = keys.count - 1
        } else if keys.count > Self.linearScanLimit {
            buildIndex(capacity: keys.count)
        }
        return nil
    }

    /// Kotlin `putIfAbsent`: sets `value` only when `key` is missing. Returns the existing value.
    @discardableResult
    mutating func putIfAbsent(_ key: Key, _ value: Value) -> Value? {
        if let i = index(forKey: key) { return values[i] }
        updateValue(value, forKey: key)
        return nil
    }

    /// Removes `key` (O(n): later entries move up). Returns the removed value.
    @discardableResult
    mutating func removeValue(forKey key: Key) -> Value? {
        guard let i = index(forKey: key) else { return nil }
        keys.remove(at: i)
        let old = values.remove(at: i)
        if index != nil {
            if keys.count > Self.linearScanLimit {
                buildIndex(capacity: keys.count)
            } else {
                index = nil
            }
        }
        return old
    }

    /// Removes every entry.
    mutating func removeAll() {
        keys.removeAll()
        values.removeAll()
        index = nil
    }

    private mutating func buildIndex(capacity: Int) {
        var d = [Key: Int](minimumCapacity: capacity)
        for (i, k) in keys.enumerated() { d[k] = i }
        index = d
    }

    // MARK: Transforms (all keep the order)

    /// Kotlin `mapValues`.
    func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> OrderedMap<Key, T> {
        try OrderedMap<Key, T>(uncheckedUniqueKeys: keys, values: values.map(transform), index: index)
    }

    /// Kotlin `mapValues { (k, v) -> ... }`.
    func mapValuesWithKey<T>(_ transform: (Key, Value) throws -> T) rethrows -> OrderedMap<Key, T> {
        var out: [T] = []
        out.reserveCapacity(count)
        for i in 0..<count { out.append(try transform(keys[i], values[i])) }
        return OrderedMap<Key, T>(uncheckedUniqueKeys: keys, values: out, index: index)
    }

    /// Kotlin `mapNotNull` into a map / `filterValues` + `mapValues` in one go.
    func compactMapValues<T>(_ transform: (Value) throws -> T?) rethrows -> OrderedMap<Key, T> {
        var out = OrderedMap<Key, T>()
        for i in 0..<count {
            if let v = try transform(values[i]) { out.updateValue(v, forKey: keys[i]) }
        }
        return out
    }

    /// Kotlin `filter { (k, v) -> ... }`: the entries for which `isIncluded` is true, in order.
    func filter(_ isIncluded: ((key: Key, value: Value)) throws -> Bool) rethrows -> OrderedMap<Key, Value> {
        var out = OrderedMap<Key, Value>()
        for i in 0..<count where try isIncluded((keys[i], values[i])) {
            out.updateValue(values[i], forKey: keys[i])
        }
        return out
    }

    /// Kotlin `filterKeys`.
    func filterKeys(_ isIncluded: (Key) throws -> Bool) rethrows -> OrderedMap<Key, Value> {
        try filter { try isIncluded($0.key) }
    }

    /// Kotlin `filterValues`.
    func filterValues(_ isIncluded: (Value) throws -> Bool) rethrows -> OrderedMap<Key, Value> {
        try filter { try isIncluded($0.value) }
    }

    /// Kotlin `map + (k to v)`: a copy with `value` set for `key` (in place if present).
    func with(_ key: Key, _ value: Value) -> OrderedMap<Key, Value> {
        var copy = self
        copy.updateValue(value, forKey: key)
        return copy
    }

    /// Kotlin `map + other`: a copy with every entry of `other` put in turn.
    func merging(_ other: OrderedMap<Key, Value>) -> OrderedMap<Key, Value> {
        var copy = self
        for (k, v) in other { copy.updateValue(v, forKey: k) }
        return copy
    }

    /// A plain dictionary with the same entries (order is lost).
    func toDictionary() -> [Key: Value] {
        Dictionary(zip(keys, values), uniquingKeysWith: { _, last in last })
    }

    private init(uncheckedUniqueKeys keys: [Key], values: [Value], index: [Key: Int]?) {
        self.keys = keys
        self.values = values
        self.index = index
    }
}

// MARK: - Sequence

extension OrderedMap: Sequence {
    struct Iterator: IteratorProtocol {
        fileprivate let keys: [Key]
        fileprivate let values: [Value]
        fileprivate var i = 0

        mutating func next() -> (key: Key, value: Value)? {
            guard i < keys.count else { return nil }
            defer { i += 1 }
            return (keys[i], values[i])
        }
    }

    func makeIterator() -> Iterator { Iterator(keys: keys, values: values) }

    var underestimatedCount: Int { count }
}

// MARK: - Literals, equality, description

extension OrderedMap: ExpressibleByDictionaryLiteral {
    /// The literal's order is kept; a repeated key keeps its first position and last value.
    init(dictionaryLiteral elements: (Key, Value)...) {
        self.init(elements)
    }
}

extension OrderedMap: Equatable where Value: Equatable {
    /// Order-insensitive, like Kotlin `Map.equals`.
    static func == (lhs: OrderedMap, rhs: OrderedMap) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for i in 0..<lhs.count {
            guard let j = rhs.index(forKey: lhs.keys[i]), rhs.values[j] == lhs.values[i] else { return false }
        }
        return true
    }

    /// Order-sensitive equality: same entries in the same order.
    func orderedEquals(_ other: OrderedMap) -> Bool {
        keys == other.keys && values == other.values
    }
}

extension OrderedMap: Hashable where Value: Hashable {
    /// Order-independent (consistent with `==`).
    func hash(into hasher: inout Hasher) {
        var commutative = 0
        for i in 0..<count {
            var h = Hasher()
            h.combine(keys[i])
            h.combine(values[i])
            commutative ^= h.finalize()
        }
        hasher.combine(count)
        hasher.combine(commutative)
    }
}

extension OrderedMap: Sendable where Key: Sendable, Value: Sendable {}

extension OrderedMap: CustomStringConvertible {
    /// `{a=1, b=2}`, like Kotlin's `Map.toString()`.
    var description: String {
        "{" + zip(keys, values).map { "\($0)=\($1)" }.joined(separator: ", ") + "}"
    }
}
