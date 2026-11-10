import Foundation

/// A value a ``KeyValueStore`` holds: the types Android `SharedPreferences` offers.
enum KeyValueStoreValue: Sendable, Hashable {
    case string(String)
    case stringSet(Set<String>)
    /// Kotlin `Int` (`putInt` / `getInt`).
    case int(Int)
    /// Kotlin `Long` (`putLong` / `getLong`).
    case int64(Int64)
    case bool(Bool)
    /// Kotlin `Float` / `Double` (stored as Double).
    case double(Double)
}

/// One change in a batch (``KeyValueStore/apply(_:)``): a put, or a removal.
enum KeyValueEdit: Sendable, Hashable {
    case put(String, KeyValueStoreValue)
    case remove(String)
}

/// The port of Android `SharedPreferences`: a small persistent key-value store, one per
/// Kotlin prefs file (same file and key names: `SettingsStore.PREFS` = "kcna26.settings" ...).
///
/// - App: ``UserDefaultsStore`` (`UserDefaults(suiteName: <PREFS>)`).
/// - Tests and previews: ``InMemoryStore`` (Kotlin `InMemoryPrefs`).
///
/// Getters return nil when the key is absent (Kotlin `getInt(key, def)` -> `int(forKey:) ?? def`)
/// and also when it holds another kind of value (Android would throw ClassCastException): a
/// string, a string set, a Bool, an integer and a floating-point number are told apart by both
/// stores. One exception: ``UserDefaultsStore`` cannot tell an `Int` from an `Int64` (both are
/// plist integers), so there `int(forKey:)` and `int64(forKey:)` both read any integer. Read
/// with the type that was written (`putInt` -> `int`, `putLong` -> `int64`); the tests run on
/// ``InMemoryStore``, which is strict about that too, so a mismatch shows up there.
/// Writes are visible to the next read at once, like `editor.apply()`.
///
/// ```swift
/// prefs.set("EWT", forKey: "directionsFrom")              // putString(...).apply()
/// prefs.string(forKey: "directionsFrom") ?? "LIVE"         // getString(key, null) ?: "LIVE"
/// prefs.edit { e in                                        // edit().putInt(...).putLong(...).apply()
///     e.set(3, forKey: "probationVersion")
///     e.set(Int64(now), forKey: "probationSince")
/// }
/// ```
protocol KeyValueStore: AnyObject, Sendable {
    /// SharedPreferences `contains(key)`.
    func contains(_ key: String) -> Bool
    /// `getString(key, null)`.
    func string(forKey key: String) -> String?
    /// `getStringSet(key, null)` (a copy: Swift sets are values).
    func stringSet(forKey key: String) -> Set<String>?
    /// `getInt(key, ...)` (nil when absent).
    func int(forKey key: String) -> Int?
    /// `getLong(key, ...)` (nil when absent).
    func int64(forKey key: String) -> Int64?
    /// `getBoolean(key, ...)` (nil when absent).
    func bool(forKey key: String) -> Bool?
    /// `getFloat(key, ...)` / a double (nil when absent).
    func double(forKey key: String) -> Double?
    /// `edit()....apply()`: applies the edits in order, as one change.
    func apply(_ edits: [KeyValueEdit])
}

/// Collects the edits of one `prefs.edit { ... }` batch.
struct KeyValueEditor {
    private(set) var edits: [KeyValueEdit] = []

    mutating func set(_ value: String, forKey key: String) { edits.append(.put(key, .string(value))) }
    mutating func set(_ value: Set<String>, forKey key: String) { edits.append(.put(key, .stringSet(value))) }
    mutating func set(_ value: Int, forKey key: String) { edits.append(.put(key, .int(value))) }
    mutating func set(_ value: Int64, forKey key: String) { edits.append(.put(key, .int64(value))) }
    mutating func set(_ value: Bool, forKey key: String) { edits.append(.put(key, .bool(value))) }
    mutating func set(_ value: Double, forKey key: String) { edits.append(.put(key, .double(value))) }
    /// Editor `remove(key)`.
    mutating func removeValue(forKey key: String) { edits.append(.remove(key)) }
}

extension KeyValueStore {
    /// `edit().putString(key, value).apply()`.
    func set(_ value: String, forKey key: String) { apply([.put(key, .string(value))]) }
    /// `edit().putStringSet(key, value).apply()`.
    func set(_ value: Set<String>, forKey key: String) { apply([.put(key, .stringSet(value))]) }
    /// `edit().putInt(key, value).apply()`.
    func set(_ value: Int, forKey key: String) { apply([.put(key, .int(value))]) }
    /// `edit().putLong(key, value).apply()`.
    func set(_ value: Int64, forKey key: String) { apply([.put(key, .int64(value))]) }
    /// `edit().putBoolean(key, value).apply()`.
    func set(_ value: Bool, forKey key: String) { apply([.put(key, .bool(value))]) }
    /// `edit().putFloat(key, value).apply()` (as a Double).
    func set(_ value: Double, forKey key: String) { apply([.put(key, .double(value))]) }
    /// `edit().remove(key).apply()`.
    func removeValue(forKey key: String) { apply([.remove(key)]) }

    /// `edit().(several puts/removes).apply()` as one batch.
    func edit(_ build: (inout KeyValueEditor) -> Void) {
        var e = KeyValueEditor()
        build(&e)
        if !e.edits.isEmpty { apply(e.edits) }
    }
}

// MARK: - InMemoryStore

/// In-memory ``KeyValueStore`` for unit tests and SwiftUI previews (Kotlin `InMemoryPrefs`).
/// Thread-safe. No Kotlin main code registers change listeners, so there are none here.
final class InMemoryStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var map: [String: KeyValueStoreValue]

    init(_ initial: [String: KeyValueStoreValue] = [:]) {
        map = initial
    }

    /// Every entry (Kotlin `getAll()`).
    var all: [String: KeyValueStoreValue] {
        lock.lock()
        defer { lock.unlock() }
        return map
    }

    private func read(_ key: String) -> KeyValueStoreValue? {
        lock.lock()
        defer { lock.unlock() }
        return map[key]
    }

    func contains(_ key: String) -> Bool { read(key) != nil }

    func string(forKey key: String) -> String? {
        if case .string(let v)? = read(key) { return v }
        return nil
    }

    func stringSet(forKey key: String) -> Set<String>? {
        if case .stringSet(let v)? = read(key) { return v }
        return nil
    }

    func int(forKey key: String) -> Int? {
        if case .int(let v)? = read(key) { return v }
        return nil
    }

    func int64(forKey key: String) -> Int64? {
        if case .int64(let v)? = read(key) { return v }
        return nil
    }

    func bool(forKey key: String) -> Bool? {
        if case .bool(let v)? = read(key) { return v }
        return nil
    }

    func double(forKey key: String) -> Double? {
        if case .double(let v)? = read(key) { return v }
        return nil
    }

    func apply(_ edits: [KeyValueEdit]) {
        lock.lock()
        defer { lock.unlock() }
        for e in edits {
            switch e {
            case let .put(k, v): map[k] = v
            case let .remove(k): map.removeValue(forKey: k)
            }
        }
    }
}

// MARK: - UserDefaultsStore

/// The app's ``KeyValueStore``: `UserDefaults(suiteName:)`, one suite per Kotlin prefs file
/// (`UserDefaultsStore(suiteName: SettingsStore.PREFS)`), so each lives in its own plist like
/// each SharedPreferences file. UserDefaults is thread-safe.
///
/// Storage: strings, numbers and bools as themselves; a string set as a sorted `[String]`.
/// Reads are typed like ``InMemoryStore``'s (a Bool is not an integer, a Double is not an
/// integer, an integer is not a Double), except that Int and Int64 are the same plist integer
/// (see ``KeyValueStore``).
final class UserDefaultsStore: KeyValueStore, @unchecked Sendable {
    /// The suite name (the Kotlin PREFS name).
    let suiteName: String
    let defaults: UserDefaults

    /// `UserDefaults(suiteName:)`; falls back to `.standard` for a name UserDefaults refuses
    /// (the app's own bundle id), which no PREFS name is.
    init(suiteName: String) {
        self.suiteName = suiteName
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    func contains(_ key: String) -> Bool { defaults.object(forKey: key) != nil }

    func string(forKey key: String) -> String? { defaults.object(forKey: key) as? String }

    func stringSet(forKey key: String) -> Set<String>? {
        guard let o = defaults.object(forKey: key) else { return nil }
        if let a = o as? [String] { return Set(a) }
        if let a = o as? [Any] {
            let strings = a.compactMap { $0 as? String }
            return strings.count == a.count ? Set(strings) : nil
        }
        return nil
    }

    func int(forKey key: String) -> Int? { number(key, .integer)?.intValue }

    func int64(forKey key: String) -> Int64? { number(key, .integer)?.int64Value }

    func bool(forKey key: String) -> Bool? { number(key, .boolean)?.boolValue }

    func double(forKey key: String) -> Double? { number(key, .floatingPoint)?.doubleValue }

    private enum NumberKind { case boolean, integer, floatingPoint }

    /// The stored number when it is of `kind`. NSNumber bridging would happily read a Bool as 1,
    /// 42 as `true` or 2.75 as 2, so the kind is checked first: a Bool is the CFBoolean
    /// singleton (`NSNumber(value: true)` is the same object, on Darwin and Linux); a
    /// floating-point number has objCType "d" or "f"; anything else is an integer.
    private func number(_ key: String, _ kind: NumberKind) -> NSNumber? {
        guard let n = defaults.object(forKey: key) as? NSNumber else { return nil }
        let actual: NumberKind
        if n === NSNumber(value: true) || n === NSNumber(value: false) {
            actual = .boolean
        } else {
            let t = n.objCType.pointee
            actual = (t == 0x64 || t == 0x66) ? .floatingPoint : .integer // "d" "f"
        }
        return actual == kind ? n : nil
    }

    func apply(_ edits: [KeyValueEdit]) {
        for e in edits {
            switch e {
            case let .put(k, .string(v)): defaults.set(v, forKey: k)
            case let .put(k, .stringSet(v)): defaults.set(v.sorted(), forKey: k)
            case let .put(k, .int(v)): defaults.set(v, forKey: k)
            case let .put(k, .int64(v)): defaults.set(NSNumber(value: v), forKey: k)
            case let .put(k, .bool(v)): defaults.set(v, forKey: k)
            case let .put(k, .double(v)): defaults.set(v, forKey: k)
            case let .remove(k): defaults.removeObject(forKey: k)
            }
        }
    }

    /// Deletes the whole suite (tests; a debug "reset" action).
    func removeAll() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
